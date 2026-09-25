// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get manager => 'Manager';

  @override
  String get settings => 'Settings';

  @override
  String get parentFolder => 'Parent Folder';

  @override
  String get refresh => 'Refresh';

  @override
  String get descending => 'Descending';

  @override
  String get rename => 'Rename';

  @override
  String get newName => 'New Name';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get folderName => 'Folder Name';

  @override
  String get renameFile => 'Rename File';

  @override
  String get operations => 'Operations';

  @override
  String get matchFolderName => 'Match Folder Name';

  @override
  String get renameToFeaturette => 'Rename to Featurette';

  @override
  String get renameToInterview => 'Rename to Interview';

  @override
  String get renameToPart => 'Rename to Part...';

  @override
  String get renameToTVShow => 'Rename to TV Show...';

  @override
  String get jellyfinSubtitle => 'Jellyfin Subtitle...';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get system => 'System';

  @override
  String get language => 'Language';

  @override
  String get search => 'Search';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get openConfigFolder => 'Open Configuration Folder';

  @override
  String sizeLabel(Object size) {
    return 'Size: $size';
  }

  @override
  String get noPreviewAvailable => 'No preview available';

  @override
  String errorRenaming(Object error) {
    return 'Error renaming: $error';
  }

  @override
  String get season => 'Season';

  @override
  String get episode => 'Episode';

  @override
  String get selectPart => 'Select Part';

  @override
  String get customPart => 'Custom Part';

  @override
  String get customPartHint => 'e.g. 5';

  @override
  String partLabel(Object count) {
    return 'Part $count';
  }

  @override
  String get tvShowDialogTitle => 'TV show episode (SxxExx)';

  @override
  String get apply => 'Apply';

  @override
  String get isDefault => 'Default';

  @override
  String get languageLabel => 'Language';

  @override
  String get subtitleLangZhHans => 'Simplified Chinese';

  @override
  String get subtitleLangZhHant => 'Traditional Chinese';

  @override
  String get subtitleLangJa => 'Japanese';

  @override
  String get subtitleLangEn => 'English';

  @override
  String get video => 'Video';

  @override
  String get appBrand => 'Jellyfin Media Management Tool';

  @override
  String get tabFiles => 'Files';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabTasks => 'Tasks';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get searchHint => 'Search files, movies, shows...';

  @override
  String get favorites => 'Favorites';

  @override
  String get noFavorites => 'No favorites yet';

  @override
  String get recent => 'Recent';

  @override
  String get noRecent => 'Nothing recent';

  @override
  String get locations => 'Locations';

  @override
  String get aiConnected => 'AI service connected';

  @override
  String get aiConnectionError => 'AI connection error';

  @override
  String get aiTesting => 'Testing connection...';

  @override
  String get aiReady => 'AI ready';

  @override
  String get aiNotConfigured => 'AI not configured';

  @override
  String itemsProcessed(Object count) {
    return '$count items processed';
  }

  @override
  String get organizeWithAi => 'Organize all with AI';

  @override
  String organizeSelectedWithAi(Object count) {
    return 'Organize selected with AI ($count)';
  }

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get menuPreview => 'Preview';

  @override
  String get menuProperties => 'Properties';

  @override
  String get menuRevealInFileManager => 'Show in file manager';

  @override
  String get newNameLabel => 'New name';

  @override
  String deleteSelectedCount(Object count) {
    return 'Delete selected ($count)';
  }

  @override
  String deleteConfirmOne(Object name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String deleteConfirmMany(Object count) {
    return 'Delete $count selected items? This cannot be undone.';
  }

  @override
  String deletedCount(Object count) {
    return 'Deleted $count items';
  }

  @override
  String deleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get revealFailed => 'Could not open the system file manager';

  @override
  String get propModified => 'Modified';

  @override
  String get propPath => 'Path';

  @override
  String get fontSection => 'Font';

  @override
  String get fontSystem => 'System default';

  @override
  String get fontStatusDownloaded => 'Downloaded';

  @override
  String get fontStatusNotDownloaded => 'Needs download';

  @override
  String get fontDownloadTitle => 'Download font';

  @override
  String fontDownloadConfirm(Object name) {
    return 'First-time use of $name requires a one-time download of the official font package (saved to the app data folder). Continue?';
  }

  @override
  String fontDownloading(Object name) {
    return 'Downloading $name…';
  }

  @override
  String fontDownloadFailed(Object error) {
    return 'Font download failed: $error';
  }

  @override
  String get downloadAction => 'Download';

  @override
  String get openFolder => 'Open Folder';

  @override
  String get folderEmpty => 'This folder is empty';

  @override
  String get colName => 'Name';

  @override
  String get colType => 'Type';

  @override
  String get colSize => 'Size';

  @override
  String get colAiSuggestion => 'AI Suggestion';

  @override
  String get colConfidence => 'Confidence';

  @override
  String get typeFolder => 'Folder';

  @override
  String get typeVideo => 'Video';

  @override
  String get typeSubtitle => 'Subtitle';

  @override
  String get typeImage => 'Image';

  @override
  String get typeMetadata => 'Metadata';

  @override
  String get typeAudio => 'Audio';

  @override
  String get typeText => 'Text';

  @override
  String get typeOther => 'Other';

  @override
  String get needsReview => 'Needs review';

  @override
  String get analyzing => 'Analyzing...';

  @override
  String get analysisComplete => 'Analysis complete';

  @override
  String get notAnalyzed => 'Not analyzed';

  @override
  String selectedCount(Object count) {
    return '$count selected';
  }

  @override
  String itemsCount(Object count) {
    return '$count items';
  }

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get analyzingSelected => 'Analyzing selected files';

  @override
  String get aiPanelIdle => 'Configure AI, then organize a folder';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get targetStructure => 'Target Structure';

  @override
  String get previewOrganize => 'Preview';

  @override
  String get edit => 'Edit';

  @override
  String get usage => 'Usage';

  @override
  String tokensLabel(Object tokens) {
    return '$tokens tokens';
  }

  @override
  String applyDone(Object count) {
    return 'Organized $count files';
  }

  @override
  String applyPartial(Object failed, Object succeeded) {
    return 'Organized $succeeded, $failed failed';
  }

  @override
  String get provider => 'Provider';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get apiKey => 'API Key';

  @override
  String get model => 'Model';

  @override
  String get testConnection => 'Test Connection';

  @override
  String connectionFailed(Object error) {
    return 'Connection failed: $error';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get showKey => 'Show';

  @override
  String get hideKey => 'Hide';

  @override
  String get temperature => 'Temperature';

  @override
  String get apiKeyOptionalHint =>
      'Optional for local servers (LM Studio, Ollama…)';

  @override
  String get contextWindow => 'Context window (tokens)';

  @override
  String get contextWindowHint => 'Blank = send everything';

  @override
  String get maxOutputTokens => 'Max output tokens';

  @override
  String get maxOutputTokensHint => 'Blank = server default';

  @override
  String get contextWindowNote =>
      'The app cannot change a server\'s context size. Set it where the model is loaded (LM Studio, Ollama, llama.cpp) and enter the same number here: large folders are then organized in batches, and scraped pages are trimmed to fit.';

  @override
  String get connectionIncomplete =>
      'Fill in the base URL and model first (Google also needs an API key)';

  @override
  String connectionOkReply(Object ms, Object reply) {
    return 'Connected in $ms ms. The model replied: $reply';
  }

  @override
  String get connectionEmptyReply => '(empty reply)';

  @override
  String get connectionTruncated =>
      'The reply hit the output limit. Raise Max output tokens before organizing.';

  @override
  String detectedContextWindow(Object source, Object tokens) {
    return '$source reports a context window of $tokens tokens';
  }

  @override
  String detectedModelMaximum(Object source, Object tokens) {
    return '$source reports the model supports up to $tokens tokens; the loaded size may be smaller';
  }

  @override
  String detectedMaxOutput(Object tokens) {
    return 'max output $tokens';
  }

  @override
  String get limitsNotDetected =>
      'The server did not report a context size. Check it where the model is loaded.';

  @override
  String get useDetectedValue => 'Use';

  @override
  String get samplingTitle => 'Sampling';

  @override
  String samplingPresetMatched(Object name) {
    return 'Recommended values for $name';
  }

  @override
  String get samplingPresetSource => 'Source';

  @override
  String get samplingNoPreset =>
      'Unrecognized model family: the server\'s defaults apply';

  @override
  String get samplingReset => 'Reset to recommended';

  @override
  String get samplingDefault => 'Default';

  @override
  String get samplingTopP => 'Top P';

  @override
  String get samplingTopK => 'Top K';

  @override
  String get samplingMinP => 'Min P';

  @override
  String get samplingPresencePenalty => 'Presence penalty';

  @override
  String get samplingRepeatPenalty => 'Repeat penalty';

  @override
  String get samplingNote =>
      'Leave a field blank to use the recommended value.';

  @override
  String get thinkingMode => 'Thinking mode';

  @override
  String get thinkingModeHint =>
      'Off by default: reasoning makes small local models far slower and prone to going in circles.';

  @override
  String get thinkingAlwaysOn => 'This model can only run with reasoning on.';

  @override
  String get thinkingEffortOnly =>
      'This model\'s reasoning cannot be turned off; with thinking off it runs at low effort.';

  @override
  String get thinkingVerifiedOff => 'Last test: reasoning was off.';

  @override
  String get thinkingStillOn =>
      'Last test: the model still reasoned. Turn thinking off in the server\'s own model settings (in LM Studio: Enable Thinking).';

  @override
  String get presetNeedsSystemPrompt =>
      'This model\'s card requires its own system prompt; results may suffer without it.';

  @override
  String get ollamaIgnoresSampling =>
      'Ollama\'s OpenAI-compatible API ignores Top K, Min P and Repeat penalty; set them in the Modelfile instead.';

  @override
  String get tokensThisSession => 'Tokens this session';

  @override
  String get requests => 'Requests';

  @override
  String get avgLatency => 'Avg latency';

  @override
  String previewTitle(Object count) {
    return 'Organize $count items into Jellyfin structure';
  }

  @override
  String previewSubtitle(Object folders, Object pct, Object size) {
    return 'Move $folders folders, $size · avg AI confidence $pct%';
  }

  @override
  String get viewTree => 'Tree compare';

  @override
  String get viewList => 'View list';

  @override
  String get viewPoster => 'Poster view';

  @override
  String get showOnly => 'Show';

  @override
  String get filterChanges => 'Changes';

  @override
  String get filterAll => 'All';

  @override
  String filterConflicts(Object count) {
    return 'Conflicts ($count)';
  }

  @override
  String countMoves(Object count) {
    return '$count moved';
  }

  @override
  String countRenames(Object count) {
    return '$count renamed';
  }

  @override
  String countConflicts(Object count) {
    return '$count conflicts';
  }

  @override
  String get beforeLabel => 'Before';

  @override
  String get afterLabel => 'After';

  @override
  String get aiOrganizeVertical => 'AI · JELLYFIN';

  @override
  String get needsReviewSuffix => 'Needs review';

  @override
  String get recordUndoHistory => 'Record undo history (7 days)';

  @override
  String applyOrganizeCount(Object count) {
    return 'Apply ($count)';
  }

  @override
  String get editTargetTitle => 'Edit target path';

  @override
  String get targetPathLabel =>
      'Target path (relative to the organized folder)';

  @override
  String get targetPathInvalid =>
      'Invalid path — must stay inside the organized folder';

  @override
  String get namingRules => 'Apply a naming rule';

  @override
  String get editedBadge => 'Edited';

  @override
  String get markResolved => 'Accept this proposal';

  @override
  String organizing(Object count) {
    return 'Organizing · $count items';
  }

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusDone => 'Organization complete';

  @override
  String get statusStopped => 'Stopped';

  @override
  String etaRemaining(Object minutes, Object seconds) {
    return '${minutes}m ${seconds}s remaining';
  }

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get doneClose => 'Done';

  @override
  String get legendDone => 'Done';

  @override
  String get legendInProgress => 'In progress';

  @override
  String get legendQueued => 'Queued';

  @override
  String get legendSkipped => 'Skipped';

  @override
  String logStarted(Object count) {
    return 'Started · $count items';
  }

  @override
  String logMoved(Object dir, Object name) {
    return 'Moved $name → $dir/';
  }

  @override
  String logSkipped(Object name) {
    return '$name · needs review';
  }

  @override
  String logFailed(Object error, Object name) {
    return 'Failed $name · $error';
  }

  @override
  String logFinished(Object done, Object skipped) {
    return 'Done · $done organized, $skipped skipped';
  }

  @override
  String logStopped(Object done, Object skipped) {
    return 'Stopped · $done organized, $skipped skipped';
  }

  @override
  String logUndoLost(Object error) {
    return 'Undo unavailable · $error';
  }

  @override
  String get historyTitle => 'Operation history';

  @override
  String historyRetention(Object days) {
    return 'Kept $days days';
  }

  @override
  String get historyEmpty => 'No history yet';

  @override
  String get historyUndoFootnote =>
      'Undo reverts every file\'s location and name. Metadata caches are preserved.';

  @override
  String historyTitleAi(Object count) {
    return 'AI organize · $count items';
  }

  @override
  String historyTitleManual(Object count) {
    return 'Manual rename · $count items';
  }

  @override
  String get historyTitleMetadata => 'Metadata refresh';

  @override
  String historyTitleImport(Object count) {
    return 'Batch import · $count items';
  }

  @override
  String subMoves(Object count) {
    return '$count moved';
  }

  @override
  String subRenames(Object count) {
    return '$count renamed';
  }

  @override
  String subWritten(Object count) {
    return '$count written';
  }

  @override
  String subReplaced(Object count) {
    return '$count replaced';
  }

  @override
  String get historyRowWritten => 'written';

  @override
  String get historyRowReplaced => 'replaced';

  @override
  String get undoAction => 'Undo';

  @override
  String movesListTitle(Object count) {
    return 'Move list · $count';
  }

  @override
  String undoDone(Object count) {
    return 'Undone $count files';
  }

  @override
  String undoPartial(Object failed, Object succeeded) {
    return 'Undid $succeeded, $failed failed';
  }

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(Object count) {
    return '$count min ago';
  }

  @override
  String timeToday(Object time) {
    return 'Today $time';
  }

  @override
  String get timeYesterday => 'Yesterday';

  @override
  String timeDaysAgo(Object count) {
    return '${count}d ago';
  }

  @override
  String get secAppearance => 'Appearance';

  @override
  String get secLanguage => 'Language';

  @override
  String get secPaths => 'Paths';

  @override
  String get secAiServices => 'AI Services';

  @override
  String get secPrivacy => 'Privacy & Cache';

  @override
  String get secShortcuts => 'Shortcuts';

  @override
  String get secAbout => 'About';

  @override
  String get versionUpToDate => 'Up to date';

  @override
  String get theme => 'Theme';

  @override
  String get glassIntensity => 'Glass intensity';

  @override
  String get glassNone => 'Off';

  @override
  String get glassSoft => 'Soft';

  @override
  String get glassStrong => 'Strong';

  @override
  String get glassOffHint =>
      'Blur is off: panels use opaque fills. This is the cheapest the interface can draw.';

  @override
  String get glassOnHint =>
      'Drag to 0 to turn the blur off entirely. The strength itself costs almost nothing — how the blur is computed is the setting under Behavior.';

  @override
  String get accentColor => 'Accent color';

  @override
  String get behavior => 'Behavior';

  @override
  String get behaviorBakedGlass => 'Pre-render the glass blur';

  @override
  String get behaviorBakedGlassDesc =>
      'Blurs the window background once and reuses it instead of re-blurring every frame. Far cheaper on the GPU, and the panels look the same.';

  @override
  String get behaviorBakedGlassUnavailable =>
      'Nothing to pre-render while the blur is off.';

  @override
  String get behaviorVideoThumbnails =>
      'Show video thumbnails in the file list';

  @override
  String get shortcutGroupNavigation => 'Navigation';

  @override
  String get shortcutGroupSelection => 'Selection';

  @override
  String get shortcutGroupFiles => 'Files';

  @override
  String get shortcutGroupApp => 'Application';

  @override
  String get shortcutsHint =>
      'Shortcuts are inactive while you are typing in a text field, except for search.';

  @override
  String get shortcutSearch => 'Focus search';

  @override
  String get shortcutParentFolder => 'Go to parent folder';

  @override
  String get shortcutOpenFolder => 'Open a folder';

  @override
  String get shortcutRefresh => 'Refresh the file list';

  @override
  String get shortcutSectionFiles => 'Go to Files';

  @override
  String get shortcutSectionLibrary => 'Go to Library';

  @override
  String get shortcutSectionTasks => 'Go to Tasks';

  @override
  String get shortcutSelectAll => 'Select every visible file';

  @override
  String get shortcutEscape => 'Close dialog · clear search or selection';

  @override
  String get shortcutRename => 'Rename the focused file';

  @override
  String get shortcutDelete => 'Delete the selection';

  @override
  String get shortcutOrganize => 'Organize with AI';

  @override
  String get shortcutToggleFavorite => 'Pin or unpin the current folder';

  @override
  String get shortcutHistory => 'Operation history';

  @override
  String get shortcutSettings => 'Settings';

  @override
  String get aboutTagline => 'AI-driven media organizer for Jellyfin.';

  @override
  String get aboutJellyfinNaming => 'Jellyfin naming guide';

  @override
  String get aboutGpuHint =>
      'The GPU Windows hands this app. Change it under Settings → System → Display → Graphics, then restart the app.';

  @override
  String get langHeaderSubtitle =>
      'Switching also affects the AI\'s output language';

  @override
  String get langCurrent => 'Current';

  @override
  String get langImportArb => 'Import translation file (.arb)';

  @override
  String get langImportSoon => 'Custom translation import is coming soon.';

  @override
  String get langPreviewTitle => 'Live preview · main UI snippet';

  @override
  String get langPreviewHint =>
      'Switching the language also translates AI prompts; NFO metadata in organized results follows the same locale.';

  @override
  String get langLearnMore => 'Learn more';

  @override
  String get previewOrganizeSubtitle =>
      'Use AI to detect and move into Jellyfin structure';

  @override
  String get previewConfidenceLabel => 'Confidence';

  @override
  String get previewConfidenceHigh => 'high';

  @override
  String get previewTargetLabel => 'Target';

  @override
  String get previewTargetValue => 'Movies/Dune: Part Two (2024)/';

  @override
  String onboardingStepCounter(Object current, Object total) {
    return 'Step $current / $total';
  }

  @override
  String get onboardingWelcomeTitle =>
      'Welcome to Jellyfin Media Management Tool';

  @override
  String get onboardingWelcomeBody =>
      'Let AI sweep through messy download folders, rename and sort files, and produce a Jellyfin-conform library structure.';

  @override
  String get onboardingSkip => 'Skip tour';

  @override
  String get onboardingStart => 'Get started →';

  @override
  String get onboardingStep1Eyebrow => 'Step 1';

  @override
  String get onboardingStep2Eyebrow => 'Step 2';

  @override
  String get onboardingRootTitle => 'Choose your library root';

  @override
  String get onboardingRootBody =>
      'Point to the path Jellyfin already scans — organized files will land here.';

  @override
  String get onboardingDropFolder => 'Drop a folder here';

  @override
  String get onboardingOr => 'or';

  @override
  String get onboardingPickFolder => 'Pick a folder…';

  @override
  String get onboardingRootHint => 'Suggested: /Volumes/Media · ~/Movies';

  @override
  String get onboardingSkipForNow => 'Skip for now';

  @override
  String get onboardingAiTitle => 'Connect your AI service';

  @override
  String get onboardingAiBody =>
      'Both major protocols are supported. You can also add one later in Settings.';

  @override
  String get onboardingProviderOpenAi => 'OpenAI-compatible endpoint';

  @override
  String get onboardingConfigureLater => 'Configure later';

  @override
  String get onboardingEnterWorkspace => 'Enter workspace →';

  @override
  String get aiHintTitle => 'Add a title hint (optional)';

  @override
  String get aiHintSubtitle =>
      'Tell the AI which movie or series this is — useful when filenames are mangled. Leave blank to let the AI infer it.';

  @override
  String get aiHintLabel => 'Title';

  @override
  String aiHintPlaceholder(Object folder) {
    return 'e.g. Dune, Stranger Things (folder: $folder)';
  }

  @override
  String get aiHintAnalyze => 'Analyze';

  @override
  String get aiHintSkip => 'Skip';

  @override
  String get aiHintKindLabel => 'Media type';

  @override
  String get aiHintKindAuto => 'Auto-detect';

  @override
  String get aiHintKindMovie => 'Movie';

  @override
  String get aiHintKindSeries => 'Series';

  @override
  String get aiHintLabelMovie => 'Movie title';

  @override
  String get aiHintLabelSeries => 'Series title';

  @override
  String get tasksTitle => 'Tasks';

  @override
  String get tasksEmpty => 'No tasks yet';

  @override
  String get tasksEmptyHint =>
      'AI analyze and organize tasks will show up here';

  @override
  String get tasksClearFinished => 'Clear finished';

  @override
  String tasksAnalyzeLabel(Object folder) {
    return 'AI analyze · $folder';
  }

  @override
  String tasksApplyLabel(Object folder) {
    return 'Organize · $folder';
  }

  @override
  String get tasksAnalyzeRunning => 'AI is analyzing…';

  @override
  String get tasksAnalyzeDone => 'Analysis complete';

  @override
  String get tasksAnalyzeStarted =>
      'AI analysis started — see Tasks for progress';

  @override
  String get tasksApplyStarted =>
      'Organize task started — see Tasks for progress';

  @override
  String get tasksRunning => 'Running';

  @override
  String get tasksDone => 'Done';

  @override
  String get tasksFailed => 'Failed';

  @override
  String get tasksViewDetail => 'View details';

  @override
  String get tasksDismiss => 'Dismiss';

  @override
  String tasksScrapeLabel(Object target) {
    return 'Scrape · $target';
  }

  @override
  String tasksScrapeCommitLabel(Object target) {
    return 'Write metadata · $target';
  }

  @override
  String get menuScrapeMetadata => 'Scrape metadata';

  @override
  String get menuRescrapeFolder => 'Refresh metadata in folder';

  @override
  String get batchScrapeTitle => 'Refresh metadata';

  @override
  String batchScrapeFound(Object count) {
    return '$count titles record where they were scraped from.';
  }

  @override
  String get batchScrapeEmpty =>
      'Nothing to refresh here. Only NFOs this app wrote record their source page, so titles scraped elsewhere have no URL to go back to.';

  @override
  String get batchScrapePolicy =>
      'Each title is refreshed with the safe defaults: blanks are filled, existing values are kept, and lists are merged. There is no per-title review — use Scrape metadata on a single title for that.';

  @override
  String get batchScrapeArtwork => 'Re-download artwork too';

  @override
  String get batchScrapeArtworkHint =>
      'Off by default: the images were downloaded on the first scrape.';

  @override
  String batchScrapeStart(Object count) {
    return 'Refresh $count titles';
  }

  @override
  String get batchScrapeStarted =>
      'Refreshing metadata — see Tasks for progress';

  @override
  String batchScrapeDone(Object count) {
    return 'Refreshed $count titles';
  }

  @override
  String batchScrapePartial(Object count, Object failed) {
    return 'Refreshed $count titles · $failed failed';
  }

  @override
  String get shortcutScrape => 'Scrape metadata for the focused item';

  @override
  String get scrapeUrlInvalid =>
      'Enter a full URL, including http:// or https://';

  @override
  String scrapeDetectedCode(Object code) {
    return 'Detected code: $code';
  }

  @override
  String get scrapePasteHtml => 'Paste the page HTML instead';

  @override
  String get scrapePasteHtmlHint => 'Paste the page source here';

  @override
  String get scrapeNoFolder => 'Open a folder first';

  @override
  String get scrapeNoteSiteWideIgnored =>
      'This site serves the same OpenGraph block on every page, so it was ignored.';

  @override
  String get scrapeNoteNoRecipe =>
      'No recipe matched this site — only the page\'s own structured data was read.';

  @override
  String get scrapeNoteDegradedEncoding =>
      'The page\'s character encoding could not be determined; some text may be garbled.';

  @override
  String get scrapeNoteRecipeStale =>
      'The recipe matched but extracted nothing — the site has probably changed.';

  @override
  String get scrapeNoteRecipeLearned =>
      'No recipe existed for this site, so the AI wrote one. Check the highlighted values before saving it — a wrong selector can look perfectly healthy while quietly truncating text.';

  @override
  String get scrapeNoteRecipeLearningFailed =>
      'The AI could not work out how to read this page. Paste the page HTML to try again.';

  @override
  String get scrapeNoteRedirectedAway =>
      'The site redirected us away from that URL — you probably need to pass its age gate or sign in. What is shown below describes the page we landed on, not the title.';

  @override
  String scrapeSaveRecipe(Object domain) {
    return 'Remember this recipe for $domain';
  }

  @override
  String scrapeRecipeSaved(Object domain) {
    return 'Recipe saved for $domain';
  }

  @override
  String get scrapePreviewTitle => 'Review metadata';

  @override
  String scrapePreviewSubtitle(Object count, Object images) {
    return '$count fields · $images images';
  }

  @override
  String get scrapeSource => 'Source';

  @override
  String get scrapeRecipeName => 'Recipe';

  @override
  String get scrapeColumnField => 'Field';

  @override
  String get scrapeColumnExisting => 'Local NFO';

  @override
  String get scrapeColumnScraped => 'Scraped';

  @override
  String get scrapeColumnDecision => 'Action';

  @override
  String get scrapeDecisionKeep => 'Keep';

  @override
  String get scrapeDecisionReplace => 'Replace';

  @override
  String get scrapeDecisionMerge => 'Merge';

  @override
  String get scrapePresetFillEmpty => 'Fill blanks only';

  @override
  String get scrapePresetReplaceAll => 'Replace all';

  @override
  String get scrapePresetKeepAll => 'Keep all';

  @override
  String get scrapeOriginStructured => 'Page data';

  @override
  String get scrapeOriginRecipe => 'Recipe';

  @override
  String get scrapeOriginLlm => 'AI guess';

  @override
  String get scrapeOriginExisting => 'Existing NFO';

  @override
  String get scrapeOriginManual => 'Edited';

  @override
  String get scrapeOriginDerived => 'Derived';

  @override
  String get scrapeOriginMerged => 'Merged';

  @override
  String get scrapeNoChanges =>
      'Nothing to change — the NFO on disk already says all of this.';

  @override
  String get scrapeWriteBackup =>
      'Record undo information (backs up any NFO this replaces)';

  @override
  String get scrapeTargetFolder => 'Target folder';

  @override
  String get scrapeNfoFileName => 'NFO file name';

  @override
  String scrapeEditValue(Object field) {
    return 'Edit $field';
  }

  @override
  String get scrapeImages => 'Artwork';

  @override
  String get scrapeImagePoster => 'Poster';

  @override
  String get scrapeImageFanart => 'Backdrop';

  @override
  String scrapeImageExtra(Object index) {
    return 'Still $index';
  }

  @override
  String scrapeImageCount(Object count, Object total) {
    return '$count of $total selected';
  }

  @override
  String get scrapeImageNone => 'This page offered no artwork.';

  @override
  String get scrapeCommitStarted => 'Writing metadata — see Tasks for progress';

  @override
  String scrapeWriteSucceeded(Object count) {
    return 'Wrote $count files';
  }

  @override
  String scrapeWritePartial(Object count, Object failed) {
    return 'Wrote $count files · $failed failed';
  }

  @override
  String scrapeWriteFailed(Object error) {
    return 'Nothing was written: $error';
  }

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldOriginalTitle => 'Original title';

  @override
  String get fieldSortTitle => 'Sort title';

  @override
  String get fieldCode => 'Code';

  @override
  String get fieldPlot => 'Synopsis';

  @override
  String get fieldOutline => 'Blurb';

  @override
  String get fieldTagline => 'Tagline';

  @override
  String get fieldPremiered => 'Release date';

  @override
  String get fieldRuntime => 'Runtime';

  @override
  String get fieldStudio => 'Studio';

  @override
  String get fieldSeries => 'Series';

  @override
  String get fieldDirector => 'Director';

  @override
  String get fieldRating => 'Rating';

  @override
  String get fieldGenres => 'Genres';

  @override
  String get fieldTags => 'Tags';

  @override
  String get fieldActors => 'Cast';

  @override
  String get fieldPoster => 'Poster';

  @override
  String get fieldFanart => 'Backdrop';

  @override
  String get fieldExtraFanart => 'Stills';

  @override
  String get secScraping => 'Scraping';

  @override
  String get settingsScrapeCookies => 'Cookies';

  @override
  String get settingsScrapeCookieWarning =>
      'A cookies.txt exported from your browser can contain a session identifier equivalent to being signed in. Cookies are held in memory only and are gone when the app closes; they also stop working once you sign out in that browser.';

  @override
  String get settingsScrapeImportCookies => 'Import cookies.txt';

  @override
  String get settingsScrapeClearCookies => 'Clear all';

  @override
  String get settingsScrapeClearDomain => 'Clear';

  @override
  String get settingsScrapeCookieEmpty => 'No cookies imported.';

  @override
  String settingsScrapeCookieCount(Object count) {
    return '$count cookies';
  }

  @override
  String settingsScrapeCookieImported(Object count) {
    return 'Imported $count cookies';
  }

  @override
  String get settingsScrapeCookieImportFailed =>
      'That file contained no usable cookies';

  @override
  String get settingsScrapeRecipes => 'Site recipes';

  @override
  String get settingsScrapeRecipeBuiltin => 'Built in';

  @override
  String get settingsScrapeRecipeLearned => 'Learned';

  @override
  String get settingsScrapeRecipeUser => 'Edited';

  @override
  String get settingsScrapeRecipeRetired => 'Retired';

  @override
  String get settingsScrapeRecipeDelete => 'Delete recipe';

  @override
  String settingsScrapeRecipeHealth(Object count, Object failed) {
    return '$count ok · $failed failed';
  }

  @override
  String get settingsScrapeRecipeAnyPath => 'any page';

  @override
  String get scrapeNoteLlmExtracted =>
      'These values were read off the page by the model, not matched by a selector — nothing verified them against the document. Check anything that matters before writing.';

  @override
  String get scrapeNoteLlmExtractionFailed =>
      'The model could not read usable metadata off this page.';

  @override
  String get scrapeNoteLlmExtractionTruncated =>
      'The model hit its output limit before it finished, so some fields may be missing. Raise the maximum output in the AI service settings.';

  @override
  String get scrapeAskLlm => 'Ask the LLM directly';

  @override
  String get scrapeAskLlmHint =>
      'Reads the page you already fetched and reports the fields itself. Costs a request, and the values are the model’s rather than the page’s.';

  @override
  String get scrapeCustomPrompt =>
      'Extra instructions for the model (optional)';

  @override
  String get scrapeCustomPromptHint => 'e.g. “use the sidebar credits as tags”';

  @override
  String get scrapeBackend => 'AI backend';

  @override
  String get scrapeBackendNone => 'No AI profile configured';

  @override
  String get scrapeCookiesLabel => 'Cookies for this site (optional)';

  @override
  String get scrapeCookiesHint =>
      'name=value; name2=value2 — held in memory for this run only';

  @override
  String get scrapeNfoTarget => 'Compare against';

  @override
  String get scrapeNfoBrowse => 'Browse…';

  @override
  String get scrapeKindMovie => 'Movie';

  @override
  String get scrapeKindTvShow => 'TV show';

  @override
  String get scrapePanelTitle => 'Scrape metadata';

  @override
  String get scrapeProcess => 'Process';

  @override
  String get scrapeWorking => 'Working…';

  @override
  String get scrapeBackToSetup => 'Back';

  @override
  String get scrapeAdvanced => 'Advanced';

  @override
  String scrapeImageLoading(Object count) {
    return 'loading $count…';
  }

  @override
  String get scrapeImageSelectAll => 'Select all';

  @override
  String get scrapeImageSelectNone => 'None';

  @override
  String scrapeSaveImages(Object count) {
    return 'Save $count images';
  }

  @override
  String get scrapeSaveImagesHint =>
      'Writes the ticked images into the media folder now. Does not touch the NFO.';

  @override
  String scrapeSaveImagesDone(Object count, Object folder) {
    return 'Saved $count images to $folder';
  }

  @override
  String scrapeSaveImagesPartial(Object count, Object failed) {
    return 'Saved $count images · $failed failed';
  }

  @override
  String get scrapeImageRole => 'Mark as Jellyfin artwork';

  @override
  String get scrapeRoleOriginal => 'Keep original name';

  @override
  String get scrapeRolePoster => 'Poster (folder)';

  @override
  String get scrapeRoleFanart => 'Backdrop';

  @override
  String get scrapeRoleExtraFanart => 'Extra backdrop';

  @override
  String get scrapeRoleThumb => 'Thumb (landscape)';

  @override
  String get scrapeRoleMenu => 'Menu';

  @override
  String get scrapeRoleBanner => 'Banner';

  @override
  String get scrapeRoleLogo => 'Logo';

  @override
  String get scrapeRoleClearArt => 'Clear art';

  @override
  String get scrapeRoleDisc => 'Disc';

  @override
  String get colResetWidths => 'Drag to resize · double-click to reset';

  @override
  String get scrapeSourceUrl => 'Product page URL';

  @override
  String get scrapeSourceSearch => 'Search sites by filename';

  @override
  String get scrapeSearchKeyword => 'Search keyword';

  @override
  String get scrapeSearchNoSites =>
      'No search sites configured — add some in Settings.';

  @override
  String scrapeNfoAutoMatched(Object name) {
    return 'Auto-matched $name in the same folder';
  }

  @override
  String get scrapeStepFetch => 'Fetch page';

  @override
  String get scrapeStepExtract => 'Extract fields';

  @override
  String get scrapeStepCompare => 'Build field comparison';

  @override
  String scrapeElapsed(Object time) {
    return 'Elapsed $time';
  }

  @override
  String scrapeWillWrite(Object count) {
    return '$count will be written';
  }

  @override
  String get scrapeConflictLegend =>
      'Local value exists and differs from the scrape';

  @override
  String get scrapeImageRoleHint =>
      'Right-click to mark as Jellyfin artwork · others keep their original file name';

  @override
  String get scrapeImageUnmarked => 'Unmarked';

  @override
  String get scrapeImageDeselect => 'Deselect';

  @override
  String scrapeWriteCounts(Object fields, Object images) {
    return 'Write $fields fields + $images images';
  }

  @override
  String get previewDryRun => 'Preview · no files are moved yet';

  @override
  String get previewFilterEmpty => 'Nothing matches this filter';

  @override
  String get previewAdjustRules => 'Adjust rules';

  @override
  String get ruleEditorTitle => 'Naming rule · Movies';

  @override
  String get ruleEditorRecommended => 'Jellyfin preset';

  @override
  String get ruleEditorFolderTemplate => 'Folder path template';

  @override
  String get ruleEditorFileTemplate => 'File name template';

  @override
  String get ruleEditorVariables => 'Available variables';

  @override
  String get ruleEditorPreview => 'Live preview';

  @override
  String get ruleEditorInput => 'Input';

  @override
  String get ruleEditorOutput => 'Output';

  @override
  String get ruleEditorOutputAi => 'Output · AI inferred';

  @override
  String get ruleEditorReset => 'Reset';

  @override
  String get ruleEditorComingSoon =>
      'Editing rules is not wired up yet — this preview shows the built-in Jellyfin convention.';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get togglePanel => 'Show or hide the side panel';

  @override
  String get searchHintShort => 'Search…';

  @override
  String statusTotalSize(String size) {
    return '$size total';
  }

  @override
  String get planReady => 'Plan ready';

  @override
  String get dropFoldersTitle => 'Drop folders here to start';

  @override
  String get dropFoldersHint =>
      'Drag one or more folders into the window · video, subtitles, posters and metadata are scanned together';

  @override
  String get orSeparator => 'or';

  @override
  String get connectNas => 'Connect NAS';

  @override
  String get historyAllRecords => 'All records';

  @override
  String get historyIrreversible => 'Cannot be undone';

  @override
  String get historyToday => 'Today';

  @override
  String get back => 'Back';

  @override
  String get pathsLibraryRoots => 'Library roots';

  @override
  String get pathsRootMovies => 'Movies';

  @override
  String get pathsRootShows => 'Shows';

  @override
  String get pathsRootExample => '/Volumes/Media/Movies';

  @override
  String get pathsMounted => 'Connected';

  @override
  String get pathsUnmounted => 'Not mounted';

  @override
  String get pathsChange => 'Change';

  @override
  String get pathsAddRoot => 'Add root';

  @override
  String get pathsRescan => 'Rescan';

  @override
  String get pathsRootsPlaceholder =>
      'This app organizes one folder at a time. Multiple roots, mount state and rescanning are not implemented yet.';

  @override
  String get pathsDefaults => 'Default locations';

  @override
  String get pathsOrganizeOutput => 'Organize output';

  @override
  String get pathsOrganizeOutputValue => 'Follows the source folder';

  @override
  String get pathsChoose => 'Choose…';

  @override
  String get pathsTempDir => 'Temporary & downloads';

  @override
  String get pathsTempDirValue => 'System temporary folder';

  @override
  String get pathsNfoOutput => 'NFO & image output';

  @override
  String get pathsNfoOutputValue => 'Beside the media file';

  @override
  String get pathsDefaultsPlaceholder =>
      'Organized files always land beside their source; a separate output or temporary folder is not implemented yet.';

  @override
  String get pathsFavorites => 'Favorite paths';

  @override
  String get pathsFavoritesHint =>
      'Reordering by drag is not implemented yet. This list is the sidebar\'s Favorites group.';

  @override
  String get pathsRecent => 'Recent';

  @override
  String get pathsClearRecent => 'Clear';

  @override
  String pathsRecentHint(Object count) {
    return 'The last $count folders you opened. The star at the end of a row adds one to Favorites.';
  }

  @override
  String get pathsAddFavorite => 'Add to favorites';

  @override
  String get privacyLocations => 'Config & data';

  @override
  String get privacyConfigFolder => 'Config folder';

  @override
  String get privacyBrowse => 'Browse';

  @override
  String get privacyCopyPath => 'Copy';

  @override
  String get privacyCopied => 'Path copied';

  @override
  String get privacyDataFiles => 'Data files';

  @override
  String get privacyDataFilesValue =>
      'config.json · ai_profiles.json · ai_learned.json · sites.json · scrapers.json';

  @override
  String get privacyPrefsBackup => 'Preferences backup';

  @override
  String get privacyPrefsBackupHint =>
      'Export or restore config.json and the AI profiles';

  @override
  String get privacyImport => 'Import';

  @override
  String get privacyExport => 'Export';

  @override
  String get privacyCaches => 'Caches';

  @override
  String get privacyClear => 'Clear';

  @override
  String get privacyClearAll => 'Clear all';

  @override
  String get privacyTotal => 'Total';

  @override
  String get privacyCacheThumbnails => 'Thumbnail cache';

  @override
  String get privacyCacheThumbnailsHint =>
      'Poster frames rendered for the file table';

  @override
  String get privacyCacheUndo => 'Undo backups';

  @override
  String privacyCacheUndoHint(Object count, Object days) {
    return 'Real copies of overwritten files, kept $days days · $count operations';
  }

  @override
  String get privacyCacheAgent => 'Organize memory';

  @override
  String get privacyCacheAgentHint =>
      'Decided groups and corrections you applied';

  @override
  String get privacyCacheNote =>
      'Clearing removes local caches only. NFOs and images already written to the library are untouched, and the next run regenerates what it needs. Undo backups have no Clear: deleting them would turn undo records that have not expired into empty promises.';

  @override
  String get privacySection => 'Privacy';

  @override
  String get privacyTelemetry => 'Send anonymous usage statistics';

  @override
  String get privacyTelemetryHint => 'No file names or paths';

  @override
  String get privacyCrashReports => 'Crash reports';

  @override
  String get privacyCrashReportsHint => 'Stack traces and device model only';

  @override
  String get privacyLogAiBodies => 'Log AI request and reply bodies';

  @override
  String privacyLogAiBodiesHint(int days) {
    return 'Every request actually sent goes to the logs folder, one file per day, kept $days days. Keys are never written; images and long text are logged by length only.';
  }

  @override
  String get privacyClearTempOnExit => 'Empty the temporary folder on exit';

  @override
  String get privacyNoTelemetry =>
      'This app collects no telemetry of any kind. The AI request log stays on this computer; the other switches have nothing to turn off yet.';

  @override
  String get privacyCacheApiLog => 'AI request log';

  @override
  String get privacyCacheApiLogHint =>
      'Written while “Log AI request and reply bodies” is on';

  @override
  String get privacyDanger => 'Danger zone';

  @override
  String get privacyReset => 'Reset all data';

  @override
  String get privacyResetBody =>
      'Clears AI services, recipes, history and every cache, returning the app to its first-launch state. Media files on disk are not deleted, and NFOs and images already written are kept.';

  @override
  String get privacyResetAction => 'Reset…';

  @override
  String get privacyResetPlaceholder =>
      'Not implemented yet. Until it is, delete the config folder by hand — an irreversible reset should not ship half-built.';

  @override
  String get shortcutsSearchHint => 'Search a command or a key…';

  @override
  String get shortcutsRestoreDefaults => 'Restore defaults';

  @override
  String get shortcutsRebindHint =>
      'Rebinding is not implemented yet — what is listed here is what is actually bound.';

  @override
  String get shortcutsNoMatch => 'No command matches';

  @override
  String get shortcutsPlatformNote =>
      'On Windows and Linux ⌘ is Ctrl, ⌥ is Alt and ⌫ is Delete.';

  @override
  String get aboutChangelog => 'Changelog';

  @override
  String get aboutCheckUpdates => 'Check for updates';

  @override
  String get aboutBuildInfo => 'Build info';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutBuildNumber => 'Build';

  @override
  String get aboutCommit => 'Commit';

  @override
  String get aboutCommitTime => 'Commit time';

  @override
  String get aboutBranch => 'Branch';

  @override
  String get aboutRuntime => 'Runtime';

  @override
  String get aboutBuildInfoPlaceholder =>
      'Commit and branch are stamped in at package time, which this build does not do yet.';

  @override
  String get aboutSystem => 'System';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutRepository => 'Repository';

  @override
  String get aboutIssues => 'Report an issue';

  @override
  String get aboutCopyright => 'Copyright';

  @override
  String get aboutCopyrightValue => '© 2026 contributors';

  @override
  String get aboutThirdParty => 'Third-party licenses';

  @override
  String get aboutGraphics => 'Graphics adapter';

  @override
  String get aboutGpuRunning => 'In use';

  @override
  String get aboutGpuShared => 'Shared memory';

  @override
  String aboutGpuCount(Object count) {
    return '$count GPUs detected';
  }

  @override
  String get aboutGpuInfoOnly => 'Information only';

  @override
  String get aboutGpuIdle => 'Idle';

  @override
  String get accentPickerTitle => 'Accent color';

  @override
  String get accentRestoreDefault => 'Restore the default blue';

  @override
  String get accentRecents => 'Recently used';

  @override
  String get accentRecentsEmpty => 'Nothing yet';

  @override
  String get accentEyedropper => 'Pick a color from the screen';

  @override
  String accentContrastOk(Object dark, Object light) {
    return 'Contrast against the dark and light window bases: $dark:1 · $light:1';
  }

  @override
  String accentContrastWeak(Object dark, Object light) {
    return 'Contrast $dark:1 · $light:1 — below 3:1, so use it as a fill only';
  }

  @override
  String get contextWindowScaleHint => 'tokens · 8k – 1M · step 1k';

  @override
  String get contextWindowFootnote =>
      'The ticks are evenly spaced segments and each segment is continuous, so the handle can stop on any 1k. Slider and field follow each other; blank means no limit.';

  @override
  String contextWindowOverDetected(Object limit) {
    return 'Above the $limit the server reported. Still saved.';
  }

  @override
  String get maxOutputStep => 'step 256';

  @override
  String get maxOutputFootnote =>
      'Capped at half the context window; anything larger is clamped.';

  @override
  String get pathsRootExampleShows => '/Volumes/Media/Shows';

  @override
  String historyTitleTransfer(Object count) {
    return 'Copy / move · $count items';
  }

  @override
  String tasksCopyLabel(Object target) {
    return 'Copy · $target';
  }

  @override
  String tasksMoveLabel(Object target) {
    return 'Move · $target';
  }

  @override
  String get shortcutCopy => 'Copy the selection';

  @override
  String get shortcutCut => 'Cut the selection';

  @override
  String get shortcutPaste => 'Paste into the current folder';

  @override
  String get menuCopy => 'Copy';

  @override
  String get menuCut => 'Cut';

  @override
  String get menuPaste => 'Paste';

  @override
  String get menuPasteIntoFolder => 'Paste into this folder';

  @override
  String get menuMoveTo => 'Move to…';

  @override
  String clipboardCopiedCount(Object count) {
    return '$count items copied';
  }

  @override
  String clipboardCutCount(Object count) {
    return '$count items cut';
  }

  @override
  String get clipboardPasteHere => 'Paste here';

  @override
  String get clipboardClear => 'Clear';

  @override
  String transferConflictTitle(Object count, Object folder) {
    return '$count items already exist in $folder';
  }

  @override
  String get transferConflictBody =>
      'Nothing is overwritten. Skip the ones that exist, or keep both and the new copies get a numbered name.';

  @override
  String get transferSkipExisting => 'Skip existing';

  @override
  String get transferKeepBoth => 'Keep both';

  @override
  String get transferNothingToDo => 'Nothing to paste here';

  @override
  String transferRefusedMissing(Object count) {
    return '$count items no longer exist';
  }

  @override
  String get transferRefusedIntoItself =>
      'A folder cannot be pasted into itself';

  @override
  String transferRefusedSameFolder(Object count) {
    return '$count items are already in this folder';
  }

  @override
  String transferCopiedCount(Object count) {
    return 'Copied $count items';
  }

  @override
  String transferMovedCount(Object count) {
    return 'Moved $count items';
  }

  @override
  String transferFailedCount(Object count) {
    return '$count failed';
  }

  @override
  String transferStopped(Object count) {
    return 'Stopped after $count items';
  }

  @override
  String get transferNoUndo => 'no undo';

  @override
  String get transferDestinationMissing =>
      'The destination folder is not available';

  @override
  String get moveToTitle => 'Move to folder';

  @override
  String transferRefusedLink(Object count) {
    return '$count items are symbolic links or contain them';
  }

  @override
  String transferRefusedUnreadable(Object count) {
    return '$count items could not be read';
  }

  @override
  String get aiAccessTitle => 'AI access';

  @override
  String get aiAccessSubtitle =>
      'A channel is one key. A route is a protocol that key can speak. Each model hangs off a channel and picks one route.';

  @override
  String get aiDiagnostics => 'Diagnostics';

  @override
  String get aiAddChannel => 'Add channel';

  @override
  String aiMergeHint(String names, int routes, int models) {
    String _temp0 = intl.Intl.pluralLogic(
      routes,
      locale: localeName,
      other: '$routes routes',
      one: '1 route',
    );
    String _temp1 = intl.Intl.pluralLogic(
      models,
      locale: localeName,
      other: '$models models',
      one: '1 model',
    );
    return '$names share one key and host and can become one channel ($_temp0, $_temp1).';
  }

  @override
  String get aiMergeAction => 'Merge';

  @override
  String aiChannelHostLine(String host, String platform) {
    return '$host · platform: $platform';
  }

  @override
  String get aiNoKeyNeeded => 'no key needed';

  @override
  String get aiNoModels => 'No models yet — open the channel to add one.';

  @override
  String get aiToolsUnprobed => 'Tools: not checked';

  @override
  String get aiToolsYes => 'Tools';

  @override
  String get aiToolsNo => 'No tools';

  @override
  String get aiImage => 'Image';

  @override
  String get aiVideo => 'Video';

  @override
  String get aiEmptyTitle => 'No channels yet';

  @override
  String get aiEmptyBody =>
      'Pick a platform, paste one key, then add the models you want to use.';

  @override
  String get aiTasksTitle => 'Task assignment';

  @override
  String get aiTasksHint =>
      'Pick a model for each task. Tasks that need tool calling leave out models known not to call tools.';

  @override
  String get aiTaskOrganize => 'Organize (tool calling)';

  @override
  String get aiTaskScrapeLearn => 'Scrape · learn a recipe (tool calling)';

  @override
  String get aiTaskScrapeDirect => 'Scrape · read the page (tool calling)';

  @override
  String get aiTaskVision => 'Frame recognition (image input)';

  @override
  String get aiFollowOrganize => 'Follow “Organize”';

  @override
  String get aiTaskNoModel => 'No suitable model';

  @override
  String get aiVisionNeedsImage =>
      'Only models allowed image input are listed.';

  @override
  String get aiSessionUsage => 'Since this launch';

  @override
  String get aiPlatformRelay => 'Relay (New API style)';

  @override
  String get aiPlatformCustom => 'Custom';

  @override
  String get aiPlatformDashScope => 'Alibaba Cloud Model Studio';

  @override
  String get aiPlatformZhipu => 'Zhipu BigModel';

  @override
  String get aiPlatformVolcengine => 'Volcengine Ark';

  @override
  String get aiAddChannelHint =>
      'Pick the platform first. Protocols, address and auth come from its profile; you only paste one key.';

  @override
  String get aiPlatformGroupVendor => 'Vendors';

  @override
  String get aiPlatformGroupRelay => 'Aggregators and relays';

  @override
  String get aiPlatformGroupLocal => 'Local servers';

  @override
  String get aiPlatformCustomHint =>
      'Custom — protocol-standard fields only, no vendor extensions';

  @override
  String aiWillCreate(String platform) {
    return '$platform · will create';
  }

  @override
  String get aiPrimaryRoute => 'Primary';

  @override
  String aiRouteDialect(String field) {
    return 'Reasoning switch: $field';
  }

  @override
  String get aiRouteLadder =>
      'No platform switch — the local-server ladder, judged by the reply';

  @override
  String get aiRouteNotInBuild => 'Arrives in a later update';

  @override
  String get aiChannelKey => 'API key (shared by the whole channel)';

  @override
  String get aiChannelHost => 'Host';

  @override
  String get aiChannelHostHint => 'Entered once; every route builds on it';

  @override
  String get aiChannelName => 'Display name';

  @override
  String get aiDeleteChannel => 'Delete channel';

  @override
  String aiDeleteChannelConfirm(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'its $count models',
      one: 'its model',
      zero: 'its settings',
    );
    return 'Delete “$name” and $_temp0? This cannot be undone.';
  }

  @override
  String aiPlatformInferred(String platform) {
    return 'Platform: $platform · inferred from the host';
  }

  @override
  String aiPlatformChosen(String platform) {
    return 'Platform: $platform';
  }

  @override
  String get aiRoutesTitle => 'Routes';

  @override
  String get aiRoutesHint =>
      'At most one per protocol. Only the protocols this platform offers are listed.';

  @override
  String aiRoutePathDefault(String path) {
    return 'Default: $path';
  }

  @override
  String get aiRouteHostItself => 'the host itself';

  @override
  String get aiRouteEnable => 'Enable';

  @override
  String get aiRouteDisable => 'Turn off';

  @override
  String get aiRouteMakePrimary => 'Make primary';

  @override
  String aiRouteInUse(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models use',
      one: '1 model uses',
    );
    return '$_temp0 this route — it cannot be turned off.';
  }

  @override
  String get aiRouteNotEnabled =>
      'Offered by the platform, not enabled. Models can switch to it once it is; their parameters start blank.';

  @override
  String get aiRoutePathNote =>
      'Blank = the platform’s own path. A relative path is added to the host; a full URL replaces the host too (shown as “own host”).';

  @override
  String get aiRouteOwnHost => 'own host';

  @override
  String get aiModelsTitle => 'Models';

  @override
  String get aiAddModel => 'Add model';

  @override
  String get aiModelNameHint => 'Model name as the server knows it';

  @override
  String get aiRouteBar => 'Route';

  @override
  String get aiRouteBarHint =>
      'Switching route keeps the model id. A route never configured starts blank.';

  @override
  String get aiCapabilityMatrix => 'Capability matrix';

  @override
  String get aiScopeModel => 'Model';

  @override
  String get aiScopeModelHint => 'Same on every route';

  @override
  String get aiUpstreamModel => 'Upstream model name';

  @override
  String get aiAllowImage => 'Allow image input';

  @override
  String get aiAllowVideo => 'Allow video frames';

  @override
  String get aiAllowHint =>
      'An authorization. Whether it can be sent depends on the route.';

  @override
  String aiScopeRoute(String protocol) {
    return 'This route · $protocol';
  }

  @override
  String get aiScopeRouteHint =>
      'Changes with the protocol; parked here when you switch routes';

  @override
  String get aiThinkingDialect => 'Reasoning switch';

  @override
  String aiDialectField(String field) {
    return '$field · from the platform profile';
  }

  @override
  String aiSendsAs(String field) {
    return 'Sent as $field';
  }

  @override
  String get aiLearnedTag => 'learned';

  @override
  String aiRefusedFields(String fields) {
    return 'Refused on this route and no longer sent: $fields';
  }

  @override
  String get aiStructuredOutput => 'Structured output';

  @override
  String aiStructuredLearned(String mode) {
    return '$mode · learned';
  }

  @override
  String get aiStructuredUnknown =>
      'Not needed by any task; the test learns it only as a fallback';

  @override
  String get aiPreviewTitle => 'What will be sent';

  @override
  String get aiPreviewHint =>
      'Built by the same code as the real request, for an organize turn.';

  @override
  String get aiPreviewUnavailable =>
      'This build has no adapter for this protocol yet.';

  @override
  String get aiTestRoute => 'Test this route';

  @override
  String get aiDeleteModel => 'Delete model';

  @override
  String aiDeleteModelConfirm(String name) {
    return 'Delete “$name”? Tasks assigned to it go back to following organize.';
  }

  @override
  String get aiToolsMeasured => 'Supported · measured on this route';

  @override
  String get aiToolsMeasuredNo => 'Not supported · measured on this route';

  @override
  String get aiToolsNotMeasured => 'Not checked on this route yet';

  @override
  String aiSwitchTitle(String model, String from, String to) {
    return 'Switch $model from $from to $to';
  }

  @override
  String get aiSwitchBody =>
      'The current route’s parameters stay parked under it and come back unchanged if you switch back. Values the new route had before are loaded; anything never set there is “not set · not sent” — never copied.';

  @override
  String get aiSwitchParam => 'Parameter';

  @override
  String aiSwitchNow(String protocol) {
    return 'Now · $protocol';
  }

  @override
  String aiSwitchAfter(String protocol) {
    return 'After · $protocol';
  }

  @override
  String get aiParamThinking => 'Reasoning';

  @override
  String get aiParamMaxOutput => 'Max output';

  @override
  String get aiParamSampling => 'Sampling';

  @override
  String get aiParamTools => 'Tool calling';

  @override
  String get aiParamImage => 'Image input';

  @override
  String get aiNotSetNotSent => 'not set · not sent';

  @override
  String get aiOn => 'on';

  @override
  String get aiOff => 'off';

  @override
  String get aiToolsProbeAfter =>
      'Not checked — test the route after switching';

  @override
  String get aiSwitchFooter =>
      'The model id is unchanged; task assignments are unaffected.';

  @override
  String get aiSwitchConfirm => 'Switch';

  @override
  String get aiMatrixHint =>
      'Allowing is your switch; whether it can be sent is platform × route × model.';

  @override
  String get aiCapTools => 'Tool calling';

  @override
  String get aiCapToolsHint => 'Organize and scrape need it';

  @override
  String get aiCapJson => 'JSON mode';

  @override
  String get aiCapJsonHint => 'Connection-test fallback only';

  @override
  String get aiCapImage => 'Image input';

  @override
  String get aiCapVideo => 'Video input';

  @override
  String get aiCapThinkingOff => 'Reasoning off';

  @override
  String get aiCapThinkingOffHint =>
      'Judged by whether the reply still reasoned';

  @override
  String get aiCapUsage => 'Usage reporting';

  @override
  String get aiCapUsageHint => 'Not reported ≠ 0';

  @override
  String get aiCapAllowed => 'allowed';

  @override
  String get aiCapNotAllowed => 'not allowed';

  @override
  String get aiColCurrent => 'current';

  @override
  String get aiColEnabled => 'enabled';

  @override
  String get aiColOffered => 'not enabled';

  @override
  String get aiCellMeasured => 'works · measured';

  @override
  String get aiCellUnmeasured => 'not measured';

  @override
  String get aiCellUnsupported => 'not supported · measured';

  @override
  String aiCellLearned(String mode) {
    return '$mode · learned';
  }

  @override
  String get aiCellParameter => 'parameter, not measured';

  @override
  String get aiCellNotInBuild => 'not in this build';

  @override
  String aiCellSwitch(String field) {
    return '$field · platform switch';
  }

  @override
  String get aiCellLadder => 'ladder · judged by reply';

  @override
  String get aiCellLadderExhausted => 'no way worked here';

  @override
  String get aiCellProtocolUsage => 'part of the protocol';

  @override
  String get aiCellNotAllowed => 'not allowed';

  @override
  String get aiMatrixFootnote =>
      'Task pickers read this matrix: a model is offered for frame recognition only where image input can actually be sent on its current route.';

  @override
  String get aiDiagTest => 'Test a route';

  @override
  String get aiDiagRun => 'Run test';

  @override
  String get aiStepReach => 'Reachable';

  @override
  String aiStepServer(String kind) {
    return 'Identified as $kind';
  }

  @override
  String aiStepGenerate(int ms, int prompt, int completion) {
    return 'Generated in $ms ms · $prompt + $completion tokens';
  }

  @override
  String get aiStepTruncated => 'Reply hit the output limit';

  @override
  String get aiStepThinkingOff => 'Reasoning is off';

  @override
  String get aiStepThinkingStillOn => 'The model still reasoned';

  @override
  String get aiStepThinkingOn => 'The model reasoned';

  @override
  String get aiStepThinkingNotOn =>
      'Reasoning was asked for, but the reply shows none';

  @override
  String get aiStepThinkingRefused =>
      'The route refused the request for reasoning';

  @override
  String get aiStepTools => 'Called the test tool';

  @override
  String get aiStepToolsNo => 'Did not call the test tool';

  @override
  String get aiStepToolsUnknown =>
      'Tool calling undecided — the request did not complete';

  @override
  String get aiStepUsage => 'Usage reported';

  @override
  String get aiStepUsageMissing =>
      'No usage reported (counted as unknown, not 0)';

  @override
  String aiStepContext(int served, int typed) {
    return 'Context: the server serves $served, you entered $typed';
  }

  @override
  String get aiStepContextBody =>
      'A local server past its window drops the system prompt from the front without a word.';

  @override
  String get aiStepUseServed => 'Use the served value';

  @override
  String get aiLogTitle => 'API log · today';

  @override
  String get aiLogHint => 'Every body actually sent, numbered';

  @override
  String get aiLogOff => 'Logging is off. Turn it on to record requests.';

  @override
  String get aiLogEmpty => 'Nothing logged today.';

  @override
  String get aiLogOpenFolder => 'Show in folder';

  @override
  String get aiLogFootnote =>
      'Keys are never written; images and strings over 2 KB are replaced by their length; writes are serial, so concurrent requests never interleave.';

  @override
  String get scrapeBackendAssigned => 'As assigned in Settings';

  @override
  String get aiPlatformLabel => 'Platform';

  @override
  String get aiMergeConfirmTitle => 'Merge channels';

  @override
  String aiMergeConfirmBody(String name) {
    return 'Routes and models move into “$name” and the other channels are removed. Every model keeps its URL, parameters and task assignments.';
  }

  @override
  String get aiCellPromptOnly => 'no parameter · prompt only';

  @override
  String get aiCellAlwaysReasons => 'this model always reasons';

  @override
  String aiCellProtocolSwitch(String field) {
    return '$field · protocol field';
  }

  @override
  String get aiCellDefaultOff => 'off by default';

  @override
  String get aiCellModelDefault => 'the model’s default';

  @override
  String aiCellSentAs(String part) {
    return 'sent as $part · not measured';
  }

  @override
  String get aiCellAsFrames => 'as image frames · not measured';

  @override
  String get aiVisionAllowFrames => 'Send video frames to this model';

  @override
  String get aiVisionAllowFramesHint =>
      'Off by default: frames leave this computer. Organize uses them only for videos whose names say nothing, and every group decided that way is flagged for review.';
}
