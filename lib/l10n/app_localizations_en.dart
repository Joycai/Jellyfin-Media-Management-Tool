// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Jellyfin Media Management Tool';

  @override
  String get manager => 'Manager';

  @override
  String get settings => 'Settings';

  @override
  String get mediaManager => 'Media Manager';

  @override
  String get pickDirectory => 'Pick Directory';

  @override
  String get openDirectory => 'Open Directory';

  @override
  String get parentFolder => 'Parent Folder';

  @override
  String get createNewFolder => 'Create New Folder';

  @override
  String get refresh => 'Refresh';

  @override
  String get sortBy => 'Sort By';

  @override
  String get sortByName => 'Sort by Name';

  @override
  String get sortByType => 'Sort by Type';

  @override
  String get sortByDate => 'Sort by Date';

  @override
  String get sortBySize => 'Sort by Size';

  @override
  String get ascending => 'Ascending';

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
  String get playVideo => 'Play Video';

  @override
  String get openFile => 'Open File';

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
  String get confirmRename => 'Confirm Rename';

  @override
  String get renameFrom => 'From:';

  @override
  String get renameTo => 'To:';

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
  String get searchFromWeb => 'Search from Web';

  @override
  String get searchKeyword => 'Search Keyword';

  @override
  String get searchSite => 'Search Site';

  @override
  String get search => 'Search';

  @override
  String get editSearchSites => 'Edit Search Sites';

  @override
  String get siteName => 'Site Name';

  @override
  String get searchUrl => 'Search URL';

  @override
  String get addSite => 'Add Site';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get openConfigFolder => 'Open Configuration Folder';

  @override
  String get areYouSure => 'Are you sure?';

  @override
  String sizeLabel(Object size) {
    return 'Size: $size';
  }

  @override
  String durationLabel(Object duration) {
    return 'Duration: $duration';
  }

  @override
  String resolutionLabel(Object resolution) {
    return 'Resolution: $resolution';
  }

  @override
  String get noDirectorySelected => 'No directory selected';

  @override
  String get pleaseSelectDirectory => 'Please select a directory';

  @override
  String get noPreviewAvailable => 'No preview available';

  @override
  String get directoriesCannotBePreviewed => 'Directories cannot be previewed';

  @override
  String errorAccessingDirectory(Object error) {
    return 'Error accessing directory: $error';
  }

  @override
  String errorCreatingFolder(Object error) {
    return 'Error creating folder: $error';
  }

  @override
  String errorRenaming(Object error) {
    return 'Error renaming: $error';
  }

  @override
  String get noSearchSitesConfigured =>
      'No search sites configured in Settings';

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
  String get noFolderOpen => 'Open a folder to begin';

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
  String get confirmApplyTitle => 'Apply organization?';

  @override
  String confirmApplyBody(Object count) {
    return '$count files will be moved and renamed into the Jellyfin structure.';
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
  String analyzeFailed(Object error) {
    return 'Failed: $error';
  }

  @override
  String get aiSettings => 'AI Service';

  @override
  String get provider => 'Provider';

  @override
  String get providerOpenAi => 'OpenAI-compatible';

  @override
  String get providerGoogle => 'Google GenAI';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get apiKey => 'API Key';

  @override
  String get model => 'Model';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get connectionOk => 'Connection successful';

  @override
  String connectionFailed(Object error) {
    return 'Connection failed: $error';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get aiServicesTitle => 'AI Services';

  @override
  String get aiServicesSubtitle =>
      'Configure the language models used to organize media';

  @override
  String get aiServiceDetailHint =>
      'Primary AI endpoint for organization and metadata matching';

  @override
  String get addService => 'Add service';

  @override
  String get addAnotherEndpoint => 'Add another endpoint';

  @override
  String get newServiceName => 'New Service';

  @override
  String get statusActive => 'Active';

  @override
  String get useThisService => 'Use this service';

  @override
  String get statusStandby => 'Standby';

  @override
  String get statusOffline => 'Offline';

  @override
  String get endpointProtocol => 'Endpoint protocol';

  @override
  String get protocolOpenAi => 'OpenAI compatible';

  @override
  String get protocolGoogle => 'Google GenAI';

  @override
  String get displayName => 'Display name';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get showKey => 'Show';

  @override
  String get hideKey => 'Hide';

  @override
  String get defaultModel => 'Default model';

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
  String get toolsSupported =>
      'Tool calling: supported. This model can organize folders and scrape metadata.';

  @override
  String get toolsUnsupported =>
      'Tool calling: not supported. This model cannot be used to organize folders or scrape metadata.';

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
  String get selectServiceHint => 'Select a service to configure';

  @override
  String get deleteServiceTitle => 'Delete service';

  @override
  String deleteServiceConfirm(Object name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

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
  String get breadcrumbPaths => 'Paths';

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
  String get glassNone => 'None';

  @override
  String get glassSoft => 'Soft';

  @override
  String get glassStrong => 'Strong';

  @override
  String get performanceMode => 'Performance mode';

  @override
  String get performanceModeDesc =>
      'Turn off the backdrop blur and the large shadows. Worth it on integrated graphics or a high-resolution display, where the blur is redrawn over every pixel each frame.';

  @override
  String get accentColor => 'Accent color';

  @override
  String get behavior => 'Behavior';

  @override
  String get behaviorVideoThumbnails =>
      'Show video thumbnails in the file list';

  @override
  String get privacyStorage => 'Local storage';

  @override
  String get privacyConfigBody =>
      'Settings, AI keys and undo manifests are stored on this device only.';

  @override
  String privacyClearHistory(Object count) {
    return 'Undo all $count entries';
  }

  @override
  String privacyClearThumbnails(Object size) {
    return 'Clear thumbnail cache ($size)';
  }

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
  String get aboutGpu => 'Graphics adapter';

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
  String get batchScrapeScanning => 'Looking for titles to refresh…';

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
  String get scrapeUrlTitle => 'Scrape metadata';

  @override
  String scrapeUrlSubtitle(Object target) {
    return 'Metadata will be written next to $target';
  }

  @override
  String get scrapeUrlLabel => 'Product page URL';

  @override
  String get scrapeUrlHint => 'https://example.com/product/12345';

  @override
  String get scrapeUrlInvalid =>
      'Enter a full URL, including http:// or https://';

  @override
  String scrapeDetectedCode(Object code) {
    return 'Detected code: $code';
  }

  @override
  String scrapeSearchOnSite(Object site) {
    return 'Search on $site';
  }

  @override
  String get scrapePasteHtml => 'Paste the page HTML instead';

  @override
  String get scrapePasteHtmlHint => 'Paste the page source here';

  @override
  String get scrapePasteNeedsUrl =>
      'The URL is still required — relative links in the pasted HTML are resolved against it.';

  @override
  String get scrapeCookieBuiltIn => 'This site has a built-in access cookie.';

  @override
  String get scrapeCookieMissing =>
      'No cookies configured for this site. If the fetch fails, import a cookies.txt under Settings → Scraping.';

  @override
  String get scrapeStart => 'Scrape';

  @override
  String get scrapeStarted => 'Scrape started — see Tasks for progress';

  @override
  String scrapeFailed(Object error) {
    return 'Scrape failed: $error';
  }

  @override
  String get scrapeReady => 'Scrape finished — review the result';

  @override
  String get scrapeReview => 'Review';

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
  String get scrapeRecipeNone => 'none';

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
  String get scrapeWrite => 'Write';

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
  String scrapeNfoAutoDetected(Object name) {
    return 'Auto-detected from $name';
  }

  @override
  String get scrapePanelTitle => 'Scrape metadata';

  @override
  String get scrapeProcess => 'Process';

  @override
  String get scrapeWorking => 'Working…';

  @override
  String get scrapeBackToSetup => 'Back';

  @override
  String get scrapeRetry => 'Try again';

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
  String get ruleEditorAiFill => 'AI smart fill';

  @override
  String get ruleEditorAiFillHint =>
      'When a file name cannot be parsed, ask the AI to infer the title, year and language.';

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
  String get toggleSidebar => 'Show or hide the sidebar';

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
      'config.json · ai_profiles.json · sites.json · scrapers.json';

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
  String get privacyLogAiBodiesHint =>
      'For troubleshooting only — logs grow quickly';

  @override
  String get privacyClearTempOnExit => 'Empty the temporary folder on exit';

  @override
  String get privacyNoTelemetry =>
      'This app collects no telemetry of any kind and has no log file, so these switches have nothing to turn off yet.';

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
  String get aboutBranch => 'Branch';

  @override
  String get aboutRuntime => 'Runtime';

  @override
  String get aboutBuildInfoPlaceholder =>
      'Commit and branch are stamped in at package time, which this build does not do yet.';

  @override
  String get aboutSystem => 'System';

  @override
  String get aboutOs => 'OS';

  @override
  String get aboutArch => 'Architecture';

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
  String get aboutGraphics => 'Graphics adapter';

  @override
  String get aboutGpuRunning => 'In use';

  @override
  String get aboutGpuShared => 'Shared memory';

  @override
  String get accentPickerTitle => 'Accent colour';

  @override
  String get accentRestoreDefault => 'Restore the default blue';

  @override
  String get accentRecents => 'Recently used';

  @override
  String get accentRecentsEmpty => 'Nothing yet';

  @override
  String get accentEyedropper => 'Pick a colour from the screen';

  @override
  String accentContrastOk(Object dark, Object light) {
    return 'Contrast against the dark and light window bases: $dark:1 · $light:1';
  }

  @override
  String accentContrastWeak(Object dark, Object light) {
    return 'Contrast $dark:1 · $light:1 — below 3:1, so use it as a fill only';
  }

  @override
  String get modelParameters => 'Model parameters';

  @override
  String get modelParametersExpand => 'Expand';

  @override
  String get modelParametersCollapse => 'Collapse';

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
}
