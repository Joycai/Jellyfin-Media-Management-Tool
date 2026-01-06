import 'package:flutter/material.dart';

class FileLabelService {
  static final Map<String, String> _extensionToLabel = {
    '.mkv': 'Video',
    '.mp4': 'Video',
    '.avi': 'Video',
    '.mov': 'Video',
    '.wmv': 'Video',
    '.flv': 'Video',
    '.webm': 'Video',
    '.srt': 'Subtitle',
    '.ass': 'Subtitle',
    '.vtt': 'Subtitle',
    '.sub': 'Subtitle',
    '.jpg': 'Image',
    '.jpeg': 'Image',
    '.png': 'Image',
    '.gif': 'Image',
    '.webp': 'Image',
    '.nfo': 'Metadata',
    '.xml': 'Metadata',
    '.mp3': 'Audio',
    '.flac': 'Audio',
    '.wav': 'Audio',
    '.m4a': 'Audio',
    '.ogg': 'Audio',
    '.txt': 'Text',
  };

  static String getLabel(String extension) {
    return _extensionToLabel[extension.toLowerCase()] ?? 'Other';
  }

  static IconData getIcon(String label, bool isDirectory) {
    if (isDirectory) return Icons.folder;
    
    switch (label) {
      case 'Video':
        return Icons.movie_outlined;
      case 'Subtitle':
        return Icons.subtitles_outlined;
      case 'Image':
        return Icons.image_outlined;
      case 'Metadata':
        return Icons.description_outlined;
      case 'Audio':
        return Icons.audiotrack_outlined;
      case 'Text':
        return Icons.text_snippet_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color getIconColor(String label, bool isDirectory) {
    if (isDirectory) return Colors.amber.shade700;

    switch (label) {
      case 'Video':
        return Colors.blue.shade600;
      case 'Subtitle':
        return Colors.teal.shade600;
      case 'Image':
        return Colors.orange.shade600;
      case 'Metadata':
        return Colors.grey.shade600;
      case 'Audio':
        return Colors.pink.shade600;
      case 'Text':
        return Colors.brown.shade600;
      default:
        return Colors.blueGrey.shade400;
    }
  }

  static void addLabel(String extension, String label) {
    _extensionToLabel[extension.toLowerCase()] = label;
  }
}
