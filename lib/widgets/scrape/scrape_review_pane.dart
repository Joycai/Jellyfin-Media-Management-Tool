import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_metadata.dart';
import '../../services/metadata/nfo_merge.dart';
import '../../services/scrape/image_cache.dart';
import '../../services/scrape/image_role.dart';
import '../../services/scrape/image_downloader.dart';
import '../../services/scrape/scrape_service.dart';
import '../../services/metadata/nfo_writer.dart';
import '../../theme/app_theme.dart';
import '../dialogs/input_dialog.dart';
import '../glass/glass_dialog.dart';
import 'image_gallery.dart';
import 'metadata_field_labels.dart';

/// Everything the caller needs to run `ScrapeService.commit`, as confirmed by
/// the user. Returned only when they press Write — cancelling returns null and
/// nothing has touched disk.
class ScrapeCommitDecision {
  /// The reviewed metadata, including any inline edits.
  final MediaMetadata metadata;
  final ImageSelection images;

  /// url -> the file name each selected image will be written under, as
  /// decided by its role. Richer than [images], which cannot express "keep the
  /// server's own name"; the commit prefers this when present.
  final Map<String, String> imageNames;

  /// Back up an NFO that is about to be replaced, and record an undo manifest.
  final bool backup;
  final String nfoFileName;
  final String targetDir;

  /// Movie or series: decides the root element, and is what made
  /// [nfoFileName] `movie.nfo` or `tvshow.nfo` in the panel.
  final NfoKind kind;

  /// Whether to store `ScrapeResult.learnedRecipe`. Always false when tier 3
  /// did not run — a learned recipe reaching `RecipeStore` is the one thing
  /// this dialog exists to gate.
  final bool saveRecipe;

  const ScrapeCommitDecision({
    required this.metadata,
    required this.images,
    this.imageNames = const {},
    required this.backup,
    required this.nfoFileName,
    required this.targetDir,
    this.kind = NfoKind.movie,
    this.saveRecipe = false,
  });
}

/// Reviewable diff between the NFO on disk and a fresh scrape, plus the
/// artwork picker.
///
/// This is the module's only gate, the same role `OrganizePreviewDialog` plays
/// for the organize pipeline: every edit here happens in memory and the single
/// disk write is whatever the caller does with the returned decision.
///
/// A pane rather than a dialog. It used to be its own route, reached from a
/// SnackBar; it is now the third stage of [ScrapePanel], so that setting a
/// scrape up, running it and reviewing it are one window instead of three.
/// Hence the callbacks — nothing here pops a route.
class ScrapeReviewPane extends StatefulWidget {
  final ScrapeResult result;
  final String defaultTargetDir;
  final String defaultNfoFileName;

  /// Chosen in the setup stage; carried through untouched.
  final NfoKind kind;

  /// Shared with the panel so a thumbnail already fetched is not fetched again
  /// when the write runs.
  final ScrapeImageCache cache;

  /// Rebuilt by the panel as cached images arrive; null once the sweep is done.
  final int? loadingImages;

  final ValueChanged<ScrapeCommitDecision> onSubmit;

  /// Return to the setup stage, keeping the scrape.
  final VoidCallback onBack;

  /// Abandon the whole panel. Separate from [onBack] because "this result is
  /// wrong, let me change the URL" and "I am done here" are different
  /// intentions, and making the second one two clicks was a dead end.
  final VoidCallback onCancel;

  /// Write the ticked images to the folder now, without touching the NFO.
  /// Takes the same `url -> file name` map the commit would use.
  final Future<void> Function(Map<String, String> imageNames) onSaveImages;

  const ScrapeReviewPane({
    super.key,
    required this.result,
    required this.defaultTargetDir,
    required this.defaultNfoFileName,
    this.kind = NfoKind.movie,
    required this.cache,
    required this.onSubmit,
    required this.onBack,
    required this.onCancel,
    required this.onSaveImages,
    this.loadingImages,
  });

  @override
  State<ScrapeReviewPane> createState() => _ScrapeReviewPaneState();
}

class _ScrapeReviewPaneState extends State<ScrapeReviewPane> {
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

  /// Which preset chip lit last. Cosmetic only — a per-row change clears it,
  /// because the plan no longer matches any preset.
  MergePreset? _activePreset;

  /// Pre-ticked, because this dialog *is* the human review the learned-recipe
  /// rule asks for: the values are on screen with their LLM badges, and the
  /// user is about to accept them. Unticking keeps the metadata and throws the
  /// recipe away.
  bool _saveRecipe = true;

  /// Stills are tracked by URL, not by index: a decision change can reorder or
  /// lengthen `extraFanartUrls` (merge puts the existing entries first), and an
  /// index captured before that would silently select a different picture.
  late Set<String> _stills = _defaultStills();

  /// url -> what the file becomes. Seeded from what the scrape already worked
  /// out; everything else keeps the server's name until the user says
  /// otherwise.
  late final Map<String, ImageRole> _roles = ImageNaming.defaultsFor(_merged);

  bool _saving = false;

  @override
  void dispose() {
    _targetDir.dispose();
    _nfoName.dispose();
    super.dispose();
  }

  late MediaMetadata _merged;

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

  /// How many rows will actually change the NFO — the footer button's count.
  int get _writeCount =>
      _plan.decisions.values.where((d) => d != MergeDecision.keep).length;

  void _setDecision(String field, MergeDecision decision) => setState(() {
    _plan = _plan.withDecision(field, decision);
    _activePreset = null;
  });

  void _applyPreset(MergePreset preset) => setState(() {
    _plan = _plan.withPreset(preset);
    _activePreset = preset;
  });

  Future<void> _edit(String field) async {
    final l10n = AppLocalizations.of(context)!;
    final label = metadataFieldLabel(l10n, field);
    final edited = await showGlassDialog<String>(
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
      _activePreset = null;
      // _merged is only refreshed at the top of build(), so it is one edit
      // stale here — recompute before deriving the default stills from it.
      _merged = NfoMerge.resolve(widget.result.existing, _scraped, _plan);
      _stills = _defaultStills();
    });
  }

  void _commit() {
    final merged = _merged;
    final urls = merged.extraFanartUrls;
    widget.onSubmit(
      ScrapeCommitDecision(
        metadata: merged,
        imageNames: _plannedNames(merged),
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
        kind: widget.kind,
        saveRecipe: widget.result.learnedRecipe != null && _saveRecipe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _merged = NfoMerge.resolve(widget.result.existing, _scraped, _plan);
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _header(l10n, scheme),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
        Expanded(child: _body(l10n, scheme)),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
        _footer(l10n, scheme),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(AppLocalizations l10n, ColorScheme scheme) {
    // Same de-duplication as `_artwork`'s tile list and the gallery's own
    // count: a page can list one image as both poster and backdrop, and a
    // raw sum of the three fields would then disagree with what the grid
    // actually shows.
    final imageCount = _imageOrder(_merged).length;
    final recipe = widget.result.recipe;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.tertiary, scheme.primary],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.travel_explore_outlined,
                  color: Colors.white,
                  size: 19,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          l10n.scrapePreviewSubtitle(_rows.length, imageCount),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        _dot(scheme),
                        Flexible(
                          child: Tooltip(
                            message: widget.result.pageUrl.toString(),
                            child: Text(
                              widget.result.pageUrl.toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (recipe != null) ...[
                          const SizedBox(width: 10),
                          _RecipeChip(
                            text: '${l10n.scrapeRecipeName} · ${recipe.domain}',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
          for (final note in widget.result.notes) ...[
            const SizedBox(height: 8),
            _NoteBanner(text: _noteText(l10n, note)),
          ],
        ],
      ),
    );
  }

  Widget _dot(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      '·',
      style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
    ),
  );

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

  // ── Body ──────────────────────────────────────────────────────────────────

  /// Fields on the left, artwork on the right.
  ///
  /// They are independent decisions — which synopsis to keep has nothing to do
  /// with which stills to save — and stacking them meant scrolling past a long
  /// field table to reach the pictures. Side by side, both are visible at once
  /// and each scrolls on its own.
  Widget _body(AppLocalizations l10n, ColorScheme scheme) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _fields(l10n, scheme)),
      VerticalDivider(
        width: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      SizedBox(
        width: 440,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: _artwork(l10n, scheme),
        ),
      ),
    ],
  );

  /// The one-click starting points, plus the count the footer button repeats.
  Widget _toolbar(AppLocalizations l10n, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: l10n.scrapePresetFillEmpty,
                selected: _activePreset == MergePreset.fillEmptyOnly,
                onTap: () => _applyPreset(MergePreset.fillEmptyOnly),
              ),
              _PresetChip(
                label: l10n.scrapePresetReplaceAll,
                selected: _activePreset == MergePreset.replaceAll,
                onTap: () => _applyPreset(MergePreset.replaceAll),
              ),
              _PresetChip(
                label: l10n.scrapePresetKeepAll,
                selected: _activePreset == MergePreset.keepAll,
                onTap: () => _applyPreset(MergePreset.keepAll),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          l10n.scrapeWillWrite(_writeCount),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );

  Widget _fields(AppLocalizations l10n, ColorScheme scheme) {
    final rows = _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolbar(l10n, scheme),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                    conflict: _plan.conflictFields.contains(field),
                    decision: _plan.decisionFor(field),
                    onDecision: (d) => _setDecision(field, d),
                    onEdit: isFieldEditable(field) ? () => _edit(field) : null,
                  ),
              ],
            ],
          ),
        ),
        if (rows.isNotEmpty) _legend(l10n, scheme),
      ],
    );
  }

  /// What the amber dot on a row means.
  Widget _legend(AppLocalizations l10n, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _conflictColor,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.scrapeConflictLegend,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );

  /// Every image the page offered, as a thumbnail.
  ///
  /// Selection is by URL rather than index throughout: a merge decision can
  /// reorder or lengthen `extraFanartUrls`, and an index captured before that
  /// would quietly select a different picture.
  Widget _artwork(AppLocalizations l10n, ColorScheme scheme) {
    final merged = _merged;
    final images = <GalleryImage>[
      if (merged.posterUrl != null)
        GalleryImage(url: merged.posterUrl!, label: l10n.scrapeImagePoster),
      if (merged.fanartUrl != null && merged.fanartUrl != merged.posterUrl)
        GalleryImage(url: merged.fanartUrl!, label: l10n.scrapeImageFanart),
      for (var i = 0; i < merged.extraFanartUrls.length; i++)
        if (merged.extraFanartUrls[i] != merged.posterUrl &&
            merged.extraFanartUrls[i] != merged.fanartUrl)
          GalleryImage(
            url: merged.extraFanartUrls[i],
            label: l10n.scrapeImageExtra(i + 1),
          ),
    ];

    return ImageGallery(
      images: images,
      cache: widget.cache,
      loadingRemaining: widget.loadingImages,
      selected: _selectedUrls(merged),
      roles: _roles,
      plannedNames: _plannedNames(merged),
      onSave: _saving ? null : _saveImages,
      onRole: _assignRole,
      onToggle: (url, on) => setState(() => _toggleImage(merged, url, on)),
      onSelectAll: () => setState(() {
        _poster = merged.posterUrl != null;
        _fanart = merged.fanartUrl != null;
        _stills = {...merged.extraFanartUrls};
      }),
      onSelectNone: () => setState(() {
        _poster = false;
        _fanart = false;
        _stills = {};
      }),
    );
  }

  /// The file each ticked image would be written to, recomputed on every
  /// build so a role change is visible on the tile immediately.
  Map<String, String> _plannedNames(MediaMetadata merged) => ImageNaming.plan(
    order: _imageOrder(merged),
    selected: _selectedUrls(merged),
    roles: _roles,
    // The real extension comes from the bytes; before they arrive the URL's
    // own suffix is the best guess, and the caption corrects itself on load.
    extensionOf: (url) {
      final bytes = widget.cache.peek(url);
      if (bytes != null) return ImageDownloader.extensionFor(bytes);
      final last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
      final dot = last.lastIndexOf('.');
      return dot > 0 ? last.substring(dot + 1).toLowerCase() : 'jpg';
    },
  );

  /// Poster, then backdrop, then stills — the order the grid shows and the
  /// order `extrafanart` numbering follows.
  List<String> _imageOrder(MediaMetadata merged) => [
    if (merged.posterUrl != null) merged.posterUrl!,
    if (merged.fanartUrl != null && merged.fanartUrl != merged.posterUrl)
      merged.fanartUrl!,
    for (final url in merged.extraFanartUrls)
      if (url != merged.posterUrl && url != merged.fanartUrl) url,
  ];

  /// A single-slot role can only belong to one image, so assigning it takes it
  /// away from whoever had it. Two files both called `poster.jpg` would mean
  /// one silently overwriting the other.
  void _assignRole(String url, ImageRole role) {
    setState(() {
      if (role.isSingleSlot) {
        _roles.removeWhere((_, existing) => existing == role);
      }
      if (role == ImageRole.original) {
        _roles.remove(url);
      } else {
        _roles[url] = role;
      }
      // Marking an image is a statement of intent about it; ticking it too is
      // what the user meant, and leaving it unticked would make the caption a
      // promise the Save button does not keep.
      if (role != ImageRole.original) _toggleImage(_merged, url, true);
    });
  }

  Future<void> _saveImages() async {
    final names = _plannedNames(_merged);
    if (names.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSaveImages(names);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<String> _selectedUrls(MediaMetadata merged) => {
    if (_poster && merged.posterUrl != null) merged.posterUrl!,
    if (_fanart && merged.fanartUrl != null) merged.fanartUrl!,
    ..._stills.where(merged.extraFanartUrls.contains),
  };

  void _toggleImage(MediaMetadata merged, String url, bool on) {
    // One URL can hold more than one job — a page with a single image lists it
    // as both poster and backdrop — so every slot it fills is toggled together
    // rather than leaving the tile half-selected and the checkbox lying.
    if (url == merged.posterUrl) _poster = on;
    if (url == merged.fanartUrl) _fanart = on;
    if (merged.extraFanartUrls.contains(url)) {
      if (on) {
        _stills.add(url);
      } else {
        _stills.remove(url);
      }
    }
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _footer(AppLocalizations l10n, ColorScheme scheme) {
    final imageCount = _selectedUrls(_merged).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _targetDir,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
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
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.scrapeNfoFileName,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                      fontSize: 12.5,
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
              // Expanded, not Flexible + Spacer — the same trailing-gap trap
              // the organize preview footer had; see its comment.
              Expanded(
                child: Text(
                  l10n.scrapeWriteBackup,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onBack,
                child: Text(l10n.scrapeBackToSetup),
              ),
              const SizedBox(width: 4),
              TextButton(onPressed: widget.onCancel, child: Text(l10n.cancel)),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _commit,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(l10n.scrapeWriteCounts(_writeCount, imageCount)),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.tertiary,
                  foregroundColor: scheme.onTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Field table ─────────────────────────────────────────────────────────────

const double _labelWidth = 104;

/// Wide enough for the three-segment picker (Keep · Replace · Merge) in both
/// locales. Fixed rather than intrinsic so every row's picker lines up.
const double _decisionWidth = 200;

/// Local value present and different from the scrape — the rows worth a real
/// look. Same amber as the LLM origin badge.
const Color _conflictColor = Color(0xFFE0B23C);

class _ColumnHeader extends StatelessWidget {
  final AppLocalizations l10n;
  const _ColumnHeader({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: scheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
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

  /// Both sides have a value and they differ — flagged with the amber dot the
  /// legend explains.
  final bool conflict;

  final MergeDecision decision;
  final ValueChanged<MergeDecision> onDecision;

  /// Null for fields the inline editor refuses (see `isFieldEditable`).
  final VoidCallback? onEdit;

  const _FieldRow({
    required this.field,
    required this.existing,
    required this.scraped,
    required this.conflict,
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

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (conflict) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _conflictColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      metadataFieldLabel(l10n, field),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
                  // Flexible because the label is a word ("Existing NFO") whose
                  // intrinsic width does not fit this column on every locale,
                  // and a badge is the first thing that should give way.
                  Flexible(child: _OriginBadge(origin: origin)),
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
          fontSize: 12,
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
        style: TextStyle(fontSize: 12, height: 1.4, color: color),
      ),
    );
  }
}

/// Where the scraped value came from, tinted per source: recipe purple,
/// derived teal, LLM amber — the amber ones are the values a human has to
/// actually look at.
class _OriginBadge extends StatelessWidget {
  final FieldOrigin origin;
  const _OriginBadge({required this.origin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (origin) {
      FieldOrigin.llm => const Color(0xFFE0852C),
      FieldOrigin.recipe => const Color(0xFF8E6FE8),
      FieldOrigin.derived => const Color(0xFF3AA885),
      FieldOrigin.manual => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        fieldOriginLabel(l10n, origin),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// One of the three merge starting points, styled as a pill that stays lit
/// until a per-row change makes the plan bespoke.
class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : glass.panelFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.4)
                  : glass.panelStroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keep / Replace, plus Merge on list fields. The chosen segment fills with
/// the primary color when it takes the scraped value, and stays neutral when
/// it keeps the disk's — so a glance down the column shows what will change.
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
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Row(
        children: [
          for (final (decision, label) in options)
            Expanded(
              child: Material(
                color: decision != value
                    ? Colors.transparent
                    : decision == MergeDecision.keep
                    ? scheme.surfaceContainerHighest
                    : scheme.primary,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onChanged(decision),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: decision == value
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: decision != value
                            ? scheme.onSurfaceVariant
                            : decision == MergeDecision.keep
                            ? scheme.onSurface
                            : scheme.onPrimary,
                      ),
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

// ── Notes ───────────────────────────────────────────────────────────────────

class _RecipeChip extends StatelessWidget {
  final String text;
  const _RecipeChip({required this.text});

  static const _purple = Color(0xFF8E6FE8);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: _purple.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: _purple.withValues(alpha: 0.3)),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _purple,
      ),
    ),
  );
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
