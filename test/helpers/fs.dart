import 'package:file/file.dart';
import 'package:file/memory.dart';

/// A fresh in-memory filesystem with `/work` pre-created so tests can use it
/// as a stand-in for the app's "base directory" argument.
FileSystem newMemoryFs() {
  final fs = MemoryFileSystem();
  fs.directory('/work').createSync(recursive: true);
  return fs;
}

/// Same as [newMemoryFs] but with Windows path semantics, so a test can prove
/// the service reads paths in the injected filesystem's style rather than the
/// host's.
FileSystem newWindowsMemoryFs() {
  final fs = MemoryFileSystem(style: FileSystemStyle.windows);
  fs.directory(r'C:\work').createSync(recursive: true);
  return fs;
}

/// Writes [contents] (default empty) to [path] inside [fs], creating any
/// intermediate directories.
File seedFile(FileSystem fs, String path, {String contents = ''}) {
  final f = fs.file(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(contents);
  return f;
}
