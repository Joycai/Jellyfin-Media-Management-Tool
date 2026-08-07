/// The scrape entry point, shared by the context menu and the shortcut.
///
/// Lives outside `HomeScreen` for the same reason `renameEntry` does: two call
/// sites, one behaviour. The flow is URL dialog → background task → review →
/// commit task, and **only the commit task writes anything**.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../services/ai_service.dart';
import '../../services/file_label_service.dart';
import '../../services/history_service.dart';
import '../../services/metadata/metadata_writer.dart';
import '../../services/scrape/media_code.dart';
import '../../services/scrape/recipe_learner.dart';
import '../../services/scrape/recipe_store.dart';
import '../../services/scrape/scrape_service.dart';
import '../../services/task_service.dart';
import 'batch_scrape_dialog.dart';
import 'scrape_preview_dialog.dart';
import 'scrape_url_dialog.dart';

/// Whether the scrape action makes sense for [entry]: a video, or a folder that
/// might hold one. Extension classification goes through [FileLabelService] so
/// there is no second list of video extensions to keep in sync.
bool canScrape(FileEntry entry) =>
    entry.isDirectory || FileLabelService.getLabel(entry.extension) == 'Video';

/// Runs the whole scrape flow for [target] (or for [baseDir] when there is no
/// focused entry).
///
/// [onShowTasks], when given, adds a "go to Tasks" action to the started
/// notice; the context menu has no way to switch sections, so it passes null.
Future<void> startScrapeFlow(
  BuildContext context, {
  FileEntry? target,
  required String baseDir,
  VoidCallback? onShowTasks,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final tasks = context.read<TaskService>();
  final scraper = context.read<ScrapeService>();
  final ai = context.read<AiService>();

  final where = _resolveTarget(target, baseDir);

  final input = await showScrapeUrlDialog(
    context,
    targetLabel: where.label,
    suggestedKeyword: detectMediaCode(where.label),
  );
  if (input == null) return;

  tasks.startScrape(
    scraper: scraper,
    label: where.label,
    url: input.url,
    pastedHtml: input.pastedHtml,
    targetDir: where.targetDir,
    nfoFileName: where.nfoFileName,
    // Tier 3 is only offered when there is an endpoint to ask. Without one the
    // ladder simply stops at tier 2 and the user falls back to pasting HTML.
    learner: ai.isConfigured ? RecipeLearner(ai.buildProvider()) : null,
    onDone: (result) {
      // Fire-and-forget work: by now the user may be anywhere in the app, so
      // this offers the review rather than stealing focus with a dialog.
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.scrapeReady),
          persist: false,
          action: SnackBarAction(
            label: l10n.scrapeReview,
            onPressed: () => _review(messenger.context, result, where),
          ),
        ),
      );
    },
  );

  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.scrapeStarted),
      // A SnackBar with an action defaults to persist:true; this is a notice,
      // not a question, so opt back into auto-dismiss.
      persist: false,
      action: onShowTasks == null
          ? null
          : SnackBarAction(label: l10n.tabTasks, onPressed: onShowTasks),
    ),
  );
}

/// Refreshes every title under [dir] whose NFO records where it came from.
///
/// The counterpart to [startScrapeFlow]: no URL is asked for because each NFO
/// already carries one, and no per-title diff is shown because a batch cannot
/// meaningfully offer one — the confirmation dialog is the gate.
Future<void> startBatchScrapeFlow(
  BuildContext context, {
  required String dir,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final tasks = context.read<TaskService>();
  final scraper = context.read<ScrapeService>();
  final history = context.read<HistoryService>();

  final targets = await scraper.findRescrapeTargets(dir);
  if (!context.mounted) return;

  final decision = await showBatchScrapeDialog(context, targets: targets);
  if (decision == null || decision.targets.isEmpty) return;

  final backupDir = decision.backup ? await ScrapeService.newBackupDir() : null;

  tasks.startBatchScrape(
    scraper: scraper,
    label: p.basename(dir),
    targets: decision.targets,
    images: decision.images,
    backupDir: backupDir,
    onDone: (result) {
      if (decision.backup) {
        // One manifest for the whole batch: the user thinks of this as a
        // single operation, so undo should too.
        unawaited(
          history.recordScrape(
            baseDir: dir,
            created: result.created,
            restored: result.restored,
            backupDir: backupDir,
          ),
        );
      }
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.hasFailures
                ? l10n.batchScrapePartial(result.succeeded, result.failed)
                : l10n.batchScrapeDone(result.succeeded),
          ),
        ),
      );
    },
  );

  messenger.showSnackBar(SnackBar(content: Text(l10n.batchScrapeStarted)));
}

/// Opens the preview and, if confirmed, starts the write task.
Future<void> _review(
  BuildContext context,
  ScrapeResult result,
  _ScrapeTarget where,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final tasks = context.read<TaskService>();
  final scraper = context.read<ScrapeService>();
  final history = context.read<HistoryService>();
  final recipes = context.read<RecipeStore>();

  final decision = await showScrapePreviewDialog(
    context,
    result: result,
    defaultTargetDir: where.targetDir,
    defaultNfoFileName: where.nfoFileName,
  );
  // Cancelled: not one byte has been written, and none will be — and a recipe
  // the model just invented is discarded with it.
  if (decision == null) return;

  // The only path from tier 3 into scrapers.json, and it runs after a human
  // looked at what the recipe extracted.
  final learned = result.learnedRecipe;
  if (decision.saveRecipe && learned != null) {
    await recipes.save(learned);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.scrapeRecipeSaved(learned.domain))),
    );
  }

  // One checkbox, both halves of undo: the backup copies that make an
  // overwritten NFO recoverable, and the manifest that says what to reverse.
  final backupDir = decision.backup ? await ScrapeService.newBackupDir() : null;

  tasks.startScrapeCommit(
    scraper: scraper,
    label: where.label,
    metadata: decision.metadata,
    pageUrl: result.pageUrl,
    targetDir: decision.targetDir,
    nfoFileName: decision.nfoFileName,
    recipe: result.recipe,
    images: decision.images,
    backupDir: backupDir,
    onDone: (written) {
      if (decision.backup) {
        // Best-effort and off the critical path: the files are already on disk
        // whether or not we manage to describe them.
        unawaited(
          history.recordScrape(
            baseDir: decision.targetDir,
            created: written.createdPaths,
            restored: written.restorablePaths,
            backupDir: backupDir,
          ),
        );
      }
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written.succeeded == 0
                ? l10n.scrapeWriteFailed(
                    written.failures.values.firstOrNull ?? '',
                  )
                : written.hasFailures
                // Counts, not the first error — the batch rule.
                ? l10n.scrapeWritePartial(written.succeeded, written.failed)
                : l10n.scrapeWriteSucceeded(written.succeeded),
          ),
        ),
      );
    },
  );

  if (!messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(l10n.scrapeCommitStarted)));
}

/// Where the metadata will land, and what to call the operation.
class _ScrapeTarget {
  final String targetDir;
  final String nfoFileName;

  /// Basename used for the task label and for code detection.
  final String label;

  const _ScrapeTarget({
    required this.targetDir,
    required this.nfoFileName,
    required this.label,
  });
}

/// A focused video writes `<video base name>.nfo` beside itself; a folder (or
/// no selection at all) writes `movie.nfo` inside it. Both are names Jellyfin
/// accepts — see [MetadataWriter.nfoNameForVideo] for why the per-video form is
/// preferred where there is a video to name it after.
_ScrapeTarget _resolveTarget(FileEntry? target, String baseDir) {
  if (target != null && !target.isDirectory) {
    return _ScrapeTarget(
      targetDir: p.dirname(target.path),
      nfoFileName: MetadataWriter.nfoNameForVideo(target.name),
      label: target.name,
    );
  }
  final dir = target?.path ?? baseDir;
  return _ScrapeTarget(
    targetDir: dir,
    nfoFileName: 'movie.nfo',
    label: p.basename(dir),
  );
}
