import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart';
import 'services/file_label_service.dart';
import 'widgets/file_preview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jellyfin Media Management Tool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainWorkspace(),
    );
  }
}

class MainWorkspace extends StatefulWidget {
  const MainWorkspace({super.key});

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> {
  String? _currentDirectory;
  List<FileSystemEntity> _files = [];
  FileSystemEntity? _selectedFile;

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        _currentDirectory = selectedDirectory;
        _selectedFile = null;
        _loadFiles();
      });
    }
  }

  void _loadFiles() {
    if (_currentDirectory != null) {
      final directory = Directory(_currentDirectory!);
      try {
        setState(() {
          _files = directory.listSync().toList();
          _files.sort((a, b) {
            if (a is Directory && b is! Directory) return -1;
            if (a is! Directory && b is Directory) return 1;
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });
        });
      } catch (e) {
        debugPrint('Error listing files: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing directory: $e')),
        );
      }
    }
  }

  void _goToParent() {
    if (_currentDirectory != null) {
      final parent = Directory(_currentDirectory!).parent;
      if (parent.path != _currentDirectory) {
        setState(() {
          _currentDirectory = parent.path;
          _selectedFile = null;
          _loadFiles();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jellyfin Media Management Tool'),
      ),
      body: Row(
        children: [
          // Left Side: File Browser
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  // Browser Toolbar
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _currentDirectory != null ? _goToParent : null,
                          tooltip: 'Go to Parent Folder',
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: _pickDirectory,
                          tooltip: 'Open Directory',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _currentDirectory ?? 'No directory selected',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // File List
                  Expanded(
                    child: _currentDirectory == null
                        ? const Center(child: Text('Please select a directory'))
                        : ListView.builder(
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final entity = _files[index];
                              final name = p.basename(entity.path);
                              final isDirectory = entity is Directory;
                              final extension = p.extension(entity.path);
                              final label = isDirectory ? 'Folder' : FileLabelService.getLabel(extension);
                              final isSelected = _selectedFile?.path == entity.path;

                              return InkWell(
                                onDoubleTap: isDirectory
                                    ? () {
                                        setState(() {
                                          _currentDirectory = entity.path;
                                          _selectedFile = null;
                                          _loadFiles();
                                        });
                                      }
                                    : null,
                                child: ListTile(
                                  leading: Icon(isDirectory ? Icons.folder : Icons.insert_drive_file),
                                  title: Text(name),
                                  subtitle: Text(label),
                                  selected: isSelected,
                                  onTap: () {
                                    setState(() {
                                      _selectedFile = entity;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          // Right Side: Operations / Preview
          Expanded(
            flex: 2,
            child: FilePreview(file: _selectedFile),
          ),
        ],
      ),
    );
  }
}
