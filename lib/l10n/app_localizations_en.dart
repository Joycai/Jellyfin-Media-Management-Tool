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
  String get selectFileToPreview => 'Select a file to preview';

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
  String get apply => 'Apply';

  @override
  String get isDefault => 'Default';

  @override
  String get languageLabel => 'Language';

  @override
  String get video => 'Video';
}
