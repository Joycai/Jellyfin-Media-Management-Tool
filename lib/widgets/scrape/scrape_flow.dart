/// The scrape entry point, shared by the context menu and the shortcut.
///
/// Lives outside `HomeScreen` for the same reason `renameEntry` does: two call
/// sites, one behaviour. The flow is panel → review → commit task, and **only
/// the commit task writes anything**.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../services/file_label_service.dart';
import '../../services/history_service.dart';
import '../../services/metadata/metadata_writer.dart';
import '../../services/scrape/media_code.dart';
import '../../services/scrape/recipe_store.dart';
import '../../services/scrape/scrape_service.dart';
import '../../services/task_service.dart';
import 'batch_scrape_dialog.dart';
import 'scrape_panel.dart';

/// Whether the scrape action makes sense for [entry]: a video, or a folder that
/// might hold one. Extension classification goes through [FileLabelService] so
/// there is no second list of video extensions to keep in sync.
bool canScrape(FileEntry entry) =>
    entry.isDirectory || FileLabelService.getLabel(entry.extension) == 'Video';

/// Runs the whole scrape flow for [target] (or for [baseDir] when there is no
/// focused entry).
///
/// Two modal steps, and nothing in between: set the scrape up and watch it run
/// in [ScrapePanel], then review what came back. The scrape used to be a
/// background task that announced itself with a SnackBar the user had to catch
/// and click; that bought nothing — they opened the dialog seconds ago and are
/// waiting for it — while costing a stale-context crash and two extra
/// surfaces. The batch refresh is still a task, because *that* one is worth
/// walking away from.
Future<void> startScrapeFlow(
  BuildContext context, {
  FileEntry? target,
  required String baseDir,
}) async {
  final where = _resolveTarget(target, baseDir);

  final panel = await showScrapePanel(
    context,
    targetDir: where.targetDir,
    nfoFileName: where.nfoFileName,
    label: where.label,
    suggestedKeyword: detectMediaCode(where.label),
  );
  if (panel == null || !context.mounted) return;

  await _commit(context, panel, where.label);
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

/// Starts the write task for a scrape the user confirmed in the panel.
///
/// Everything up to here happened in memory; this is the first thing that can
/// touch disk. Closing the panel instead of pressing Write means none of it
/// runs — including saving a recipe the model just invented.
Future<void> _commit(
  BuildContext context,
  ScrapePanelResult panel,
  String label,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final tasks = context.read<TaskService>();
  final scraper = context.read<ScrapeService>();
  final history = context.read<HistoryService>();
  final recipes = context.read<RecipeStore>();
  final result = panel.result;
  final decision = panel.decision;

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
    label: label,
    metadata: decision.metadata,
    pageUrl: result.pageUrl,
    targetDir: decision.targetDir,
    nfoFileName: decision.nfoFileName,
    recipe: result.recipe,
    images: decision.images,
    backupDir: backupDir,
    // The grid already downloaded these to draw thumbnails.
    imageCache: panel.cache,
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
