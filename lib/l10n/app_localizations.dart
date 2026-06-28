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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin Media Management Tool'**
  String get appTitle;

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

  /// No description provided for @mediaManager.
  ///
  /// In en, this message translates to:
  /// **'Media Manager'**
  String get mediaManager;

  /// No description provided for @pickDirectory.
  ///
  /// In en, this message translates to:
  /// **'Pick Directory'**
  String get pickDirectory;

  /// No description provided for @openDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Directory'**
  String get openDirectory;

  /// No description provided for @parentFolder.
  ///
  /// In en, this message translates to:
  /// **'Parent Folder'**
  String get parentFolder;

  /// No description provided for @createNewFolder.
  ///
  /// In en, this message translates to:
  /// **'Create New Folder'**
  String get createNewFolder;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortBy;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort by Name'**
  String get sortByName;

  /// No description provided for @sortByType.
  ///
  /// In en, this message translates to:
  /// **'Sort by Type'**
  String get sortByType;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'Sort by Date'**
  String get sortByDate;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'Sort by Size'**
  String get sortBySize;

  /// No description provided for @ascending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascending;

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

  /// No description provided for @playVideo.
  ///
  /// In en, this message translates to:
  /// **'Play Video'**
  String get playVideo;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get openFile;

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

  /// No description provided for @confirmRename.
  ///
  /// In en, this message translates to:
  /// **'Confirm Rename'**
  String get confirmRename;

  /// No description provided for @renameFrom.
  ///
  /// In en, this message translates to:
  /// **'From:'**
  String get renameFrom;

  /// No description provided for @renameTo.
  ///
  /// In en, this message translates to:
  /// **'To:'**
  String get renameTo;

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

  /// No description provided for @searchFromWeb.
  ///
  /// In en, this message translates to:
  /// **'Search from Web'**
  String get searchFromWeb;

  /// No description provided for @searchKeyword.
  ///
  /// In en, this message translates to:
  /// **'Search Keyword'**
  String get searchKeyword;

  /// No description provided for @searchSite.
  ///
  /// In en, this message translates to:
  /// **'Search Site'**
  String get searchSite;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @editSearchSites.
  ///
  /// In en, this message translates to:
  /// **'Edit Search Sites'**
  String get editSearchSites;

  /// No description provided for @siteName.
  ///
  /// In en, this message translates to:
  /// **'Site Name'**
  String get siteName;

  /// No description provided for @searchUrl.
  ///
  /// In en, this message translates to:
  /// **'Search URL'**
  String get searchUrl;

  /// No description provided for @addSite.
  ///
  /// In en, this message translates to:
  /// **'Add Site'**
  String get addSite;

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

  /// No description provided for @areYouSure.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get areYouSure;

  /// No description provided for @sizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String sizeLabel(Object size);

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration: {duration}'**
  String durationLabel(Object duration);

  /// No description provided for @resolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolution: {resolution}'**
  String resolutionLabel(Object resolution);

  /// No description provided for @noDirectorySelected.
  ///
  /// In en, this message translates to:
  /// **'No directory selected'**
  String get noDirectorySelected;

  /// No description provided for @pleaseSelectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Please select a directory'**
  String get pleaseSelectDirectory;

  /// No description provided for @noPreviewAvailable.
  ///
  /// In en, this message translates to:
  /// **'No preview available'**
  String get noPreviewAvailable;

  /// No description provided for @directoriesCannotBePreviewed.
  ///
  /// In en, this message translates to:
  /// **'Directories cannot be previewed'**
  String get directoriesCannotBePreviewed;

  /// No description provided for @selectFileToPreview.
  ///
  /// In en, this message translates to:
  /// **'Select a file to preview'**
  String get selectFileToPreview;

  /// No description provided for @errorAccessingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Error accessing directory: {error}'**
  String errorAccessingDirectory(Object error);

  /// No description provided for @errorCreatingFolder.
  ///
  /// In en, this message translates to:
  /// **'Error creating folder: {error}'**
  String errorCreatingFolder(Object error);

  /// No description provided for @errorRenaming.
  ///
  /// In en, this message translates to:
  /// **'Error renaming: {error}'**
  String errorRenaming(Object error);

  /// No description provided for @noSearchSitesConfigured.
  ///
  /// In en, this message translates to:
  /// **'No search sites configured in Settings'**
  String get noSearchSitesConfigured;

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
  /// **'Jellyfin Organizer'**
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

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openFolder;

  /// No description provided for @noFolderOpen.
  ///
  /// In en, this message translates to:
  /// **'Open a folder to begin'**
  String get noFolderOpen;

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

  /// No description provided for @applyOrganize.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyOrganize;

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

  /// No description provided for @confirmApplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply organization?'**
  String get confirmApplyTitle;

  /// No description provided for @confirmApplyBody.
  ///
  /// In en, this message translates to:
  /// **'{count} files will be moved and renamed into the Jellyfin structure.'**
  String confirmApplyBody(Object count);

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

  /// No description provided for @analyzeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String analyzeFailed(Object error);

  /// No description provided for @aiSettings.
  ///
  /// In en, this message translates to:
  /// **'AI Service'**
  String get aiSettings;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @providerOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible'**
  String get providerOpenAi;

  /// No description provided for @providerGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI'**
  String get providerGoogle;

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

  /// No description provided for @connectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get connectionOk;

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

  /// No description provided for @aiServicesTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Services'**
  String get aiServicesTitle;

  /// No description provided for @aiServicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure the language models used to organize media'**
  String get aiServicesSubtitle;

  /// No description provided for @aiServiceDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Primary AI endpoint for organization and metadata matching'**
  String get aiServiceDetailHint;

  /// No description provided for @addService.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get addService;

  /// No description provided for @addAnotherEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Add another endpoint'**
  String get addAnotherEndpoint;

  /// No description provided for @newServiceName.
  ///
  /// In en, this message translates to:
  /// **'New Service'**
  String get newServiceName;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusStandby.
  ///
  /// In en, this message translates to:
  /// **'Standby'**
  String get statusStandby;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @endpointProtocol.
  ///
  /// In en, this message translates to:
  /// **'Endpoint protocol'**
  String get endpointProtocol;

  /// No description provided for @protocolOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI compatible'**
  String get protocolOpenAi;

  /// No description provided for @protocolGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google GenAI'**
  String get protocolGoogle;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

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

  /// No description provided for @defaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get defaultModel;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

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

  /// No description provided for @selectServiceHint.
  ///
  /// In en, this message translates to:
  /// **'Select a service to configure'**
  String get selectServiceHint;

  /// No description provided for @deleteServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete service'**
  String get deleteServiceTitle;

  /// No description provided for @deleteServiceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteServiceConfirm(Object name);

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

  /// No description provided for @breadcrumbPaths.
  ///
  /// In en, this message translates to:
  /// **'Paths'**
  String get breadcrumbPaths;

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
  /// **'None'**
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

  /// No description provided for @behaviorAutoConnect.
  ///
  /// In en, this message translates to:
  /// **'Auto-connect to AI service on launch'**
  String get behaviorAutoConnect;

  /// No description provided for @behaviorAlwaysPreview.
  ///
  /// In en, this message translates to:
  /// **'Always show preview before applying'**
  String get behaviorAlwaysPreview;

  /// No description provided for @behaviorLowConfSuggest.
  ///
  /// In en, this message translates to:
  /// **'Only suggest (don\'t auto-apply) when confidence < 60%'**
  String get behaviorLowConfSuggest;

  /// No description provided for @privacyStorage.
  ///
  /// In en, this message translates to:
  /// **'Local storage'**
  String get privacyStorage;

  /// No description provided for @privacyConfigBody.
  ///
  /// In en, this message translates to:
  /// **'Settings, AI keys and undo manifests are stored on this device only.'**
  String get privacyConfigBody;

  /// No description provided for @privacyClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Undo all {count} entries'**
  String privacyClearHistory(Object count);

  /// No description provided for @shortcutSearch.
  ///
  /// In en, this message translates to:
  /// **'Focus search'**
  String get shortcutSearch;

  /// No description provided for @shortcutCloseDialog.
  ///
  /// In en, this message translates to:
  /// **'Close dialog'**
  String get shortcutCloseDialog;

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

  /// No description provided for @langSoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get langSoon;

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
  /// **'Welcome to Jellyfin Organizer'**
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
