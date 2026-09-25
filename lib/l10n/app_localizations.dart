import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @manager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get manager;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @parentFolder.
  ///
  /// In en, this message translates to:
  /// **'Parent Folder'**
  String get parentFolder;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @descending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descending;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @newName.
  ///
  /// In en, this message translates to:
  /// **'New Name'**
  String get newName;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// No description provided for @renameFile.
  ///
  /// In en, this message translates to:
  /// **'Rename File'**
  String get renameFile;

  /// No description provided for @operations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get operations;

  /// No description provided for @matchFolderName.
  ///
  /// In en, this message translates to:
  /// **'Match Folder Name'**
  String get matchFolderName;

  /// No description provided for @renameToFeaturette.
  ///
  /// In en, this message translates to:
  /// **'Rename to Featurette'**
  String get renameToFeaturette;

  /// No description provided for @renameToInterview.
  ///
  /// In en, this message translates to:
  /// **'Rename to Interview'**
  String get renameToInterview;

  /// No description provided for @renameToPart.
  ///
  /// In en, this message translates to:
  /// **'Rename to Part...'**
  String get renameToPart;

  /// No description provided for @renameToTVShow.
  ///
  /// In en, this message translates to:
  /// **'Rename to TV Show...'**
  String get renameToTVShow;

  /// No description provided for @jellyfinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin Subtitle...'**
  String get jellyfinSubtitle;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @openConfigFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Configuration Folder'**
  String get openConfigFolder;

  /// No description provided for @sizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String sizeLabel(Object size);

  /// No description provided for @noPreviewAvailable.
  ///
  /// In en, this message translates to:
  /// **'No preview available'**
  String get noPreviewAvailable;

  /// No description provided for @errorRenaming.
  ///
  /// In en, this message translates to:
  /// **'Error renaming: {error}'**
  String errorRenaming(Object error);

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get season;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get episode;

  /// No description provided for @selectPart.
  ///
  /// In en, this message translates to:
  /// **'Select Part'**
  String get selectPart;

  /// No description provided for @customPart.
  ///
  /// In en, this message translates to:
  /// **'Custom Part'**
  String get customPart;

  /// No description provided for @customPartHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 5'**
  String get customPartHint;

  /// No description provided for @partLabel.
  ///
  /// In en, this message translates to:
  /// **'Part {count}'**
  String partLabel(Object count);

  /// No description provided for @tvShowDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'TV show episode (SxxExx)'**
  String get tvShowDialogTitle;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @isDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get isDefault;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @subtitleLangZhHans.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get subtitleLangZhHans;

  /// No description provided for @subtitleLangZhHant.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get subtitleLangZhHant;

  /// No description provided for @subtitleLangJa.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get subtitleLangJa;

  /// No description provided for @subtitleLangEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get subtitleLangEn;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @appBrand.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin Media Management Tool'**
  String get appBrand;

  /// No description provided for @tabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

  /// No description provided for @tabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// No description provided for @tabTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tabTasks;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files, movies, shows...'**
  String get searchHint;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavorites;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @noRecent.
  ///
  /// In en, this message translates to:
  /// **'Nothing recent'**
  String get noRecent;

  /// No description provided for @locations.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get locations;

  /// No description provided for @aiConnected.
  ///
  /// In en, this message translates to:
  /// **'AI service connected'**
  String get aiConnected;

  /// No description provided for @aiConnectionError.
  ///
  /// In en, this message translates to:
  /// **'AI connection error'**
  String get aiConnectionError;

  /// No description provided for @aiTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing connection...'**
  String get aiTesting;

  /// No description provided for @aiReady.
  ///
  /// In en, this message translates to:
  /// **'AI ready'**
  String get aiReady;

  /// No description provided for @aiNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI not configured'**
  String get aiNotConfigured;

  /// No description provided for @itemsProcessed.
  ///
  /// In en, this message translates to:
  /// **'{count} items processed'**
  String itemsProcessed(Object count);

  /// No description provided for @organizeWithAi.
  ///
  /// In en, this message translates to:
  /// **'Organize all with AI'**
  String get organizeWithAi;

  /// No description provided for @organizeSelectedWithAi.
  ///
  /// In en, this message translates to:
  /// **'Organize selected with AI ({count})'**
  String organizeSelectedWithAi(Object count);

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @menuPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get menuPreview;

  /// No description provided for @menuProperties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get menuProperties;

  /// No description provided for @menuRevealInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Show in file manager'**
  String get menuRevealInFileManager;

  /// No description provided for @newNameLabel.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get newNameLabel;

  /// No description provided for @deleteSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'Delete selected ({count})'**
  String deleteSelectedCount(Object count);

  /// No description provided for @deleteConfirmOne.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteConfirmOne(Object name);

  /// No description provided for @deleteConfirmMany.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} selected items? This cannot be undone.'**
  String deleteConfirmMany(Object count);

  /// No description provided for @deletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} items'**
  String deletedCount(Object count);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(Object error);

  /// No description provided for @revealFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the system file manager'**
  String get revealFailed;

  /// No description provided for @propModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get propModified;

  /// No description provided for @propPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get propPath;

  /// No description provided for @fontSection.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontSection;

  /// No description provided for @fontSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get fontSystem;

  /// No description provided for @fontStatusDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get fontStatusDownloaded;

  /// No description provided for @fontStatusNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Needs download'**
  String get fontStatusNotDownloaded;

  /// No description provided for @fontDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download font'**
  String get fontDownloadTitle;

  /// No description provided for @fontDownloadConfirm.
  ///
  /// In en, this message translates to:
  /// **'First-time use of {name} requires a one-time download of the official font package (saved to the app data folder). Continue?'**
  String fontDownloadConfirm(Object name);

  /// No description provided for @fontDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}…'**
  String fontDownloading(Object name);

  /// No description provided for @fontDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Font download failed: {error}'**
  String fontDownloadFailed(Object error);

  /// No description provided for @downloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadAction;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openFolder;

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get folderEmpty;

  /// No description provided for @colName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get colName;

  /// No description provided for @colType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get colType;

  /// No description provided for @colSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get colSize;

  /// No description provided for @colAiSuggestion.
  ///
  /// In en, this message translates to:
  /// **'AI Suggestion'**
  String get colAiSuggestion;

  /// No description provided for @colConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get colConfidence;

  /// No description provided for @typeFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get typeFolder;

  /// No description provided for @typeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get typeVideo;

  /// No description provided for @typeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get typeSubtitle;

  /// No description provided for @typeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get typeImage;

  /// No description provided for @typeMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get typeMetadata;

  /// No description provided for @typeAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get typeAudio;

  /// No description provided for @typeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get typeText;

  /// No description provided for @typeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get typeOther;

  /// No description provided for @needsReview.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get needsReview;

  /// No description provided for @analyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing...'**
  String get analyzing;

  /// No description provided for @analysisComplete.
  ///
  /// In en, this message translates to:
  /// **'Analysis complete'**
  String get analysisComplete;

  /// No description provided for @notAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Not analyzed'**
  String get notAnalyzed;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(Object count);

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(Object count);

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @analyzingSelected.
  ///
  /// In en, this message translates to:
  /// **'Analyzing selected files'**
  String get analyzingSelected;

  /// No description provided for @aiPanelIdle.
  ///
  /// In en, this message translates to:
  /// **'Configure AI, then organize a folder'**
  String get aiPanelIdle;

  /// No description provided for @reasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get reasoning;

  /// No description provided for @targetStructure.
  ///
  /// In en, this message translates to:
  /// **'Target Structure'**
  String get targetStructure;

  /// No description provided for @previewOrganize.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewOrganize;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @usage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usage;

  /// No description provided for @tokensLabel.
  ///
  /// In en, this message translates to:
  /// **'{tokens} tokens'**
  String tokensLabel(Object tokens);

  /// No description provided for @applyDone.
  ///
  /// In en, this message translates to:
  /// **'Organized {count} files'**
  String applyDone(Object count);

  /// No description provided for @applyPartial.
  ///
  /// In en, this message translates to:
  /// **'Organized {succeeded}, {failed} failed'**
  String applyPartial(Object failed, Object succeeded);

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get endpoint;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailed(Object error);

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @showKey.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showKey;

  /// No description provided for @hideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideKey;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @apiKeyOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Optional for local servers (LM Studio, Ollama…)'**
  String get apiKeyOptionalHint;

  /// No description provided for @contextWindow.
  ///
  /// In en, this message translates to:
  /// **'Context window (tokens)'**
  String get contextWindow;

  /// No description provided for @contextWindowHint.
  ///
  /// In en, this message translates to:
  /// **'Blank = send everything'**
  String get contextWindowHint;

  /// No description provided for @maxOutputTokens.
  ///
  /// In en, this message translates to:
  /// **'Max output tokens'**
  String get maxOutputTokens;

  /// No description provided for @maxOutputTokensHint.
  ///
  /// In en, this message translates to:
  /// **'Blank = server default'**
  String get maxOutputTokensHint;

  /// No description provided for @contextWindowNote.
  ///
  /// In en, this message translates to:
  /// **'The app cannot change a server\'s context size. Set it where the model is loaded (LM Studio, Ollama, llama.cpp) and enter the same number here: large folders are then organized in batches, and scraped pages are trimmed to fit.'**
  String get contextWindowNote;

  /// No description provided for @connectionIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Fill in the base URL and model first (Google also needs an API key)'**
  String get connectionIncomplete;

  /// No description provided for @connectionOkReply.
  ///
  /// In en, this message translates to:
  /// **'Connected in {ms} ms. The model replied: {reply}'**
  String connectionOkReply(Object ms, Object reply);

  /// No description provided for @connectionEmptyReply.
  ///
  /// In en, this message translates to:
  /// **'(empty reply)'**
  String get connectionEmptyReply;

  /// No description provided for @connectionTruncated.
  ///
  /// In en, this message translates to:
  /// **'The reply hit the output limit. Raise Max output tokens before organizing.'**
  String get connectionTruncated;

  /// No description provided for @detectedContextWindow.
  ///
  /// In en, this message translates to:
  /// **'{source} reports a context window of {tokens} tokens'**
  String detectedContextWindow(Object source, Object tokens);

  /// No description provided for @detectedModelMaximum.
  ///
  /// In en, this message translates to:
  /// **'{source} reports the model supports up to {tokens} tokens; the loaded size may be smaller'**
  String detectedModelMaximum(Object source, Object tokens);

  /// No description provided for @detectedMaxOutput.
  ///
  /// In en, this message translates to:
  /// **'max output {tokens}'**
  String detectedMaxOutput(Object tokens);

  /// No description provided for @limitsNotDetected.
  ///
  /// In en, this message translates to:
  /// **'The server did not report a context size. Check it where the model is loaded.'**
  String get limitsNotDetected;

  /// No description provided for @useDetectedValue.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get useDetectedValue;

  /// No description provided for @samplingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sampling'**
  String get samplingTitle;

  /// No description provided for @samplingPresetMatched.
  ///
  /// In en, this message translates to:
  /// **'Recommended values for {name}'**
  String samplingPresetMatched(Object name);

  /// No description provided for @samplingPresetSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get samplingPresetSource;

  /// No description provided for @samplingNoPreset.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized model family: the server\'s defaults apply'**
  String get samplingNoPreset;

  /// No description provided for @samplingReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to recommended'**
  String get samplingReset;

  /// No description provided for @samplingDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get samplingDefault;

  /// No description provided for @samplingTopP.
  ///
  /// In en, this message translates to:
  /// **'Top P'**
  String get samplingTopP;

  /// No description provided for @samplingTopK.
  ///
  /// In en, this message translates to:
  /// **'Top K'**
  String get samplingTopK;

  /// No description provided for @samplingMinP.
  ///
  /// In en, this message translates to:
  /// **'Min P'**
  String get samplingMinP;

  /// No description provided for @samplingPresencePenalty.
  ///
  /// In en, this message translates to:
  /// **'Presence penalty'**
  String get samplingPresencePenalty;

  /// No description provided for @samplingRepeatPenalty.
  ///
  /// In en, this message translates to:
  /// **'Repeat penalty'**
  String get samplingRepeatPenalty;

  /// No description provided for @samplingNote.
  ///
  /// In en, this message translates to:
  /// **'Leave a field blank to use the recommended value.'**
  String get samplingNote;

  /// No description provided for @thinkingMode.
  ///
  /// In en, this message translates to:
  /// **'Thinking mode'**
  String get thinkingMode;

  /// No description provided for @thinkingModeHint.
  ///
  /// In en, this message translates to:
  /// **'Off by default: reasoning makes small local models far slower and prone to going in circles.'**
  String get thinkingModeHint;

  /// No description provided for @thinkingAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'This model can only run with reasoning on.'**
  String get thinkingAlwaysOn;

  /// No description provided for @thinkingEffortOnly.
  ///
  /// In en, this message translates to:
  /// **'This model\'s reasoning cannot be turned off; with thinking off it runs at low effort.'**
  String get thinkingEffortOnly;

  /// No description provided for @thinkingVerifiedOff.
  ///
  /// In en, this message translates to:
  /// **'Last test: reasoning was off.'**
  String get thinkingVerifiedOff;

  /// No description provided for @thinkingStillOn.
  ///
  /// In en, this message translates to:
  /// **'Last test: the model still reasoned. Turn thinking off in the server\'s own model settings (in LM Studio: Enable Thinking).'**
  String get thinkingStillOn;

  /// No description provided for @presetNeedsSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'This model\'s card requires its own system prompt; results may suffer without it.'**
  String get presetNeedsSystemPrompt;

  /// No description provided for @ollamaIgnoresSampling.
  ///
  /// In en, this message translates to:
  /// **'Ollama\'s OpenAI-compatible API ignores Top K, Min P and Repeat penalty; set them in the Modelfile instead.'**
  String get ollamaIgnoresSampling;

  /// No description provided for @tokensThisSession.
  ///
  /// In en, this message translates to:
  /// **'Tokens this session'**
  String get tokensThisSession;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @avgLatency.
  ///
  /// In en, this message translates to:
  /// **'Avg latency'**
  String get avgLatency;

  /// No description provided for @previewTitle.
  ///
  /// In en, this message translates to:
  /// **'Organize {count} items into Jellyfin structure'**
  String previewTitle(Object count);

  /// No description provided for @previewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Move {folders} folders, {size} · avg AI confidence {pct}%'**
  String previewSubtitle(Object folders, Object pct, Object size);

  /// No description provided for @viewTree.
  ///
  /// In en, this message translates to:
  /// **'Tree compare'**
  String get viewTree;

  /// No description provided for @viewList.
  ///
  /// In en, this message translates to:
  /// **'View list'**
  String get viewList;

  /// No description provided for @viewPoster.
  ///
  /// In en, this message translates to:
  /// **'Poster view'**
  String get viewPoster;

  /// No description provided for @showOnly.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showOnly;

  /// No description provided for @filterChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get filterChanges;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts ({count})'**
  String filterConflicts(Object count);

  /// No description provided for @countMoves.
  ///
  /// In en, this message translates to:
  /// **'{count} moved'**
  String countMoves(Object count);

  /// No description provided for @countRenames.
  ///
  /// In en, this message translates to:
  /// **'{count} renamed'**
  String countRenames(Object count);

  /// No description provided for @countConflicts.
  ///
  /// In en, this message translates to:
  /// **'{count} conflicts'**
  String countConflicts(Object count);

  /// No description provided for @beforeLabel.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get beforeLabel;

  /// No description provided for @afterLabel.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get afterLabel;

  /// No description provided for @aiOrganizeVertical.
  ///
  /// In en, this message translates to:
  /// **'AI · JELLYFIN'**
  String get aiOrganizeVertical;

  /// No description provided for @needsReviewSuffix.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get needsReviewSuffix;

  /// No description provided for @recordUndoHistory.
  ///
  /// In en, this message translates to:
  /// **'Record undo history (7 days)'**
  String get recordUndoHistory;

  /// No description provided for @applyOrganizeCount.
  ///
  /// In en, this message translates to:
  /// **'Apply ({count})'**
  String applyOrganizeCount(Object count);

  /// No description provided for @editTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit target path'**
  String get editTargetTitle;

  /// No description provided for @targetPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Target path (relative to the organized folder)'**
  String get targetPathLabel;

  /// No description provided for @targetPathInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid path — must stay inside the organized folder'**
  String get targetPathInvalid;

  /// No description provided for @namingRules.
  ///
  /// In en, this message translates to:
  /// **'Apply a naming rule'**
  String get namingRules;

  /// No description provided for @editedBadge.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get editedBadge;

  /// No description provided for @markResolved.
  ///
  /// In en, this message translates to:
  /// **'Accept this proposal'**
  String get markResolved;

  /// No description provided for @organizing.
  ///
  /// In en, this message translates to:
  /// **'Organizing · {count} items'**
  String organizing(Object count);

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Organization complete'**
  String get statusDone;

  /// No description provided for @statusStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get statusStopped;

  /// No description provided for @etaRemaining.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s remaining'**
  String etaRemaining(Object minutes, Object seconds);

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @doneClose.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneClose;

  /// No description provided for @legendDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get legendDone;

  /// No description provided for @legendInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get legendInProgress;

  /// No description provided for @legendQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get legendQueued;

  /// No description provided for @legendSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get legendSkipped;

  /// No description provided for @logStarted.
  ///
  /// In en, this message translates to:
  /// **'Started · {count} items'**
  String logStarted(Object count);

  /// No description provided for @logMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved {name} → {dir}/'**
  String logMoved(Object dir, Object name);

  /// No description provided for @logSkipped.
  ///
  /// In en, this message translates to:
  /// **'{name} · needs review'**
  String logSkipped(Object name);

  /// No description provided for @logFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed {name} · {error}'**
  String logFailed(Object error, Object name);

  /// No description provided for @logFinished.
  ///
  /// In en, this message translates to:
  /// **'Done · {done} organized, {skipped} skipped'**
  String logFinished(Object done, Object skipped);

  /// No description provided for @logStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped · {done} organized, {skipped} skipped'**
  String logStopped(Object done, Object skipped);

  /// No description provided for @logUndoLost.
  ///
  /// In en, this message translates to:
  /// **'Undo unavailable · {error}'**
  String logUndoLost(Object error);

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Operation history'**
  String get historyTitle;

  /// No description provided for @historyRetention.
  ///
  /// In en, this message translates to:
  /// **'Kept {days} days'**
  String historyRetention(Object days);

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get historyEmpty;

  /// No description provided for @historyUndoFootnote.
  ///
  /// In en, this message translates to:
  /// **'Undo reverts every file\'s location and name. Metadata caches are preserved.'**
  String get historyUndoFootnote;

  /// No description provided for @historyTitleAi.
  ///
  /// In en, this message translates to:
  /// **'AI organize · {count} items'**
  String historyTitleAi(Object count);

  /// No description provided for @historyTitleManual.
  ///
  /// In en, this message translates to:
  /// **'Manual rename · {count} items'**
  String historyTitleManual(Object count);

  /// No description provided for @historyTitleMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata refresh'**
  String get historyTitleMetadata;

  /// No description provided for @historyTitleImport.
  ///
  /// In en, this message translates to:
  /// **'Batch import · {count} items'**
  String historyTitleImport(Object count);

  /// No description provided for @subMoves.
  ///
  /// In en, this message translates to:
  /// **'{count} moved'**
  String subMoves(Object count);

  /// No description provided for @subRenames.
  ///
  /// In en, this message translates to:
  /// **'{count} renamed'**
  String subRenames(Object count);

  /// No description provided for @subWritten.
  ///
  /// In en, this message translates to:
  /// **'{count} written'**
  String subWritten(Object count);

  /// No description provided for @subReplaced.
  ///
  /// In en, this message translates to:
  /// **'{count} replaced'**
  String subReplaced(Object count);

  /// No description provided for @historyRowWritten.
  ///
  /// In en, this message translates to:
  /// **'written'**
  String get historyRowWritten;

  /// No description provided for @historyRowReplaced.
  ///
  /// In en, this message translates to:
  /// **'replaced'**
  String get historyRowReplaced;

  /// No description provided for @undoAction.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoAction;

  /// No description provided for @movesListTitle.
  ///
  /// In en, this message translates to:
  /// **'Move list · {count}'**
  String movesListTitle(Object count);

  /// No description provided for @undoDone.
  ///
  /// In en, this message translates to:
  /// **'Undone {count} files'**
  String undoDone(Object count);

  /// No description provided for @undoPartial.
  ///
  /// In en, this message translates to:
  /// **'Undid {succeeded}, {failed} failed'**
  String undoPartial(Object failed, Object succeeded);

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String timeMinutesAgo(Object count);

  /// No description provided for @timeToday.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String timeToday(Object time);

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timeYesterday;

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String timeDaysAgo(Object count);

  /// No description provided for @secAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get secAppearance;

  /// No description provided for @secLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get secLanguage;

  /// No description provided for @secPaths.
  ///
  /// In en, this message translates to:
  /// **'Paths'**
  String get secPaths;

  /// No description provided for @secAiServices.
  ///
  /// In en, this message translates to:
  /// **'AI Services'**
  String get secAiServices;

  /// No description provided for @secPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Cache'**
  String get secPrivacy;

  /// No description provided for @secShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get secShortcuts;

  /// No description provided for @secAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get secAbout;

  /// No description provided for @versionUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get versionUpToDate;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @glassIntensity.
  ///
  /// In en, this message translates to:
  /// **'Glass intensity'**
  String get glassIntensity;

  /// No description provided for @glassNone.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get glassNone;

  /// No description provided for @glassSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get glassSoft;

  /// No description provided for @glassStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get glassStrong;

  /// No description provided for @glassOffHint.
  ///
  /// In en, this message translates to:
  /// **'Blur is off: panels use opaque fills. This is the cheapest the interface can draw.'**
  String get glassOffHint;

  /// No description provided for @glassOnHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to 0 to turn the blur off entirely. The strength itself costs almost nothing — how the blur is computed is the setting under Behavior.'**
  String get glassOnHint;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @behavior.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get behavior;

  /// No description provided for @behaviorBakedGlass.
  ///
  /// In en, this message translates to:
  /// **'Pre-render the glass blur'**
  String get behaviorBakedGlass;

  /// No description provided for @behaviorBakedGlassDesc.
  ///
  /// In en, this message translates to:
  /// **'Blurs the window background once and reuses it instead of re-blurring every frame. Far cheaper on the GPU, and the panels look the same.'**
  String get behaviorBakedGlassDesc;

  /// No description provided for @behaviorBakedGlassUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nothing to pre-render while the blur is off.'**
  String get behaviorBakedGlassUnavailable;

  /// No description provided for @behaviorVideoThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Show video thumbnails in the file list'**
  String get behaviorVideoThumbnails;

  /// No description provided for @shortcutGroupNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get shortcutGroupNavigation;

  /// No description provided for @shortcutGroupSelection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get shortcutGroupSelection;

  /// No description provided for @shortcutGroupFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get shortcutGroupFiles;

  /// No description provided for @shortcutGroupApp.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get shortcutGroupApp;

  /// No description provided for @shortcutsHint.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts are inactive while you are typing in a text field, except for search.'**
  String get shortcutsHint;

  /// No description provided for @shortcutSearch.
  ///
  /// In en, this message translates to:
  /// **'Focus search'**
  String get shortcutSearch;

  /// No description provided for @shortcutParentFolder.
  ///
  /// In en, this message translates to:
  /// **'Go to parent folder'**
  String get shortcutParentFolder;

  /// No description provided for @shortcutOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open a folder'**
  String get shortcutOpenFolder;

  /// No description provided for @shortcutRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh the file list'**
  String get shortcutRefresh;

  /// No description provided for @shortcutSectionFiles.
  ///
  /// In en, this message translates to:
  /// **'Go to Files'**
  String get shortcutSectionFiles;

  /// No description provided for @shortcutSectionLibrary.
  ///
  /// In en, this message translates to:
  /// **'Go to Library'**
  String get shortcutSectionLibrary;

  /// No description provided for @shortcutSectionTasks.
  ///
  /// In en, this message translates to:
  /// **'Go to Tasks'**
  String get shortcutSectionTasks;

  /// No description provided for @shortcutSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select every visible file'**
  String get shortcutSelectAll;

  /// No description provided for @shortcutEscape.
  ///
  /// In en, this message translates to:
  /// **'Close dialog · clear search or selection'**
  String get shortcutEscape;

  /// No description provided for @shortcutRename.
  ///
  /// In en, this message translates to:
  /// **'Rename the focused file'**
  String get shortcutRename;

  /// No description provided for @shortcutDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete the selection'**
  String get shortcutDelete;

  /// No description provided for @shortcutOrganize.
  ///
  /// In en, this message translates to:
  /// **'Organize with AI'**
  String get shortcutOrganize;

  /// No description provided for @shortcutToggleFavorite.
  ///
  /// In en, this message translates to:
  /// **'Pin or unpin the current folder'**
  String get shortcutToggleFavorite;

  /// No description provided for @shortcutHistory.
  ///
  /// In en, this message translates to:
  /// **'Operation history'**
  String get shortcutHistory;

  /// No description provided for @shortcutSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get shortcutSettings;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'AI-driven media organizer for Jellyfin.'**
  String get aboutTagline;

  /// No description provided for @aboutJellyfinNaming.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin naming guide'**
  String get aboutJellyfinNaming;

  /// No description provided for @aboutGpuHint.
  ///
  /// In en, this message translates to:
  /// **'The GPU Windows hands this app. Change it under Settings → System → Display → Graphics, then restart the app.'**
  String get aboutGpuHint;

  /// No description provided for @langHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switching also affects the AI\'s output language'**
  String get langHeaderSubtitle;

  /// No description provided for @langCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get langCurrent;

  /// No description provided for @langImportArb.
  ///
  /// In en, this message translates to:
  /// **'Import translation file (.arb)'**
  String get langImportArb;

  /// No description provided for @langImportSoon.
  ///
  /// In en, this message translates to:
  /// **'Custom translation import is coming soon.'**
  String get langImportSoon;

  /// No description provided for @langPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Live preview · main UI snippet'**
  String get langPreviewTitle;

  /// No description provided for @langPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Switching the language also translates AI prompts; NFO metadata in organized results follows the same locale.'**
  String get langPreviewHint;

  /// No description provided for @langLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get langLearnMore;

  /// No description provided for @previewOrganizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use AI to detect and move into Jellyfin structure'**
  String get previewOrganizeSubtitle;

  /// No description provided for @previewConfidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get previewConfidenceLabel;

  /// No description provided for @previewConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get previewConfidenceHigh;

  /// No description provided for @previewTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get previewTargetLabel;

  /// No description provided for @previewTargetValue.
  ///
  /// In en, this message translates to:
  /// **'Movies/Dune: Part Two (2024)/'**
  String get previewTargetValue;

  /// No description provided for @onboardingStepCounter.
  ///
  /// In en, this message translates to:
  /// **'Step {current} / {total}'**
  String onboardingStepCounter(Object current, Object total);

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Jellyfin Media Management Tool'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Let AI sweep through messy download folders, rename and sort files, and produce a Jellyfin-conform library structure.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip tour'**
  String get onboardingSkip;

  /// No description provided for @onboardingStart.
  ///
  /// In en, this message translates to:
  /// **'Get started →'**
  String get onboardingStart;

  /// No description provided for @onboardingStep1Eyebrow.
  ///
  /// In en, this message translates to:
  /// **'Step 1'**
  String get onboardingStep1Eyebrow;

  /// No description provided for @onboardingStep2Eyebrow.
  ///
  /// In en, this message translates to:
  /// **'Step 2'**
  String get onboardingStep2Eyebrow;

  /// No description provided for @onboardingRootTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your library root'**
  String get onboardingRootTitle;

  /// No description provided for @onboardingRootBody.
  ///
  /// In en, this message translates to:
  /// **'Point to the path Jellyfin already scans — organized files will land here.'**
  String get onboardingRootBody;

  /// No description provided for @onboardingDropFolder.
  ///
  /// In en, this message translates to:
  /// **'Drop a folder here'**
  String get onboardingDropFolder;

  /// No description provided for @onboardingOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get onboardingOr;

  /// No description provided for @onboardingPickFolder.
  ///
  /// In en, this message translates to:
  /// **'Pick a folder…'**
  String get onboardingPickFolder;

  /// No description provided for @onboardingRootHint.
  ///
  /// In en, this message translates to:
  /// **'Suggested: /Volumes/Media · ~/Movies'**
  String get onboardingRootHint;

  /// No description provided for @onboardingSkipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get onboardingSkipForNow;

  /// No description provided for @onboardingAiTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect your AI service'**
  String get onboardingAiTitle;

  /// No description provided for @onboardingAiBody.
  ///
  /// In en, this message translates to:
  /// **'Both major protocols are supported. You can also add one later in Settings.'**
  String get onboardingAiBody;

  /// No description provided for @onboardingProviderOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible endpoint'**
  String get onboardingProviderOpenAi;

  /// No description provided for @onboardingConfigureLater.
  ///
  /// In en, this message translates to:
  /// **'Configure later'**
  String get onboardingConfigureLater;

  /// No description provided for @onboardingEnterWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Enter workspace →'**
  String get onboardingEnterWorkspace;

  /// No description provided for @aiHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a title hint (optional)'**
  String get aiHintTitle;

  /// No description provided for @aiHintSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell the AI which movie or series this is — useful when filenames are mangled. Leave blank to let the AI infer it.'**
  String get aiHintSubtitle;

  /// No description provided for @aiHintLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get aiHintLabel;

  /// No description provided for @aiHintPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dune, Stranger Things (folder: {folder})'**
  String aiHintPlaceholder(Object folder);

  /// No description provided for @aiHintAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get aiHintAnalyze;

  /// No description provided for @aiHintSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get aiHintSkip;

  /// No description provided for @aiHintKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Media type'**
  String get aiHintKindLabel;

  /// No description provided for @aiHintKindAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get aiHintKindAuto;

  /// No description provided for @aiHintKindMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get aiHintKindMovie;

  /// No description provided for @aiHintKindSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get aiHintKindSeries;

  /// No description provided for @aiHintLabelMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie title'**
  String get aiHintLabelMovie;

  /// No description provided for @aiHintLabelSeries.
  ///
  /// In en, this message translates to:
  /// **'Series title'**
  String get aiHintLabelSeries;

  /// No description provided for @tasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTitle;

  /// No description provided for @tasksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get tasksEmpty;

  /// No description provided for @tasksEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'AI analyze and organize tasks will show up here'**
  String get tasksEmptyHint;

  /// No description provided for @tasksClearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get tasksClearFinished;

  /// No description provided for @tasksAnalyzeLabel.
  ///
  /// In en, this message translates to:
  /// **'AI analyze · {folder}'**
  String tasksAnalyzeLabel(Object folder);

  /// No description provided for @tasksApplyLabel.
  ///
  /// In en, this message translates to:
  /// **'Organize · {folder}'**
  String tasksApplyLabel(Object folder);

  /// No description provided for @tasksAnalyzeRunning.
  ///
  /// In en, this message translates to:
  /// **'AI is analyzing…'**
  String get tasksAnalyzeRunning;

  /// No description provided for @tasksAnalyzeDone.
  ///
  /// In en, this message translates to:
  /// **'Analysis complete'**
  String get tasksAnalyzeDone;

  /// No description provided for @tasksAnalyzeStarted.
  ///
  /// In en, this message translates to:
  /// **'AI analysis started — see Tasks for progress'**
  String get tasksAnalyzeStarted;

  /// No description provided for @tasksApplyStarted.
  ///
  /// In en, this message translates to:
  /// **'Organize task started — see Tasks for progress'**
  String get tasksApplyStarted;

  /// No description provided for @tasksRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get tasksRunning;

  /// No description provided for @tasksDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tasksDone;

  /// No description provided for @tasksFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get tasksFailed;

  /// No description provided for @tasksViewDetail.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get tasksViewDetail;

  /// No description provided for @tasksDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get tasksDismiss;

  /// No description provided for @tasksScrapeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scrape · {target}'**
  String tasksScrapeLabel(Object target);

  /// No description provided for @tasksScrapeCommitLabel.
  ///
  /// In en, this message translates to:
  /// **'Write metadata · {target}'**
  String tasksScrapeCommitLabel(Object target);

  /// No description provided for @menuScrapeMetadata.
  ///
  /// In en, this message translates to:
  /// **'Scrape metadata'**
  String get menuScrapeMetadata;

  /// No description provided for @menuRescrapeFolder.
  ///
  /// In en, this message translates to:
  /// **'Refresh metadata in folder'**
  String get menuRescrapeFolder;

  /// No description provided for @batchScrapeTitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh metadata'**
  String get batchScrapeTitle;

  /// No description provided for @batchScrapeFound.
  ///
  /// In en, this message translates to:
  /// **'{count} titles record where they were scraped from.'**
  String batchScrapeFound(Object count);

  /// No description provided for @batchScrapeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to refresh here. Only NFOs this app wrote record their source page, so titles scraped elsewhere have no URL to go back to.'**
  String get batchScrapeEmpty;

  /// No description provided for @batchScrapePolicy.
  ///
  /// In en, this message translates to:
  /// **'Each title is refreshed with the safe defaults: blanks are filled, existing values are kept, and lists are merged. There is no per-title review — use Scrape metadata on a single title for that.'**
  String get batchScrapePolicy;

  /// No description provided for @batchScrapeArtwork.
  ///
  /// In en, this message translates to:
  /// **'Re-download artwork too'**
  String get batchScrapeArtwork;

  /// No description provided for @batchScrapeArtworkHint.
  ///
  /// In en, this message translates to:
  /// **'Off by default: the images were downloaded on the first scrape.'**
  String get batchScrapeArtworkHint;

  /// No description provided for @batchScrapeStart.
  ///
  /// In en, this message translates to:
  /// **'Refresh {count} titles'**
  String batchScrapeStart(Object count);

  /// No description provided for @batchScrapeStarted.
  ///
  /// In en, this message translates to:
  /// **'Refreshing metadata — see Tasks for progress'**
  String get batchScrapeStarted;

  /// No description provided for @batchScrapeDone.
  ///
  /// In en, this message translates to:
  /// **'Refreshed {count} titles'**
  String batchScrapeDone(Object count);

  /// No description provided for @batchScrapePartial.
  ///
  /// In en, this message translates to:
  /// **'Refreshed {count} titles · {failed} failed'**
  String batchScrapePartial(Object count, Object failed);

  /// No description provided for @shortcutScrape.
  ///
  /// In en, this message translates to:
  /// **'Scrape metadata for the focused item'**
  String get shortcutScrape;

  /// No description provided for @scrapeUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a full URL, including http:// or https://'**
  String get scrapeUrlInvalid;

  /// No description provided for @scrapeDetectedCode.
  ///
  /// In en, this message translates to:
  /// **'Detected code: {code}'**
  String scrapeDetectedCode(Object code);

  /// No description provided for @scrapePasteHtml.
  ///
  /// In en, this message translates to:
  /// **'Paste the page HTML instead'**
  String get scrapePasteHtml;

  /// No description provided for @scrapePasteHtmlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the page source here'**
  String get scrapePasteHtmlHint;

  /// No description provided for @scrapeNoFolder.
  ///
  /// In en, this message translates to:
  /// **'Open a folder first'**
  String get scrapeNoFolder;

  /// No description provided for @scrapeNoteSiteWideIgnored.
  ///
  /// In en, this message translates to:
  /// **'This site serves the same OpenGraph block on every page, so it was ignored.'**
  String get scrapeNoteSiteWideIgnored;

  /// No description provided for @scrapeNoteNoRecipe.
  ///
  /// In en, this message translates to:
  /// **'No recipe matched this site — only the page\'s own structured data was read.'**
  String get scrapeNoteNoRecipe;

  /// No description provided for @scrapeNoteDegradedEncoding.
  ///
  /// In en, this message translates to:
  /// **'The page\'s character encoding could not be determined; some text may be garbled.'**
  String get scrapeNoteDegradedEncoding;

  /// No description provided for @scrapeNoteRecipeStale.
  ///
  /// In en, this message translates to:
  /// **'The recipe matched but extracted nothing — the site has probably changed.'**
  String get scrapeNoteRecipeStale;

  /// No description provided for @scrapeNoteRecipeLearned.
  ///
  /// In en, this message translates to:
  /// **'No recipe existed for this site, so the AI wrote one. Check the highlighted values before saving it — a wrong selector can look perfectly healthy while quietly truncating text.'**
  String get scrapeNoteRecipeLearned;

  /// No description provided for @scrapeNoteRecipeLearningFailed.
  ///
  /// In en, this message translates to:
  /// **'The AI could not work out how to read this page. Paste the page HTML to try again.'**
  String get scrapeNoteRecipeLearningFailed;

  /// No description provided for @scrapeNoteRedirectedAway.
  ///
  /// In en, this message translates to:
  /// **'The site redirected us away from that URL — you probably need to pass its age gate or sign in. What is shown below describes the page we landed on, not the title.'**
  String get scrapeNoteRedirectedAway;

  /// No description provided for @scrapeSaveRecipe.
  ///
  /// In en, this message translates to:
  /// **'Remember this recipe for {domain}'**
  String scrapeSaveRecipe(Object domain);

  /// No description provided for @scrapeRecipeSaved.
  ///
  /// In en, this message translates to:
  /// **'Recipe saved for {domain}'**
  String scrapeRecipeSaved(Object domain);

  /// No description provided for @scrapePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review metadata'**
  String get scrapePreviewTitle;

  /// No description provided for @scrapePreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} fields · {images} images'**
  String scrapePreviewSubtitle(Object count, Object images);

  /// No description provided for @scrapeSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get scrapeSource;

  /// No description provided for @scrapeRecipeName.
  ///
  /// In en, this message translates to:
  /// **'Recipe'**
  String get scrapeRecipeName;

  /// No description provided for @scrapeColumnField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get scrapeColumnField;

  /// No description provided for @scrapeColumnExisting.
  ///
  /// In en, this message translates to:
  /// **'Local NFO'**
  String get scrapeColumnExisting;

  /// No description provided for @scrapeColumnScraped.
  ///
  /// In en, this message translates to:
  /// **'Scraped'**
  String get scrapeColumnScraped;

  /// No description provided for @scrapeColumnDecision.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get scrapeColumnDecision;

  /// No description provided for @scrapeDecisionKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get scrapeDecisionKeep;

  /// No description provided for @scrapeDecisionReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get scrapeDecisionReplace;

  /// No description provided for @scrapeDecisionMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get scrapeDecisionMerge;

  /// No description provided for @scrapePresetFillEmpty.
  ///
  /// In en, this message translates to:
  /// **'Fill blanks only'**
  String get scrapePresetFillEmpty;

  /// No description provided for @scrapePresetReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get scrapePresetReplaceAll;

  /// No description provided for @scrapePresetKeepAll.
  ///
  /// In en, this message translates to:
  /// **'Keep all'**
  String get scrapePresetKeepAll;

  /// No description provided for @scrapeOriginStructured.
  ///
  /// In en, this message translates to:
  /// **'Page data'**
  String get scrapeOriginStructured;

  /// No description provided for @scrapeOriginRecipe.
  ///
  /// In en, this message translates to:
  /// **'Recipe'**
  String get scrapeOriginRecipe;

  /// No description provided for @scrapeOriginLlm.
  ///
  /// In en, this message translates to:
  /// **'AI guess'**
  String get scrapeOriginLlm;

  /// No description provided for @scrapeOriginExisting.
  ///
  /// In en, this message translates to:
  /// **'Existing NFO'**
  String get scrapeOriginExisting;

  /// No description provided for @scrapeOriginManual.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get scrapeOriginManual;

  /// No description provided for @scrapeOriginDerived.
  ///
  /// In en, this message translates to:
  /// **'Derived'**
  String get scrapeOriginDerived;

  /// No description provided for @scrapeOriginMerged.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get scrapeOriginMerged;

  /// No description provided for @scrapeNoChanges.
  ///
  /// In en, this message translates to:
  /// **'Nothing to change — the NFO on disk already says all of this.'**
  String get scrapeNoChanges;

  /// No description provided for @scrapeWriteBackup.
  ///
  /// In en, this message translates to:
  /// **'Record undo information (backs up any NFO this replaces)'**
  String get scrapeWriteBackup;

  /// No description provided for @scrapeTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Target folder'**
  String get scrapeTargetFolder;

  /// No description provided for @scrapeNfoFileName.
  ///
  /// In en, this message translates to:
  /// **'NFO file name'**
  String get scrapeNfoFileName;

  /// No description provided for @scrapeEditValue.
  ///
  /// In en, this message translates to:
  /// **'Edit {field}'**
  String scrapeEditValue(Object field);

  /// No description provided for @scrapeImages.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get scrapeImages;

  /// No description provided for @scrapeImagePoster.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get scrapeImagePoster;

  /// No description provided for @scrapeImageFanart.
  ///
  /// In en, this message translates to:
  /// **'Backdrop'**
  String get scrapeImageFanart;

  /// No description provided for @scrapeImageExtra.
  ///
  /// In en, this message translates to:
  /// **'Still {index}'**
  String scrapeImageExtra(Object index);

  /// No description provided for @scrapeImageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} selected'**
  String scrapeImageCount(Object count, Object total);

  /// No description provided for @scrapeImageNone.
  ///
  /// In en, this message translates to:
  /// **'This page offered no artwork.'**
  String get scrapeImageNone;

  /// No description provided for @scrapeCommitStarted.
  ///
  /// In en, this message translates to:
  /// **'Writing metadata — see Tasks for progress'**
  String get scrapeCommitStarted;

  /// No description provided for @scrapeWriteSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Wrote {count} files'**
  String scrapeWriteSucceeded(Object count);

  /// No description provided for @scrapeWritePartial.
  ///
  /// In en, this message translates to:
  /// **'Wrote {count} files · {failed} failed'**
  String scrapeWritePartial(Object count, Object failed);

  /// No description provided for @scrapeWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Nothing was written: {error}'**
  String scrapeWriteFailed(Object error);

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldOriginalTitle.
  ///
  /// In en, this message translates to:
  /// **'Original title'**
  String get fieldOriginalTitle;

  /// No description provided for @fieldSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort title'**
  String get fieldSortTitle;

  /// No description provided for @fieldCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get fieldCode;

  /// No description provided for @fieldPlot.
  ///
  /// In en, this message translates to:
  /// **'Synopsis'**
  String get fieldPlot;

  /// No description provided for @fieldOutline.
  ///
  /// In en, this message translates to:
  /// **'Blurb'**
  String get fieldOutline;

  /// No description provided for @fieldTagline.
  ///
  /// In en, this message translates to:
  /// **'Tagline'**
  String get fieldTagline;

  /// No description provided for @fieldPremiered.
  ///
  /// In en, this message translates to:
  /// **'Release date'**
  String get fieldPremiered;

  /// No description provided for @fieldRuntime.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get fieldRuntime;

  /// No description provided for @fieldStudio.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get fieldStudio;

  /// No description provided for @fieldSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get fieldSeries;

  /// No description provided for @fieldDirector.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get fieldDirector;

  /// No description provided for @fieldRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get fieldRating;

  /// No description provided for @fieldGenres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get fieldGenres;

  /// No description provided for @fieldTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get fieldTags;

  /// No description provided for @fieldActors.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get fieldActors;

  /// No description provided for @fieldPoster.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get fieldPoster;

  /// No description provided for @fieldFanart.
  ///
  /// In en, this message translates to:
  /// **'Backdrop'**
  String get fieldFanart;

  /// No description provided for @fieldExtraFanart.
  ///
  /// In en, this message translates to:
  /// **'Stills'**
  String get fieldExtraFanart;

  /// No description provided for @secScraping.
  ///
  /// In en, this message translates to:
  /// **'Scraping'**
  String get secScraping;

  /// No description provided for @settingsScrapeCookies.
  ///
  /// In en, this message translates to:
  /// **'Cookies'**
  String get settingsScrapeCookies;

  /// No description provided for @settingsScrapeCookieWarning.
  ///
  /// In en, this message translates to:
  /// **'A cookies.txt exported from your browser can contain a session identifier equivalent to being signed in. Cookies are held in memory only and are gone when the app closes; they also stop working once you sign out in that browser.'**
  String get settingsScrapeCookieWarning;

  /// No description provided for @settingsScrapeImportCookies.
  ///
  /// In en, this message translates to:
  /// **'Import cookies.txt'**
  String get settingsScrapeImportCookies;

  /// No description provided for @settingsScrapeClearCookies.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get settingsScrapeClearCookies;

  /// No description provided for @settingsScrapeClearDomain.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsScrapeClearDomain;

  /// No description provided for @settingsScrapeCookieEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cookies imported.'**
  String get settingsScrapeCookieEmpty;

  /// No description provided for @settingsScrapeCookieCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cookies'**
  String settingsScrapeCookieCount(Object count);

  /// No description provided for @settingsScrapeCookieImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} cookies'**
  String settingsScrapeCookieImported(Object count);

  /// No description provided for @settingsScrapeCookieImportFailed.
  ///
  /// In en, this message translates to:
  /// **'That file contained no usable cookies'**
  String get settingsScrapeCookieImportFailed;

  /// No description provided for @settingsScrapeRecipes.
  ///
  /// In en, this message translates to:
  /// **'Site recipes'**
  String get settingsScrapeRecipes;

  /// No description provided for @settingsScrapeRecipeBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get settingsScrapeRecipeBuiltin;

  /// No description provided for @settingsScrapeRecipeLearned.
  ///
  /// In en, this message translates to:
  /// **'Learned'**
  String get settingsScrapeRecipeLearned;

  /// No description provided for @settingsScrapeRecipeUser.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get settingsScrapeRecipeUser;

  /// No description provided for @settingsScrapeRecipeRetired.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get settingsScrapeRecipeRetired;

  /// No description provided for @settingsScrapeRecipeDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete recipe'**
  String get settingsScrapeRecipeDelete;

  /// No description provided for @settingsScrapeRecipeHealth.
  ///
  /// In en, this message translates to:
  /// **'{count} ok · {failed} failed'**
  String settingsScrapeRecipeHealth(Object count, Object failed);

  /// No description provided for @settingsScrapeRecipeAnyPath.
  ///
  /// In en, this message translates to:
  /// **'any page'**
  String get settingsScrapeRecipeAnyPath;

  /// No description provided for @scrapeNoteLlmExtracted.
  ///
  /// In en, this message translates to:
  /// **'These values were read off the page by the model, not matched by a selector — nothing verified them against the document. Check anything that matters before writing.'**
  String get scrapeNoteLlmExtracted;

  /// No description provided for @scrapeNoteLlmExtractionFailed.
  ///
  /// In en, this message translates to:
  /// **'The model could not read usable metadata off this page.'**
  String get scrapeNoteLlmExtractionFailed;

  /// No description provided for @scrapeNoteLlmExtractionTruncated.
  ///
  /// In en, this message translates to:
  /// **'The model hit its output limit before it finished, so some fields may be missing. Raise the maximum output in the AI service settings.'**
  String get scrapeNoteLlmExtractionTruncated;

  /// No description provided for @scrapeAskLlm.
  ///
  /// In en, this message translates to:
  /// **'Ask the LLM directly'**
  String get scrapeAskLlm;

  /// No description provided for @scrapeAskLlmHint.
  ///
  /// In en, this message translates to:
  /// **'Reads the page you already fetched and reports the fields itself. Costs a request, and the values are the model’s rather than the page’s.'**
  String get scrapeAskLlmHint;

  /// No description provided for @scrapeCustomPrompt.
  ///
  /// In en, this message translates to:
  /// **'Extra instructions for the model (optional)'**
  String get scrapeCustomPrompt;

  /// No description provided for @scrapeCustomPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. “use the sidebar credits as tags”'**
  String get scrapeCustomPromptHint;

  /// No description provided for @scrapeBackend.
  ///
  /// In en, this message translates to:
  /// **'AI backend'**
  String get scrapeBackend;

  /// No description provided for @scrapeBackendNone.
  ///
  /// In en, this message translates to:
  /// **'No AI profile configured'**
  String get scrapeBackendNone;

  /// No description provided for @scrapeCookiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Cookies for this site (optional)'**
  String get scrapeCookiesLabel;

  /// No description provided for @scrapeCookiesHint.
  ///
  /// In en, this message translates to:
  /// **'name=value; name2=value2 — held in memory for this run only'**
  String get scrapeCookiesHint;

  /// No description provided for @scrapeNfoTarget.
  ///
  /// In en, this message translates to:
  /// **'Compare against'**
  String get scrapeNfoTarget;

  /// No description provided for @scrapeNfoBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get scrapeNfoBrowse;

  /// No description provided for @scrapeKindMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get scrapeKindMovie;

  /// No description provided for @scrapeKindTvShow.
  ///
  /// In en, this message translates to:
  /// **'TV show'**
  String get scrapeKindTvShow;

  /// No description provided for @scrapePanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Scrape metadata'**
  String get scrapePanelTitle;

  /// No description provided for @scrapeProcess.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get scrapeProcess;

  /// No description provided for @scrapeWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get scrapeWorking;

  /// No description provided for @scrapeBackToSetup.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get scrapeBackToSetup;

  /// No description provided for @scrapeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get scrapeAdvanced;

  /// No description provided for @scrapeImageLoading.
  ///
  /// In en, this message translates to:
  /// **'loading {count}…'**
  String scrapeImageLoading(Object count);

  /// No description provided for @scrapeImageSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get scrapeImageSelectAll;

  /// No description provided for @scrapeImageSelectNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get scrapeImageSelectNone;

  /// No description provided for @scrapeSaveImages.
  ///
  /// In en, this message translates to:
  /// **'Save {count} images'**
  String scrapeSaveImages(Object count);

  /// No description provided for @scrapeSaveImagesHint.
  ///
  /// In en, this message translates to:
  /// **'Writes the ticked images into the media folder now. Does not touch the NFO.'**
  String get scrapeSaveImagesHint;

  /// No description provided for @scrapeSaveImagesDone.
  ///
  /// In en, this message translates to:
  /// **'Saved {count} images to {folder}'**
  String scrapeSaveImagesDone(Object count, Object folder);

  /// No description provided for @scrapeSaveImagesPartial.
  ///
  /// In en, this message translates to:
  /// **'Saved {count} images · {failed} failed'**
  String scrapeSaveImagesPartial(Object count, Object failed);

  /// No description provided for @scrapeImageRole.
  ///
  /// In en, this message translates to:
  /// **'Mark as Jellyfin artwork'**
  String get scrapeImageRole;

  /// No description provided for @scrapeRoleOriginal.
  ///
  /// In en, this message translates to:
  /// **'Keep original name'**
  String get scrapeRoleOriginal;

  /// No description provided for @scrapeRolePoster.
  ///
  /// In en, this message translates to:
  /// **'Poster (folder)'**
  String get scrapeRolePoster;

  /// No description provided for @scrapeRoleFanart.
  ///
  /// In en, this message translates to:
  /// **'Backdrop'**
  String get scrapeRoleFanart;

  /// No description provided for @scrapeRoleExtraFanart.
  ///
  /// In en, this message translates to:
  /// **'Extra backdrop'**
  String get scrapeRoleExtraFanart;

  /// No description provided for @scrapeRoleThumb.
  ///
  /// In en, this message translates to:
  /// **'Thumb (landscape)'**
  String get scrapeRoleThumb;

  /// No description provided for @scrapeRoleMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get scrapeRoleMenu;

  /// No description provided for @scrapeRoleBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get scrapeRoleBanner;

  /// No description provided for @scrapeRoleLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get scrapeRoleLogo;

  /// No description provided for @scrapeRoleClearArt.
  ///
  /// In en, this message translates to:
  /// **'Clear art'**
  String get scrapeRoleClearArt;

  /// No description provided for @scrapeRoleDisc.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get scrapeRoleDisc;

  /// No description provided for @colResetWidths.
  ///
  /// In en, this message translates to:
  /// **'Drag to resize · double-click to reset'**
  String get colResetWidths;

  /// No description provided for @scrapeSourceUrl.
  ///
  /// In en, this message translates to:
  /// **'Product page URL'**
  String get scrapeSourceUrl;

  /// No description provided for @scrapeSourceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search sites by filename'**
  String get scrapeSourceSearch;

  /// No description provided for @scrapeSearchKeyword.
  ///
  /// In en, this message translates to:
  /// **'Search keyword'**
  String get scrapeSearchKeyword;

  /// No description provided for @scrapeSearchNoSites.
  ///
  /// In en, this message translates to:
  /// **'No search sites configured — add some in Settings.'**
  String get scrapeSearchNoSites;

  /// No description provided for @scrapeNfoAutoMatched.
  ///
  /// In en, this message translates to:
  /// **'Auto-matched {name} in the same folder'**
  String scrapeNfoAutoMatched(Object name);

  /// No description provided for @scrapeStepFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch page'**
  String get scrapeStepFetch;

  /// No description provided for @scrapeStepExtract.
  ///
  /// In en, this message translates to:
  /// **'Extract fields'**
  String get scrapeStepExtract;

  /// No description provided for @scrapeStepCompare.
  ///
  /// In en, this message translates to:
  /// **'Build field comparison'**
  String get scrapeStepCompare;

  /// No description provided for @scrapeElapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed {time}'**
  String scrapeElapsed(Object time);

  /// No description provided for @scrapeWillWrite.
  ///
  /// In en, this message translates to:
  /// **'{count} will be written'**
  String scrapeWillWrite(Object count);

  /// No description provided for @scrapeConflictLegend.
  ///
  /// In en, this message translates to:
  /// **'Local value exists and differs from the scrape'**
  String get scrapeConflictLegend;

  /// No description provided for @scrapeImageRoleHint.
  ///
  /// In en, this message translates to:
  /// **'Right-click to mark as Jellyfin artwork · others keep their original file name'**
  String get scrapeImageRoleHint;

  /// No description provided for @scrapeImageUnmarked.
  ///
  /// In en, this message translates to:
  /// **'Unmarked'**
  String get scrapeImageUnmarked;

  /// No description provided for @scrapeImageDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get scrapeImageDeselect;

  /// No description provided for @scrapeWriteCounts.
  ///
  /// In en, this message translates to:
  /// **'Write {fields} fields + {images} images'**
  String scrapeWriteCounts(Object fields, Object images);

  /// No description provided for @previewDryRun.
  ///
  /// In en, this message translates to:
  /// **'Preview · no files are moved yet'**
  String get previewDryRun;

  /// No description provided for @previewFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter'**
  String get previewFilterEmpty;

  /// No description provided for @previewAdjustRules.
  ///
  /// In en, this message translates to:
  /// **'Adjust rules'**
  String get previewAdjustRules;

  /// No description provided for @ruleEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Naming rule · Movies'**
  String get ruleEditorTitle;

  /// No description provided for @ruleEditorRecommended.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin preset'**
  String get ruleEditorRecommended;

  /// No description provided for @ruleEditorFolderTemplate.
  ///
  /// In en, this message translates to:
  /// **'Folder path template'**
  String get ruleEditorFolderTemplate;

  /// No description provided for @ruleEditorFileTemplate.
  ///
  /// In en, this message translates to:
  /// **'File name template'**
  String get ruleEditorFileTemplate;

  /// No description provided for @ruleEditorVariables.
  ///
  /// In en, this message translates to:
  /// **'Available variables'**
  String get ruleEditorVariables;

  /// No description provided for @ruleEditorPreview.
  ///
  /// In en, this message translates to:
  /// **'Live preview'**
  String get ruleEditorPreview;

  /// No description provided for @ruleEditorInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get ruleEditorInput;

  /// No description provided for @ruleEditorOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get ruleEditorOutput;

  /// No description provided for @ruleEditorOutputAi.
  ///
  /// In en, this message translates to:
  /// **'Output · AI inferred'**
  String get ruleEditorOutputAi;

  /// No description provided for @ruleEditorReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get ruleEditorReset;

  /// No description provided for @ruleEditorComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Editing rules is not wired up yet — this preview shows the built-in Jellyfin convention.'**
  String get ruleEditorComingSoon;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowClose;

  /// No description provided for @togglePanel.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the side panel'**
  String get togglePanel;

  /// No description provided for @searchHintShort.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get searchHintShort;

  /// No description provided for @statusTotalSize.
  ///
  /// In en, this message translates to:
  /// **'{size} total'**
  String statusTotalSize(String size);

  /// No description provided for @planReady.
  ///
  /// In en, this message translates to:
  /// **'Plan ready'**
  String get planReady;

  /// No description provided for @dropFoldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop folders here to start'**
  String get dropFoldersTitle;

  /// No description provided for @dropFoldersHint.
  ///
  /// In en, this message translates to:
  /// **'Drag one or more folders into the window · video, subtitles, posters and metadata are scanned together'**
  String get dropFoldersHint;

  /// No description provided for @orSeparator.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orSeparator;

  /// No description provided for @connectNas.
  ///
  /// In en, this message translates to:
  /// **'Connect NAS'**
  String get connectNas;

  /// No description provided for @historyAllRecords.
  ///
  /// In en, this message translates to:
  /// **'All records'**
  String get historyAllRecords;

  /// No description provided for @historyIrreversible.
  ///
  /// In en, this message translates to:
  /// **'Cannot be undone'**
  String get historyIrreversible;

  /// No description provided for @historyToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyToday;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @pathsLibraryRoots.
  ///
  /// In en, this message translates to:
  /// **'Library roots'**
  String get pathsLibraryRoots;

  /// No description provided for @pathsRootMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get pathsRootMovies;

  /// No description provided for @pathsRootShows.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get pathsRootShows;

  /// No description provided for @pathsRootExample.
  ///
  /// In en, this message translates to:
  /// **'/Volumes/Media/Movies'**
  String get pathsRootExample;

  /// No description provided for @pathsMounted.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get pathsMounted;

  /// No description provided for @pathsUnmounted.
  ///
  /// In en, this message translates to:
  /// **'Not mounted'**
  String get pathsUnmounted;

  /// No description provided for @pathsChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get pathsChange;

  /// No description provided for @pathsAddRoot.
  ///
  /// In en, this message translates to:
  /// **'Add root'**
  String get pathsAddRoot;

  /// No description provided for @pathsRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get pathsRescan;

  /// No description provided for @pathsRootsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'This app organizes one folder at a time. Multiple roots, mount state and rescanning are not implemented yet.'**
  String get pathsRootsPlaceholder;

  /// No description provided for @pathsDefaults.
  ///
  /// In en, this message translates to:
  /// **'Default locations'**
  String get pathsDefaults;

  /// No description provided for @pathsOrganizeOutput.
  ///
  /// In en, this message translates to:
  /// **'Organize output'**
  String get pathsOrganizeOutput;

  /// No description provided for @pathsOrganizeOutputValue.
  ///
  /// In en, this message translates to:
  /// **'Follows the source folder'**
  String get pathsOrganizeOutputValue;

  /// No description provided for @pathsChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get pathsChoose;

  /// No description provided for @pathsTempDir.
  ///
  /// In en, this message translates to:
  /// **'Temporary & downloads'**
  String get pathsTempDir;

  /// No description provided for @pathsTempDirValue.
  ///
  /// In en, this message translates to:
  /// **'System temporary folder'**
  String get pathsTempDirValue;

  /// No description provided for @pathsNfoOutput.
  ///
  /// In en, this message translates to:
  /// **'NFO & image output'**
  String get pathsNfoOutput;

  /// No description provided for @pathsNfoOutputValue.
  ///
  /// In en, this message translates to:
  /// **'Beside the media file'**
  String get pathsNfoOutputValue;

  /// No description provided for @pathsDefaultsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Organized files always land beside their source; a separate output or temporary folder is not implemented yet.'**
  String get pathsDefaultsPlaceholder;

  /// No description provided for @pathsFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorite paths'**
  String get pathsFavorites;

  /// No description provided for @pathsFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Reordering by drag is not implemented yet. This list is the sidebar\'s Favorites group.'**
  String get pathsFavoritesHint;

  /// No description provided for @pathsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get pathsRecent;

  /// No description provided for @pathsClearRecent.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get pathsClearRecent;

  /// No description provided for @pathsRecentHint.
  ///
  /// In en, this message translates to:
  /// **'The last {count} folders you opened. The star at the end of a row adds one to Favorites.'**
  String pathsRecentHint(Object count);

  /// No description provided for @pathsAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get pathsAddFavorite;

  /// No description provided for @privacyLocations.
  ///
  /// In en, this message translates to:
  /// **'Config & data'**
  String get privacyLocations;

  /// No description provided for @privacyConfigFolder.
  ///
  /// In en, this message translates to:
  /// **'Config folder'**
  String get privacyConfigFolder;

  /// No description provided for @privacyBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get privacyBrowse;

  /// No description provided for @privacyCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get privacyCopyPath;

  /// No description provided for @privacyCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get privacyCopied;

  /// No description provided for @privacyDataFiles.
  ///
  /// In en, this message translates to:
  /// **'Data files'**
  String get privacyDataFiles;

  /// No description provided for @privacyDataFilesValue.
  ///
  /// In en, this message translates to:
  /// **'config.json · ai_profiles.json · ai_learned.json · sites.json · scrapers.json'**
  String get privacyDataFilesValue;

  /// No description provided for @privacyPrefsBackup.
  ///
  /// In en, this message translates to:
  /// **'Preferences backup'**
  String get privacyPrefsBackup;

  /// No description provided for @privacyPrefsBackupHint.
  ///
  /// In en, this message translates to:
  /// **'Export or restore config.json and the AI profiles'**
  String get privacyPrefsBackupHint;

  /// No description provided for @privacyImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get privacyImport;

  /// No description provided for @privacyExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get privacyExport;

  /// No description provided for @privacyCaches.
  ///
  /// In en, this message translates to:
  /// **'Caches'**
  String get privacyCaches;

  /// No description provided for @privacyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get privacyClear;

  /// No description provided for @privacyClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get privacyClearAll;

  /// No description provided for @privacyTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get privacyTotal;

  /// No description provided for @privacyCacheThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail cache'**
  String get privacyCacheThumbnails;

  /// No description provided for @privacyCacheThumbnailsHint.
  ///
  /// In en, this message translates to:
  /// **'Poster frames rendered for the file table'**
  String get privacyCacheThumbnailsHint;

  /// No description provided for @privacyCacheUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo backups'**
  String get privacyCacheUndo;

  /// No description provided for @privacyCacheUndoHint.
  ///
  /// In en, this message translates to:
  /// **'Real copies of overwritten files, kept {days} days · {count} operations'**
  String privacyCacheUndoHint(Object count, Object days);

  /// No description provided for @privacyCacheAgent.
  ///
  /// In en, this message translates to:
  /// **'Organize memory'**
  String get privacyCacheAgent;

  /// No description provided for @privacyCacheAgentHint.
  ///
  /// In en, this message translates to:
  /// **'Decided groups and corrections you applied'**
  String get privacyCacheAgentHint;

  /// No description provided for @privacyCacheNote.
  ///
  /// In en, this message translates to:
  /// **'Clearing removes local caches only. NFOs and images already written to the library are untouched, and the next run regenerates what it needs. Undo backups have no Clear: deleting them would turn undo records that have not expired into empty promises.'**
  String get privacyCacheNote;

  /// No description provided for @privacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacySection;

  /// No description provided for @privacyTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Send anonymous usage statistics'**
  String get privacyTelemetry;

  /// No description provided for @privacyTelemetryHint.
  ///
  /// In en, this message translates to:
  /// **'No file names or paths'**
  String get privacyTelemetryHint;

  /// No description provided for @privacyCrashReports.
  ///
  /// In en, this message translates to:
  /// **'Crash reports'**
  String get privacyCrashReports;

  /// No description provided for @privacyCrashReportsHint.
  ///
  /// In en, this message translates to:
  /// **'Stack traces and device model only'**
  String get privacyCrashReportsHint;

  /// No description provided for @privacyLogAiBodies.
  ///
  /// In en, this message translates to:
  /// **'Log AI request and reply bodies'**
  String get privacyLogAiBodies;

  /// No description provided for @privacyLogAiBodiesHint.
  ///
  /// In en, this message translates to:
  /// **'Every request actually sent goes to the logs folder, one file per day, kept {days} days. Keys are never written; images and long text are logged by length only.'**
  String privacyLogAiBodiesHint(int days);

  /// No description provided for @privacyClearTempOnExit.
  ///
  /// In en, this message translates to:
  /// **'Empty the temporary folder on exit'**
  String get privacyClearTempOnExit;

  /// No description provided for @privacyNoTelemetry.
  ///
  /// In en, this message translates to:
  /// **'This app collects no telemetry of any kind. The AI request log stays on this computer; the other switches have nothing to turn off yet.'**
  String get privacyNoTelemetry;

  /// No description provided for @privacyCacheApiLog.
  ///
  /// In en, this message translates to:
  /// **'AI request log'**
  String get privacyCacheApiLog;

  /// No description provided for @privacyCacheApiLogHint.
  ///
  /// In en, this message translates to:
  /// **'Written while “Log AI request and reply bodies” is on'**
  String get privacyCacheApiLogHint;

  /// No description provided for @privacyDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get privacyDanger;

  /// No description provided for @privacyReset.
  ///
  /// In en, this message translates to:
  /// **'Reset all data'**
  String get privacyReset;

  /// No description provided for @privacyResetBody.
  ///
  /// In en, this message translates to:
  /// **'Clears AI services, recipes, history and every cache, returning the app to its first-launch state. Media files on disk are not deleted, and NFOs and images already written are kept.'**
  String get privacyResetBody;

  /// No description provided for @privacyResetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset…'**
  String get privacyResetAction;

  /// No description provided for @privacyResetPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Not implemented yet. Until it is, delete the config folder by hand — an irreversible reset should not ship half-built.'**
  String get privacyResetPlaceholder;

  /// No description provided for @shortcutsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search a command or a key…'**
  String get shortcutsSearchHint;

  /// No description provided for @shortcutsRestoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get shortcutsRestoreDefaults;

  /// No description provided for @shortcutsRebindHint.
  ///
  /// In en, this message translates to:
  /// **'Rebinding is not implemented yet — what is listed here is what is actually bound.'**
  String get shortcutsRebindHint;

  /// No description provided for @shortcutsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No command matches'**
  String get shortcutsNoMatch;

  /// No description provided for @shortcutsPlatformNote.
  ///
  /// In en, this message translates to:
  /// **'On Windows and Linux ⌘ is Ctrl, ⌥ is Alt and ⌫ is Delete.'**
  String get shortcutsPlatformNote;

  /// No description provided for @aboutChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get aboutChangelog;

  /// No description provided for @aboutCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheckUpdates;

  /// No description provided for @aboutBuildInfo.
  ///
  /// In en, this message translates to:
  /// **'Build info'**
  String get aboutBuildInfo;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// No description provided for @aboutBuildNumber.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get aboutBuildNumber;

  /// No description provided for @aboutCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get aboutCommit;

  /// No description provided for @aboutCommitTime.
  ///
  /// In en, this message translates to:
  /// **'Commit time'**
  String get aboutCommitTime;

  /// No description provided for @aboutBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get aboutBranch;

  /// No description provided for @aboutRuntime.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get aboutRuntime;

  /// No description provided for @aboutBuildInfoPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Commit and branch are stamped in at package time, which this build does not do yet.'**
  String get aboutBuildInfoPlaceholder;

  /// No description provided for @aboutSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get aboutSystem;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get aboutOpenSource;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get aboutRepository;

  /// No description provided for @aboutIssues.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get aboutIssues;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get aboutCopyright;

  /// No description provided for @aboutCopyrightValue.
  ///
  /// In en, this message translates to:
  /// **'© 2026 contributors'**
  String get aboutCopyrightValue;

  /// No description provided for @aboutThirdParty.
  ///
  /// In en, this message translates to:
  /// **'Third-party licenses'**
  String get aboutThirdParty;

  /// No description provided for @aboutGraphics.
  ///
  /// In en, this message translates to:
  /// **'Graphics adapter'**
  String get aboutGraphics;

  /// No description provided for @aboutGpuRunning.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get aboutGpuRunning;

  /// No description provided for @aboutGpuShared.
  ///
  /// In en, this message translates to:
  /// **'Shared memory'**
  String get aboutGpuShared;

  /// No description provided for @aboutGpuCount.
  ///
  /// In en, this message translates to:
  /// **'{count} GPUs detected'**
  String aboutGpuCount(Object count);

  /// No description provided for @aboutGpuInfoOnly.
  ///
  /// In en, this message translates to:
  /// **'Information only'**
  String get aboutGpuInfoOnly;

  /// No description provided for @aboutGpuIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get aboutGpuIdle;

  /// No description provided for @accentPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentPickerTitle;

  /// No description provided for @accentRestoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore the default blue'**
  String get accentRestoreDefault;

  /// No description provided for @accentRecents.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get accentRecents;

  /// No description provided for @accentRecentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get accentRecentsEmpty;

  /// No description provided for @accentEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Pick a color from the screen'**
  String get accentEyedropper;

  /// No description provided for @accentContrastOk.
  ///
  /// In en, this message translates to:
  /// **'Contrast against the dark and light window bases: {dark}:1 · {light}:1'**
  String accentContrastOk(Object dark, Object light);

  /// No description provided for @accentContrastWeak.
  ///
  /// In en, this message translates to:
  /// **'Contrast {dark}:1 · {light}:1 — below 3:1, so use it as a fill only'**
  String accentContrastWeak(Object dark, Object light);

  /// No description provided for @contextWindowScaleHint.
  ///
  /// In en, this message translates to:
  /// **'tokens · 8k – 1M · step 1k'**
  String get contextWindowScaleHint;

  /// No description provided for @contextWindowFootnote.
  ///
  /// In en, this message translates to:
  /// **'The ticks are evenly spaced segments and each segment is continuous, so the handle can stop on any 1k. Slider and field follow each other; blank means no limit.'**
  String get contextWindowFootnote;

  /// No description provided for @contextWindowOverDetected.
  ///
  /// In en, this message translates to:
  /// **'Above the {limit} the server reported. Still saved.'**
  String contextWindowOverDetected(Object limit);

  /// No description provided for @maxOutputStep.
  ///
  /// In en, this message translates to:
  /// **'step 256'**
  String get maxOutputStep;

  /// No description provided for @maxOutputFootnote.
  ///
  /// In en, this message translates to:
  /// **'Capped at half the context window; anything larger is clamped.'**
  String get maxOutputFootnote;

  /// No description provided for @pathsRootExampleShows.
  ///
  /// In en, this message translates to:
  /// **'/Volumes/Media/Shows'**
  String get pathsRootExampleShows;

  /// No description provided for @historyTitleTransfer.
  ///
  /// In en, this message translates to:
  /// **'Copy / move · {count} items'**
  String historyTitleTransfer(Object count);

  /// No description provided for @tasksCopyLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy · {target}'**
  String tasksCopyLabel(Object target);

  /// No description provided for @tasksMoveLabel.
  ///
  /// In en, this message translates to:
  /// **'Move · {target}'**
  String tasksMoveLabel(Object target);

  /// No description provided for @shortcutCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy the selection'**
  String get shortcutCopy;

  /// No description provided for @shortcutCut.
  ///
  /// In en, this message translates to:
  /// **'Cut the selection'**
  String get shortcutCut;

  /// No description provided for @shortcutPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste into the current folder'**
  String get shortcutPaste;

  /// No description provided for @menuCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuCopy;

  /// No description provided for @menuCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuCut;

  /// No description provided for @menuPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuPaste;

  /// No description provided for @menuPasteIntoFolder.
  ///
  /// In en, this message translates to:
  /// **'Paste into this folder'**
  String get menuPasteIntoFolder;

  /// No description provided for @menuMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get menuMoveTo;

  /// No description provided for @clipboardCopiedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items copied'**
  String clipboardCopiedCount(Object count);

  /// No description provided for @clipboardCutCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items cut'**
  String clipboardCutCount(Object count);

  /// No description provided for @clipboardPasteHere.
  ///
  /// In en, this message translates to:
  /// **'Paste here'**
  String get clipboardPasteHere;

  /// No description provided for @clipboardClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clipboardClear;

  /// No description provided for @transferConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} items already exist in {folder}'**
  String transferConflictTitle(Object count, Object folder);

  /// No description provided for @transferConflictBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing is overwritten. Skip the ones that exist, or keep both and the new copies get a numbered name.'**
  String get transferConflictBody;

  /// No description provided for @transferSkipExisting.
  ///
  /// In en, this message translates to:
  /// **'Skip existing'**
  String get transferSkipExisting;

  /// No description provided for @transferKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get transferKeepBoth;

  /// No description provided for @transferNothingToDo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to paste here'**
  String get transferNothingToDo;

  /// No description provided for @transferRefusedMissing.
  ///
  /// In en, this message translates to:
  /// **'{count} items no longer exist'**
  String transferRefusedMissing(Object count);

  /// No description provided for @transferRefusedIntoItself.
  ///
  /// In en, this message translates to:
  /// **'A folder cannot be pasted into itself'**
  String get transferRefusedIntoItself;

  /// No description provided for @transferRefusedSameFolder.
  ///
  /// In en, this message translates to:
  /// **'{count} items are already in this folder'**
  String transferRefusedSameFolder(Object count);

  /// No description provided for @transferCopiedCount.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} items'**
  String transferCopiedCount(Object count);

  /// No description provided for @transferMovedCount.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} items'**
  String transferMovedCount(Object count);

  /// No description provided for @transferFailedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String transferFailedCount(Object count);

  /// No description provided for @transferStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped after {count} items'**
  String transferStopped(Object count);

  /// No description provided for @transferNoUndo.
  ///
  /// In en, this message translates to:
  /// **'no undo'**
  String get transferNoUndo;

  /// No description provided for @transferDestinationMissing.
  ///
  /// In en, this message translates to:
  /// **'The destination folder is not available'**
  String get transferDestinationMissing;

  /// No description provided for @moveToTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToTitle;

  /// No description provided for @transferRefusedLink.
  ///
  /// In en, this message translates to:
  /// **'{count} items are symbolic links or contain them'**
  String transferRefusedLink(Object count);

  /// No description provided for @transferRefusedUnreadable.
  ///
  /// In en, this message translates to:
  /// **'{count} items could not be read'**
  String transferRefusedUnreadable(Object count);

  /// No description provided for @aiAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'AI access'**
  String get aiAccessTitle;

  /// No description provided for @aiAccessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A channel is one key. A route is a protocol that key can speak. Each model hangs off a channel and picks one route.'**
  String get aiAccessSubtitle;

  /// No description provided for @aiDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get aiDiagnostics;

  /// No description provided for @aiAddChannel.
  ///
  /// In en, this message translates to:
  /// **'Add channel'**
  String get aiAddChannel;

  /// No description provided for @aiMergeHint.
  ///
  /// In en, this message translates to:
  /// **'{names} share one key and host and can become one channel ({routes, plural, =1{1 route} other{{routes} routes}}, {models, plural, =1{1 model} other{{models} models}}).'**
  String aiMergeHint(String names, int routes, int models);

  /// No description provided for @aiMergeAction.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get aiMergeAction;

  /// No description provided for @aiChannelHostLine.
  ///
  /// In en, this message translates to:
  /// **'{host} · platform: {platform}'**
  String aiChannelHostLine(String host, String platform);

  /// No description provided for @aiNoKeyNeeded.
  ///
  /// In en, this message translates to:
  /// **'no key needed'**
  String get aiNoKeyNeeded;

  /// No description provided for @aiNoModels.
  ///
  /// In en, this message translates to:
  /// **'No models yet — open the channel to add one.'**
  String get aiNoModels;

  /// No description provided for @aiToolsUnprobed.
  ///
  /// In en, this message translates to:
  /// **'Tools: not checked'**
  String get aiToolsUnprobed;

  /// No description provided for @aiToolsYes.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get aiToolsYes;

  /// No description provided for @aiToolsNo.
  ///
  /// In en, this message translates to:
  /// **'No tools'**
  String get aiToolsNo;

  /// No description provided for @aiImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get aiImage;

  /// No description provided for @aiVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get aiVideo;

  /// No description provided for @aiEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No channels yet'**
  String get aiEmptyTitle;

  /// No description provided for @aiEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a platform, paste one key, then add the models you want to use.'**
  String get aiEmptyBody;

  /// No description provided for @aiTasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Task assignment'**
  String get aiTasksTitle;

  /// No description provided for @aiTasksHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a model for each task. Tasks that need tool calling leave out models known not to call tools.'**
  String get aiTasksHint;

  /// No description provided for @aiTaskOrganize.
  ///
  /// In en, this message translates to:
  /// **'Organize (tool calling)'**
  String get aiTaskOrganize;

  /// No description provided for @aiTaskScrapeLearn.
  ///
  /// In en, this message translates to:
  /// **'Scrape · learn a recipe (tool calling)'**
  String get aiTaskScrapeLearn;

  /// No description provided for @aiTaskScrapeDirect.
  ///
  /// In en, this message translates to:
  /// **'Scrape · read the page (tool calling)'**
  String get aiTaskScrapeDirect;

  /// No description provided for @aiTaskVision.
  ///
  /// In en, this message translates to:
  /// **'Frame recognition (image input)'**
  String get aiTaskVision;

  /// No description provided for @aiFollowOrganize.
  ///
  /// In en, this message translates to:
  /// **'Follow “Organize”'**
  String get aiFollowOrganize;

  /// No description provided for @aiTaskNoModel.
  ///
  /// In en, this message translates to:
  /// **'No suitable model'**
  String get aiTaskNoModel;

  /// No description provided for @aiVisionNeedsImage.
  ///
  /// In en, this message translates to:
  /// **'Only models allowed image input are listed.'**
  String get aiVisionNeedsImage;

  /// No description provided for @aiSessionUsage.
  ///
  /// In en, this message translates to:
  /// **'Since this launch'**
  String get aiSessionUsage;

  /// No description provided for @aiPlatformRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay (New API style)'**
  String get aiPlatformRelay;

  /// No description provided for @aiPlatformCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get aiPlatformCustom;

  /// No description provided for @aiPlatformDashScope.
  ///
  /// In en, this message translates to:
  /// **'Alibaba Cloud Model Studio'**
  String get aiPlatformDashScope;

  /// No description provided for @aiPlatformZhipu.
  ///
  /// In en, this message translates to:
  /// **'Zhipu BigModel'**
  String get aiPlatformZhipu;

  /// No description provided for @aiPlatformVolcengine.
  ///
  /// In en, this message translates to:
  /// **'Volcengine Ark'**
  String get aiPlatformVolcengine;

  /// No description provided for @aiAddChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Pick the platform first. Protocols, address and auth come from its profile; you only paste one key.'**
  String get aiAddChannelHint;

  /// No description provided for @aiPlatformGroupVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendors'**
  String get aiPlatformGroupVendor;

  /// No description provided for @aiPlatformGroupRelay.
  ///
  /// In en, this message translates to:
  /// **'Aggregators and relays'**
  String get aiPlatformGroupRelay;

  /// No description provided for @aiPlatformGroupLocal.
  ///
  /// In en, this message translates to:
  /// **'Local servers'**
  String get aiPlatformGroupLocal;

  /// No description provided for @aiPlatformCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Custom — protocol-standard fields only, no vendor extensions'**
  String get aiPlatformCustomHint;

  /// No description provided for @aiWillCreate.
  ///
  /// In en, this message translates to:
  /// **'{platform} · will create'**
  String aiWillCreate(String platform);

  /// No description provided for @aiPrimaryRoute.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get aiPrimaryRoute;

  /// No description provided for @aiRouteDialect.
  ///
  /// In en, this message translates to:
  /// **'Reasoning switch: {field}'**
  String aiRouteDialect(String field);

  /// No description provided for @aiRouteLadder.
  ///
  /// In en, this message translates to:
  /// **'No platform switch — the local-server ladder, judged by the reply'**
  String get aiRouteLadder;

  /// No description provided for @aiRouteNotInBuild.
  ///
  /// In en, this message translates to:
  /// **'Arrives in a later update'**
  String get aiRouteNotInBuild;

  /// No description provided for @aiChannelKey.
  ///
  /// In en, this message translates to:
  /// **'API key (shared by the whole channel)'**
  String get aiChannelKey;

  /// No description provided for @aiChannelHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get aiChannelHost;

  /// No description provided for @aiChannelHostHint.
  ///
  /// In en, this message translates to:
  /// **'Entered once; every route builds on it'**
  String get aiChannelHostHint;

  /// No description provided for @aiChannelName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get aiChannelName;

  /// No description provided for @aiDeleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete channel'**
  String get aiDeleteChannel;

  /// No description provided for @aiDeleteChannelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}” and {count, plural, =0{its settings} =1{its model} other{its {count} models}}? This cannot be undone.'**
  String aiDeleteChannelConfirm(String name, int count);

  /// No description provided for @aiPlatformInferred.
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform} · inferred from the host'**
  String aiPlatformInferred(String platform);

  /// No description provided for @aiPlatformChosen.
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform}'**
  String aiPlatformChosen(String platform);

  /// No description provided for @aiRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get aiRoutesTitle;

  /// No description provided for @aiRoutesHint.
  ///
  /// In en, this message translates to:
  /// **'At most one per protocol. Only the protocols this platform offers are listed.'**
  String get aiRoutesHint;

  /// No description provided for @aiRoutePathDefault.
  ///
  /// In en, this message translates to:
  /// **'Default: {path}'**
  String aiRoutePathDefault(String path);

  /// No description provided for @aiRouteHostItself.
  ///
  /// In en, this message translates to:
  /// **'the host itself'**
  String get aiRouteHostItself;

  /// No description provided for @aiRouteEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get aiRouteEnable;

  /// No description provided for @aiRouteDisable.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get aiRouteDisable;

  /// No description provided for @aiRouteMakePrimary.
  ///
  /// In en, this message translates to:
  /// **'Make primary'**
  String get aiRouteMakePrimary;

  /// No description provided for @aiRouteInUse.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 model uses} other{{count} models use}} this route — it cannot be turned off.'**
  String aiRouteInUse(int count);

  /// No description provided for @aiRouteNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Offered by the platform, not enabled. Models can switch to it once it is; their parameters start blank.'**
  String get aiRouteNotEnabled;

  /// No description provided for @aiRoutePathNote.
  ///
  /// In en, this message translates to:
  /// **'Blank = the platform’s own path. A relative path is added to the host; a full URL replaces the host too (shown as “own host”).'**
  String get aiRoutePathNote;

  /// No description provided for @aiRouteOwnHost.
  ///
  /// In en, this message translates to:
  /// **'own host'**
  String get aiRouteOwnHost;

  /// No description provided for @aiModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get aiModelsTitle;

  /// No description provided for @aiAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get aiAddModel;

  /// No description provided for @aiModelNameHint.
  ///
  /// In en, this message translates to:
  /// **'Model name as the server knows it'**
  String get aiModelNameHint;

  /// No description provided for @aiRouteBar.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get aiRouteBar;

  /// No description provided for @aiRouteBarHint.
  ///
  /// In en, this message translates to:
  /// **'Switching route keeps the model id. A route never configured starts blank.'**
  String get aiRouteBarHint;

  /// No description provided for @aiCapabilityMatrix.
  ///
  /// In en, this message translates to:
  /// **'Capability matrix'**
  String get aiCapabilityMatrix;

  /// No description provided for @aiScopeModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiScopeModel;

  /// No description provided for @aiScopeModelHint.
  ///
  /// In en, this message translates to:
  /// **'Same on every route'**
  String get aiScopeModelHint;

  /// No description provided for @aiUpstreamModel.
  ///
  /// In en, this message translates to:
  /// **'Upstream model name'**
  String get aiUpstreamModel;

  /// No description provided for @aiAllowImage.
  ///
  /// In en, this message translates to:
  /// **'Allow image input'**
  String get aiAllowImage;

  /// No description provided for @aiAllowVideo.
  ///
  /// In en, this message translates to:
  /// **'Allow video frames'**
  String get aiAllowVideo;

  /// No description provided for @aiAllowHint.
  ///
  /// In en, this message translates to:
  /// **'An authorization. Whether it can be sent depends on the route.'**
  String get aiAllowHint;

  /// No description provided for @aiScopeRoute.
  ///
  /// In en, this message translates to:
  /// **'This route · {protocol}'**
  String aiScopeRoute(String protocol);

  /// No description provided for @aiScopeRouteHint.
  ///
  /// In en, this message translates to:
  /// **'Changes with the protocol; parked here when you switch routes'**
  String get aiScopeRouteHint;

  /// No description provided for @aiThinkingDialect.
  ///
  /// In en, this message translates to:
  /// **'Reasoning switch'**
  String get aiThinkingDialect;

  /// No description provided for @aiDialectField.
  ///
  /// In en, this message translates to:
  /// **'{field} · from the platform profile'**
  String aiDialectField(String field);

  /// No description provided for @aiSendsAs.
  ///
  /// In en, this message translates to:
  /// **'Sent as {field}'**
  String aiSendsAs(String field);

  /// No description provided for @aiLearnedTag.
  ///
  /// In en, this message translates to:
  /// **'learned'**
  String get aiLearnedTag;

  /// No description provided for @aiRefusedFields.
  ///
  /// In en, this message translates to:
  /// **'Refused on this route and no longer sent: {fields}'**
  String aiRefusedFields(String fields);

  /// No description provided for @aiStructuredOutput.
  ///
  /// In en, this message translates to:
  /// **'Structured output'**
  String get aiStructuredOutput;

  /// No description provided for @aiStructuredLearned.
  ///
  /// In en, this message translates to:
  /// **'{mode} · learned'**
  String aiStructuredLearned(String mode);

  /// No description provided for @aiStructuredUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not needed by any task; the test learns it only as a fallback'**
  String get aiStructuredUnknown;

  /// No description provided for @aiPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'What will be sent'**
  String get aiPreviewTitle;

  /// No description provided for @aiPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Built by the same code as the real request, for an organize turn.'**
  String get aiPreviewHint;

  /// No description provided for @aiPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This build has no adapter for this protocol yet.'**
  String get aiPreviewUnavailable;

  /// No description provided for @aiTestRoute.
  ///
  /// In en, this message translates to:
  /// **'Test this route'**
  String get aiTestRoute;

  /// No description provided for @aiDeleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete model'**
  String get aiDeleteModel;

  /// No description provided for @aiDeleteModelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? Tasks assigned to it go back to following organize.'**
  String aiDeleteModelConfirm(String name);

  /// No description provided for @aiToolsMeasured.
  ///
  /// In en, this message translates to:
  /// **'Supported · measured on this route'**
  String get aiToolsMeasured;

  /// No description provided for @aiToolsMeasuredNo.
  ///
  /// In en, this message translates to:
  /// **'Not supported · measured on this route'**
  String get aiToolsMeasuredNo;

  /// No description provided for @aiToolsNotMeasured.
  ///
  /// In en, this message translates to:
  /// **'Not checked on this route yet'**
  String get aiToolsNotMeasured;

  /// No description provided for @aiSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch {model} from {from} to {to}'**
  String aiSwitchTitle(String model, String from, String to);

  /// No description provided for @aiSwitchBody.
  ///
  /// In en, this message translates to:
  /// **'The current route’s parameters stay parked under it and come back unchanged if you switch back. Values the new route had before are loaded; anything never set there is “not set · not sent” — never copied.'**
  String get aiSwitchBody;

  /// No description provided for @aiSwitchParam.
  ///
  /// In en, this message translates to:
  /// **'Parameter'**
  String get aiSwitchParam;

  /// No description provided for @aiSwitchNow.
  ///
  /// In en, this message translates to:
  /// **'Now · {protocol}'**
  String aiSwitchNow(String protocol);

  /// No description provided for @aiSwitchAfter.
  ///
  /// In en, this message translates to:
  /// **'After · {protocol}'**
  String aiSwitchAfter(String protocol);

  /// No description provided for @aiParamThinking.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get aiParamThinking;

  /// No description provided for @aiParamMaxOutput.
  ///
  /// In en, this message translates to:
  /// **'Max output'**
  String get aiParamMaxOutput;

  /// No description provided for @aiParamSampling.
  ///
  /// In en, this message translates to:
  /// **'Sampling'**
  String get aiParamSampling;

  /// No description provided for @aiParamTools.
  ///
  /// In en, this message translates to:
  /// **'Tool calling'**
  String get aiParamTools;

  /// No description provided for @aiParamImage.
  ///
  /// In en, this message translates to:
  /// **'Image input'**
  String get aiParamImage;

  /// No description provided for @aiNotSetNotSent.
  ///
  /// In en, this message translates to:
  /// **'not set · not sent'**
  String get aiNotSetNotSent;

  /// No description provided for @aiOn.
  ///
  /// In en, this message translates to:
  /// **'on'**
  String get aiOn;

  /// No description provided for @aiOff.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get aiOff;

  /// No description provided for @aiToolsProbeAfter.
  ///
  /// In en, this message translates to:
  /// **'Not checked — test the route after switching'**
  String get aiToolsProbeAfter;

  /// No description provided for @aiSwitchFooter.
  ///
  /// In en, this message translates to:
  /// **'The model id is unchanged; task assignments are unaffected.'**
  String get aiSwitchFooter;

  /// No description provided for @aiSwitchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get aiSwitchConfirm;

  /// No description provided for @aiMatrixHint.
  ///
  /// In en, this message translates to:
  /// **'Allowing is your switch; whether it can be sent is platform × route × model.'**
  String get aiMatrixHint;

  /// No description provided for @aiCapTools.
  ///
  /// In en, this message translates to:
  /// **'Tool calling'**
  String get aiCapTools;

  /// No description provided for @aiCapToolsHint.
  ///
  /// In en, this message translates to:
  /// **'Organize and scrape need it'**
  String get aiCapToolsHint;

  /// No description provided for @aiCapJson.
  ///
  /// In en, this message translates to:
  /// **'JSON mode'**
  String get aiCapJson;

  /// No description provided for @aiCapJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Connection-test fallback only'**
  String get aiCapJsonHint;

  /// No description provided for @aiCapImage.
  ///
  /// In en, this message translates to:
  /// **'Image input'**
  String get aiCapImage;

  /// No description provided for @aiCapVideo.
  ///
  /// In en, this message translates to:
  /// **'Video input'**
  String get aiCapVideo;

  /// No description provided for @aiCapThinkingOff.
  ///
  /// In en, this message translates to:
  /// **'Reasoning off'**
  String get aiCapThinkingOff;

  /// No description provided for @aiCapThinkingOffHint.
  ///
  /// In en, this message translates to:
  /// **'Judged by whether the reply still reasoned'**
  String get aiCapThinkingOffHint;

  /// No description provided for @aiCapUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage reporting'**
  String get aiCapUsage;

  /// No description provided for @aiCapUsageHint.
  ///
  /// In en, this message translates to:
  /// **'Not reported ≠ 0'**
  String get aiCapUsageHint;

  /// No description provided for @aiCapAllowed.
  ///
  /// In en, this message translates to:
  /// **'allowed'**
  String get aiCapAllowed;

  /// No description provided for @aiCapNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'not allowed'**
  String get aiCapNotAllowed;

  /// No description provided for @aiColCurrent.
  ///
  /// In en, this message translates to:
  /// **'current'**
  String get aiColCurrent;

  /// No description provided for @aiColEnabled.
  ///
  /// In en, this message translates to:
  /// **'enabled'**
  String get aiColEnabled;

  /// No description provided for @aiColOffered.
  ///
  /// In en, this message translates to:
  /// **'not enabled'**
  String get aiColOffered;

  /// No description provided for @aiCellMeasured.
  ///
  /// In en, this message translates to:
  /// **'works · measured'**
  String get aiCellMeasured;

  /// No description provided for @aiCellUnmeasured.
  ///
  /// In en, this message translates to:
  /// **'not measured'**
  String get aiCellUnmeasured;

  /// No description provided for @aiCellUnsupported.
  ///
  /// In en, this message translates to:
  /// **'not supported · measured'**
  String get aiCellUnsupported;

  /// No description provided for @aiCellLearned.
  ///
  /// In en, this message translates to:
  /// **'{mode} · learned'**
  String aiCellLearned(String mode);

  /// No description provided for @aiCellParameter.
  ///
  /// In en, this message translates to:
  /// **'parameter, not measured'**
  String get aiCellParameter;

  /// No description provided for @aiCellNotInBuild.
  ///
  /// In en, this message translates to:
  /// **'not in this build'**
  String get aiCellNotInBuild;

  /// No description provided for @aiCellSwitch.
  ///
  /// In en, this message translates to:
  /// **'{field} · platform switch'**
  String aiCellSwitch(String field);

  /// No description provided for @aiCellLadder.
  ///
  /// In en, this message translates to:
  /// **'ladder · judged by reply'**
  String get aiCellLadder;

  /// No description provided for @aiCellLadderExhausted.
  ///
  /// In en, this message translates to:
  /// **'no way worked here'**
  String get aiCellLadderExhausted;

  /// No description provided for @aiCellProtocolUsage.
  ///
  /// In en, this message translates to:
  /// **'part of the protocol'**
  String get aiCellProtocolUsage;

  /// No description provided for @aiCellNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'not allowed'**
  String get aiCellNotAllowed;

  /// No description provided for @aiMatrixFootnote.
  ///
  /// In en, this message translates to:
  /// **'Task pickers read this matrix: a model is offered for frame recognition only where image input can actually be sent on its current route.'**
  String get aiMatrixFootnote;

  /// No description provided for @aiDiagTest.
  ///
  /// In en, this message translates to:
  /// **'Test a route'**
  String get aiDiagTest;

  /// No description provided for @aiDiagRun.
  ///
  /// In en, this message translates to:
  /// **'Run test'**
  String get aiDiagRun;

  /// No description provided for @aiStepReach.
  ///
  /// In en, this message translates to:
  /// **'Reachable'**
  String get aiStepReach;

  /// No description provided for @aiStepServer.
  ///
  /// In en, this message translates to:
  /// **'Identified as {kind}'**
  String aiStepServer(String kind);

  /// No description provided for @aiStepGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generated in {ms} ms · {prompt} + {completion} tokens'**
  String aiStepGenerate(int ms, int prompt, int completion);

  /// No description provided for @aiStepTruncated.
  ///
  /// In en, this message translates to:
  /// **'Reply hit the output limit'**
  String get aiStepTruncated;

  /// No description provided for @aiStepThinkingOff.
  ///
  /// In en, this message translates to:
  /// **'Reasoning is off'**
  String get aiStepThinkingOff;

  /// No description provided for @aiStepThinkingStillOn.
  ///
  /// In en, this message translates to:
  /// **'The model still reasoned'**
  String get aiStepThinkingStillOn;

  /// No description provided for @aiStepTools.
  ///
  /// In en, this message translates to:
  /// **'Called the test tool'**
  String get aiStepTools;

  /// No description provided for @aiStepToolsNo.
  ///
  /// In en, this message translates to:
  /// **'Did not call the test tool'**
  String get aiStepToolsNo;

  /// No description provided for @aiStepToolsUnknown.
  ///
  /// In en, this message translates to:
  /// **'Tool calling undecided — the request did not complete'**
  String get aiStepToolsUnknown;

  /// No description provided for @aiStepUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage reported'**
  String get aiStepUsage;

  /// No description provided for @aiStepUsageMissing.
  ///
  /// In en, this message translates to:
  /// **'No usage reported (counted as unknown, not 0)'**
  String get aiStepUsageMissing;

  /// No description provided for @aiStepContext.
  ///
  /// In en, this message translates to:
  /// **'Context: the server serves {served}, you entered {typed}'**
  String aiStepContext(int served, int typed);

  /// No description provided for @aiStepContextBody.
  ///
  /// In en, this message translates to:
  /// **'A local server past its window drops the system prompt from the front without a word.'**
  String get aiStepContextBody;

  /// No description provided for @aiStepUseServed.
  ///
  /// In en, this message translates to:
  /// **'Use the served value'**
  String get aiStepUseServed;

  /// No description provided for @aiLogTitle.
  ///
  /// In en, this message translates to:
  /// **'API log · today'**
  String get aiLogTitle;

  /// No description provided for @aiLogHint.
  ///
  /// In en, this message translates to:
  /// **'Every body actually sent, numbered'**
  String get aiLogHint;

  /// No description provided for @aiLogOff.
  ///
  /// In en, this message translates to:
  /// **'Logging is off. Turn it on to record requests.'**
  String get aiLogOff;

  /// No description provided for @aiLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged today.'**
  String get aiLogEmpty;

  /// No description provided for @aiLogOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Show in folder'**
  String get aiLogOpenFolder;

  /// No description provided for @aiLogFootnote.
  ///
  /// In en, this message translates to:
  /// **'Keys are never written; images and strings over 2 KB are replaced by their length; writes are serial, so concurrent requests never interleave.'**
  String get aiLogFootnote;

  /// No description provided for @scrapeBackendAssigned.
  ///
  /// In en, this message translates to:
  /// **'As assigned in Settings'**
  String get scrapeBackendAssigned;

  /// No description provided for @aiPlatformLabel.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get aiPlatformLabel;

  /// No description provided for @aiMergeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge channels'**
  String get aiMergeConfirmTitle;

  /// No description provided for @aiMergeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Routes and models move into “{name}” and the other channels are removed. Every model keeps its URL, parameters and task assignments.'**
  String aiMergeConfirmBody(String name);

  /// No description provided for @aiCellPromptOnly.
  ///
  /// In en, this message translates to:
  /// **'no parameter · prompt only'**
  String get aiCellPromptOnly;

  /// No description provided for @aiCellAlwaysReasons.
  ///
  /// In en, this message translates to:
  /// **'this model always reasons'**
  String get aiCellAlwaysReasons;

  /// No description provided for @aiCellDefaultOff.
  ///
  /// In en, this message translates to:
  /// **'off by default'**
  String get aiCellDefaultOff;

  /// No description provided for @aiCellModelDefault.
  ///
  /// In en, this message translates to:
  /// **'the model’s default'**
  String get aiCellModelDefault;

  /// No description provided for @aiCellSentAs.
  ///
  /// In en, this message translates to:
  /// **'sent as {part} · not measured'**
  String aiCellSentAs(String part);

  /// No description provided for @aiCellAsFrames.
  ///
  /// In en, this message translates to:
  /// **'as image frames · not measured'**
  String get aiCellAsFrames;

  /// No description provided for @aiVisionAllowFrames.
  ///
  /// In en, this message translates to:
  /// **'Send video frames to this model'**
  String get aiVisionAllowFrames;

  /// No description provided for @aiVisionAllowFramesHint.
  ///
  /// In en, this message translates to:
  /// **'Off by default: frames leave this computer. Organize uses them only for videos whose names say nothing, and every group decided that way is flagged for review.'**
  String get aiVisionAllowFramesHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
