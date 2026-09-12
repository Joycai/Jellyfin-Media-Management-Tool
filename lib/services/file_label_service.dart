import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

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

  /// 类型图标色，取自设计稿 3.1（见 [AppPalette] 的 `type*`）。
  ///
  /// 只有视频、影像与音频拿到色相；字幕、元数据、文本这些「陪跑文件」留在
  /// 中性档 —— 它们在一个文件夹里数量最多，给它们上色等于给整列上色。
  static Color getIconColor(String label, bool isDirectory) {
    if (isDirectory) return AppPalette.typeFolder;

    switch (label) {
      case 'Video':
        return AppPalette.typeVideo;
      case 'Image':
        return AppPalette.typeImage;
      case 'Audio':
        return AppPalette.typeSeries;
      case 'Subtitle':
      case 'Metadata':
      case 'Text':
      default:
        return AppPalette.typeNeutral;
    }
  }
}
