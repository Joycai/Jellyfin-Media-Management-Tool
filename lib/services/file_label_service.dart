class FileLabelService {
  static final Map<String, String> _extensionToLabel = {
    '.mkv': 'Video',
    '.mp4': 'Video',
    '.avi': 'Video',
    '.mov': 'Video',
    '.wmv': 'Video',
    '.srt': 'Subtitle',
    '.ass': 'Subtitle',
    '.vtt': 'Subtitle',
    '.jpg': 'Image',
    '.jpeg': 'Image',
    '.png': 'Image',
    '.nfo': 'Metadata',
  };

  static String getLabel(String extension) {
    return _extensionToLabel[extension.toLowerCase()] ?? 'Other';
  }

  static void addLabel(String extension, String label) {
    _extensionToLabel[extension.toLowerCase()] = label;
  }
}
