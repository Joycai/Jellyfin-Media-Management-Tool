import 'dart:io';
import 'package:path/path.dart' as p;

enum RenameRule {
  matchFolder,
  featurette,
  interview,
  part,
  tvShow,
  subtitle,
}

class RenameService {
  static String getNewName(File file, RenameRule rule, {String? extra}) {
    final parentDir = file.parent;
    final folderName = p.basename(parentDir.path);
    final extension = p.extension(file.path);

    switch (rule) {
      case RenameRule.matchFolder:
        return '$folderName$extension';
      case RenameRule.featurette:
        return '$folderName-featurette$extension';
      case RenameRule.interview:
        return '$folderName-interview$extension';
      case RenameRule.part:
        return '$folderName-part${extra ?? "1"}$extension';
      case RenameRule.tvShow:
        // extra format expected: "S01E01"
        return '$folderName.${extra ?? "S01E01"}$extension';
      case RenameRule.subtitle:
        // extra format expected: "VideoFileName.chi.[default]"
        return '$extra$extension';
    }
  }

  static Future<File> rename(File file, String newName) async {
    final newPath = p.join(file.parent.path, newName);
    return await file.rename(newPath);
  }
}
