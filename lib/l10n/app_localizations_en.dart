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
  String get appBrand => 'Jellyfin Organizer';

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
  String get accentColor => 'Accent color';

  @override
  String get behavior => 'Behavior';

  @override
  String get behaviorAutoConnect => 'Auto-connect to AI service on launch';

  @override
  String get behaviorAlwaysPreview => 'Always show preview before applying';

  @override
  String get behaviorLowConfSuggest =>
      'Only suggest (don\'t auto-apply) when confidence < 60%';

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
  String get shortcutSearch => 'Focus search';

  @override
  String get shortcutCloseDialog => 'Close dialog';

  @override
  String get aboutTagline => 'AI-driven media organizer for Jellyfin.';

  @override
  String get aboutJellyfinNaming => 'Jellyfin naming guide';

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
  String get onboardingWelcomeTitle => 'Welcome to Jellyfin Organizer';

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
}
