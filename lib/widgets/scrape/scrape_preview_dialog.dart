import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_metadata.dart';
import '../../services/metadata/nfo_merge.dart';
import '../../services/scrape/image_downloader.dart';
import '../../services/scrape/scrape_service.dart';
import '../../theme/app_theme.dart';
import '../dialogs/input_dialog.dart';
import 'metadata_field_labels.dart';

/// Everything the caller needs to run `ScrapeService.commit`, as confirmed by
/// the user. Returned only when they press Write — cancelling returns null and
/// nothing has touched disk.
class ScrapeCommitDecision {
  /// The reviewed metadata, including any inline edits.
  final MediaMetadata metadata;
  final ImageSelection images;

  /// Back up an NFO that is about to be replaced, and record an undo manifest.
  final bool backup;
  final String nfoFileName;
  final String targetDir;

  /// Whether to store `ScrapeResult.learnedRecipe`. Always false when tier 3
  /// did not run — a learned recipe reaching `RecipeStore` is the one thing
  /// this dialog exists to gate.
  final bool saveRecipe;

  const ScrapeCommitDecision({
    required this.metadata,
    required this.images,
    required this.backup,
    required this.nfoFileName,
    required this.targetDir,
    this.saveRecipe = false,
  });
}

/// Reviewable diff between the NFO on disk and a fresh scrape.
///
/// This is the module's only gate, the same role `OrganizePreviewDialog` plays
/// for the organize pipeline: every edit here happens in memory and the single
/// disk write is whatever the caller does with the returned decision.
Future<ScrapeCommitDecision?> showScrapePreviewDialog(
  BuildContext context, {
  required ScrapeResult result,
  required String defaultTargetDir,
  required String defaultNfoFileName,
}) => showDialog<ScrapeCommitDecision>(
  context: context,
  builder: (_) => ScrapePreviewDialog(
    result: result,
    defaultTargetDir: defaultTargetDir,
    defaultNfoFileName: defaultNfoFileName,
  ),
);

class ScrapePreviewDialog extends StatefulWidget {
  final ScrapeResult result;
  final String defaultTargetDir;
  final String defaultNfoFileName;

  const ScrapePreviewDialog({
    super.key,
    required this.result,
    required this.defaultTargetDir,
    required this.defaultNfoFileName,
  });

  @override
  State<ScrapePreviewDialog> createState() => _ScrapePreviewDialogState();
}

class _ScrapePreviewDialogState extends State<ScrapePreviewDialog> {
  late NfoMergePlan _plan = widget.result.mergePlan;

  /// Edited in place, exactly like `OrganizeAction.target` is in the organize
  /// preview. The result object is discarded on cancel, so in-memory edits can
  /// never reach disk on their own.
  late final MediaMetadata _scraped = widget.result.scraped;

  late final TextEditingController _targetDir = TextEditingController(
    text: widget.defaultTargetDir,
  );
  late final TextEditingController _nfoName = TextEditingController(
    text: widget.defaultNfoFileName,
  );

  bool _backup = true;
  bool _poster = true;
  bool _fanart = true;

  /// Pre-ticked, because this dialog *is* the human review the learned-recipe
  /// rule asks for: the values are on screen with their LLM badges, and the
  /// user is about to accept them. Unticking keeps the metadata and throws the
  /// recipe away.
  bool _saveRecipe = true;

  /// Stills are tracked by URL, not by index: a decision change can reorder or
  /// lengthen `extraFanartUrls` (merge puts the existing entries first), and an
  /// index captured before that would silently select a different picture.
  late Set<String> _stills = _defaultStills();

  @override
  void dispose() {
    _targetDir.dispose();
    _nfoName.dispose();
    super.dispose();
  }

  MediaMetadata get _merged =>
      NfoMerge.resolve(widget.result.existing, _scraped, _plan);

  Set<String> _defaultStills() {
    final urls = _merged.extraFanartUrls;
    // The same default `ImageSelection` uses, resolved here so the grid and the
    // download agree without a second hardcoded count.
    final wanted = const ImageSelection().resolveExtra(urls.length);
    return {
      for (var i = 0; i < urls.length; i++)
        if (wanted.contains(i)) urls[i],
    };
  }

  /// Rows to show: only fields whose two sides differ. Fields that already
  /// match need no decision, and listing them would bury the ones that do.
  List<String> get _rows => [
    for (final f in MetadataField.all)
      if (_plan.decisions.containsKey(f)) f,
  ];

  void _setDecision(String field, MergeDecision decision) =>
      setState(() => _plan = _plan.withDecision(field, decision));

  void _applyPreset(MergePreset preset) =>
      setState(() => _plan = _plan.withPreset(preset));

  Future<void> _edit(String field) async {
    final l10n = AppLocalizations.of(context)!;
    final label = metadataFieldLabel(l10n, field);
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => InputDialog(
        title: l10n.scrapeEditValue(label),
        labelText: label,
        initialValue: metadataEditText(_scraped, field),
        actionLabel: MaterialLocalizations.of(context).saveButtonLabel,
        maxLines: isFieldMultiline(field) ? 10 : 1,
      ),
    );
    if (edited == null || !mounted) return;
    final value = parseMetadataValue(field, edited);
    if (value == null) return;
    setState(() {
      _scraped.set(field, value, FieldOrigin.manual);
      // They just typed what they want written, so "keep" would throw it away.
      _plan = _plan.withDecision(field, MergeDecision.replace);
      _stills = _defaultStills();
    });
  }

  void _commit() {
    final urls = _merged.extraFanartUrls;
    Navigator.pop(
      context,
      ScrapeCommitDecision(
        metadata: _merged,
        images: ImageSelection(
          poster: _poster,
          fanart: _fanart,
          extraFanart: {
            for (var i = 0; i < urls.length; i++)
              if (_stills.contains(urls[i])) i,
          },
        ),
        backup: _backup,
        nfoFileName: _nfoName.text.trim().isEmpty
            ? widget.defaultNfoFileName
            : _nfoName.text.trim(),
        targetDir: _targetDir.text.trim().isEmpty
            ? widget.defaultTargetDir
            : _targetDir.text.trim(),
        saveRecipe: widget.result.learnedRecipe != null && _saveRecipe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
        child: Column(
          children: [
            _header(l10n, scheme),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            _toolbar(l10n),
            Expanded(child: _body(l10n, scheme)),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            _footer(l10n, scheme),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(AppLocalizations l10n, ColorScheme scheme) {
    final imageCount =
        (_merged.posterUrl != null ? 1 : 0) +
        (_merged.fanartUrl != null ? 1 : 0) +
        _merged.extraFanartUrls.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.travel_explore_outlined,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _merged.title ?? l10n.scrapePreviewTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.scrapePreviewSubtitle(_rows.length, imageCount),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _provenance(l10n, scheme),
          for (final note in widget.result.notes) ...[
            const SizedBox(height: 8),
            _NoteBanner(text: _noteText(l10n, note)),
          ],
        ],
      ),
    );
  }

  Widget _provenance(AppLocalizations l10n, ColorScheme scheme) {
    final recipe = widget.result.recipe;
    final style = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Row(
      children: [
        Text('${l10n.scrapeSource}: ', style: style),
        Flexible(
          child: Tooltip(
            message: widget.result.pageUrl.toString(),
            child: Text(
              widget.result.pageUrl.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          '${l10n.scrapeRecipeName}: ${recipe?.domain ?? l10n.scrapeRecipeNone}',
          style: style,
        ),
      ],
    );
  }

  static String _noteText(AppLocalizations l10n, ScrapeNote note) =>
      switch (note) {
        ScrapeNote.siteWideStructuredDataIgnored =>
          l10n.scrapeNoteSiteWideIgnored,
        ScrapeNote.noRecipe => l10n.scrapeNoteNoRecipe,
        ScrapeNote.degradedEncoding => l10n.scrapeNoteDegradedEncoding,
        ScrapeNote.recipeProducedNothing => l10n.scrapeNoteRecipeStale,
        ScrapeNote.recipeLearned => l10n.scrapeNoteRecipeLearned,
        ScrapeNote.recipeLearningFailed => l10n.scrapeNoteRecipeLearningFailed,
        ScrapeNote.redirectedAway => l10n.scrapeNoteRedirectedAway,
        ScrapeNote.llmExtracted => l10n.scrapeNoteLlmExtracted,
        ScrapeNote.llmExtractionFailed => l10n.scrapeNoteLlmExtractionFailed,
      };

  // ── Preset toolbar ────────────────────────────────────────────────────────

  Widget _toolbar(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
    child: Row(
      children: [
        OutlinedButton(
          onPressed: () => _applyPreset(MergePreset.fillEmptyOnly),
          child: Text(l10n.scrapePresetFillEmpty),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _applyPreset(MergePreset.replaceAll),
          child: Text(l10n.scrapePresetReplaceAll),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _applyPreset(MergePreset.keepAll),
          child: Text(l10n.scrapePresetKeepAll),
        ),
      ],
    ),
  );

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _body(AppLocalizations l10n, ColorScheme scheme) {
    final rows = _rows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                l10n.scrapeNoChanges,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else ...[
          _ColumnHeader(l10n: l10n),
          for (final field in rows)
            _FieldRow(
              field: field,
              existing: widget.result.existing,
              scraped: _scraped,
              decision: _plan.decisionFor(field),
              onDecision: (d) => _setDecision(field, d),
              onEdit: isFieldEditable(field) ? () => _edit(field) : null,
            ),
        ],
        const SizedBox(height: 22),
        _artwork(l10n, scheme),
      ],
    );
  }

  Widget _artwork(AppLocalizations l10n, ColorScheme scheme) {
    final merged = _merged;
    final stills = merged.extraFanartUrls;
    final total =
        (merged.posterUrl != null ? 1 : 0) +
        (merged.fanartUrl != null ? 1 : 0) +
        stills.length;
    if (total == 0) {
      return Text(
        l10n.scrapeImageNone,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      );
    }
    final selected =
        (merged.posterUrl != null && _poster ? 1 : 0) +
        (merged.fanartUrl != null && _fanart ? 1 : 0) +
        stills.where(_stills.contains).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.scrapeImages,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.scrapeImageCount(selected, total),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // URLs only, no thumbnails: a product page can offer 30+ stills and
        // pre-fetching them all to draw a grid would defeat the per-host rate
        // limit the fetcher exists to enforce.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (merged.posterUrl != null)
              _ImageChip(
                label: l10n.scrapeImagePoster,
                url: merged.posterUrl!,
                selected: _poster,
                onChanged: (v) => setState(() => _poster = v),
              ),
            if (merged.fanartUrl != null)
              _ImageChip(
                label: l10n.scrapeImageFanart,
                url: merged.fanartUrl!,
                selected: _fanart,
                onChanged: (v) => setState(() => _fanart = v),
              ),
            for (var i = 0; i < stills.length; i++)
              _ImageChip(
                label: l10n.scrapeImageExtra(i + 1),
                url: stills[i],
                selected: _stills.contains(stills[i]),
                onChanged: (v) => setState(() {
                  if (v) {
                    _stills.add(stills[i]);
                  } else {
                    _stills.remove(stills[i]);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _footer(AppLocalizations l10n, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _targetDir,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.scrapeTargetFolder,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nfoName,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.scrapeNfoFileName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.result.learnedRecipe != null)
          Row(
            children: [
              Checkbox(
                value: _saveRecipe,
                onChanged: (v) => setState(() => _saveRecipe = v ?? true),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  l10n.scrapeSaveRecipe(widget.result.learnedRecipe!.domain),
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        Row(
          children: [
            Checkbox(
              value: _backup,
              onChanged: (v) => setState(() => _backup = v ?? true),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                l10n.scrapeWriteBackup,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _commit,
              icon: const Icon(Icons.save_outlined, size: 17),
              label: Text(l10n.scrapeWrite),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ── Field table ─────────────────────────────────────────────────────────────

const double _labelWidth = 118;

/// Wide enough for the three-segment picker (Keep · Replace · Merge) in both
/// locales. Fixed rather than intrinsic so every row's picker lines up.
const double _decisionWidth = 280;

class _ColumnHeader extends StatelessWidget {
  final AppLocalizations l10n;
  const _ColumnHeader({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(l10n.scrapeColumnField, style: style),
          ),
          Expanded(
            flex: 3,
            child: Text(l10n.scrapeColumnExisting, style: style),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(l10n.scrapeColumnScraped, style: style),
          ),
          SizedBox(
            width: _decisionWidth,
            child: Text(l10n.scrapeColumnDecision, style: style),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String field;
  final MediaMetadata? existing;
  final MediaMetadata scraped;
  final MergeDecision decision;
  final ValueChanged<MergeDecision> onDecision;

  /// Null for fields the inline editor refuses (see `isFieldEditable`).
  final VoidCallback? onEdit;

  const _FieldRow({
    required this.field,
    required this.existing,
    required this.scraped,
    required this.decision,
    required this.onDecision,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final origin = scraped.origins[field];
    final existingText = metadataValueText(existing, field);
    final scrapedText = metadataValueText(scraped, field);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                metadataFieldLabel(l10n, field),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _Value(text: existingText, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Value(text: scrapedText)),
                if (origin != null) ...[
                  const SizedBox(width: 6),
                  _OriginBadge(origin: origin),
                ],
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.edit,
                    onPressed: onEdit,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: _decisionWidth,
            child: _DecisionPicker(
              field: field,
              value: decision,
              onChanged: onDecision,
            ),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  final String text;
  final Color? color;
  const _Value({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (text.isEmpty) {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 12.5,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );
    }
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 400),
      child: Text(
        text,
        // Three lines is enough to tell a full synopsis from a truncated one
        // without letting one field push the rest of the table off screen.
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, height: 1.35, color: color),
      ),
    );
  }
}

/// Where the scraped value came from. LLM-sourced values get a warning color:
/// those are the ones a human has to actually look at.
class _OriginBadge extends StatelessWidget {
  final FieldOrigin origin;
  const _OriginBadge({required this.origin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final color = origin == FieldOrigin.llm
        ? const Color(0xFFE0852C)
        : origin == FieldOrigin.manual
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        fieldOriginLabel(l10n, origin),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Keep / Replace, plus Merge on list fields.
class _DecisionPicker extends StatelessWidget {
  final String field;
  final MergeDecision value;
  final ValueChanged<MergeDecision> onChanged;

  const _DecisionPicker({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final scheme = Theme.of(context).colorScheme;

    final options = <(MergeDecision, String)>[
      (MergeDecision.keep, l10n.scrapeDecisionKeep),
      (MergeDecision.replace, l10n.scrapeDecisionReplace),
      if (MetadataField.listFields.contains(field))
        (MergeDecision.merge, l10n.scrapeDecisionMerge),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (decision, label) in options)
            Material(
              color: decision == value ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(decision),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: decision == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: decision == value
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Artwork + notes ─────────────────────────────────────────────────────────

class _ImageChip extends StatelessWidget {
  final String label;
  final String url;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _ImageChip({
    required this.label,
    required this.url,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: url,
      waitDuration: const Duration(milliseconds: 400),
      child: FilterChip(
        selected: selected,
        onSelected: onChanged,
        showCheckmark: true,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _NoteBanner extends StatelessWidget {
  final String text;
  const _NoteBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFE0852C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 15, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
