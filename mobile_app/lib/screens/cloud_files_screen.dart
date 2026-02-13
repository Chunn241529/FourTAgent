import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/cloud_file_service.dart';
import '../widgets/file_viewer_dialog.dart';

class CloudFilesScreen extends StatefulWidget {
  final bool isEmbedded;
  const CloudFilesScreen({super.key, this.isEmbedded = false});

  @override
  State<CloudFilesScreen> createState() => _CloudFilesScreenState();
}

class _CloudFilesScreenState extends State<CloudFilesScreen> {
  String _currentPath = '/';
  List<CloudFile> _files = [];
  bool _isLoading = false;
  
  // Breadcrumbs navigation logic
  List<String> get _breadcrumbs {
    if (_currentPath == '/') return ['Root'];
    final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    return ['Root', ...parts];
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final files = await CloudFileService.listFiles(_currentPath);
      // Sort: Directories first, then files
      files.sort((a, b) {
        if (a.type == b.type) {
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
        return a.type == 'directory' ? -1 : 1;
      });
      if (mounted) {
        setState(() => _files = files);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading files: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateTo(String directoryName) {
    setState(() {
      if (_currentPath == '/') {
        _currentPath = directoryName;
      } else {
        _currentPath = '$_currentPath/$directoryName';
      }
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath == '/') return;
    
    final lastSlash = _currentPath.lastIndexOf('/');
    if (lastSlash == -1) { // Should not happen if path logic is correct
      setState(() => _currentPath = '/');
    } else {
       // e.g. "folder/sub" -> "folder"
       // "folder" -> "" (logic fix needed)
       
       final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
       if (parts.length <= 1) {
         setState(() => _currentPath = '/');
       } else {
         parts.removeLast();
         setState(() => _currentPath = parts.join('/'));
       }
    }
    _loadFiles();
  }
  
  void _navigateToBreadcrumb(int index) {
      if (index == 0) {
          setState(() => _currentPath = '/');
      } else {
          final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
          final newPath = parts.take(index).join('/');
          setState(() => _currentPath = newPath);
      }
      _loadFiles();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        final newPath = _currentPath == '/' ? name : '$_currentPath/$name';
        await CloudFileService.createFolder(newPath);
        _loadFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }
  
  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
          final file = File(result.files.single.path!);
          await CloudFileService.uploadFile(file, _currentPath);
          _loadFiles();
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploaded successfully')));
          }
      }
    } catch (e) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        }
    }
  }

  Future<void> _deleteItem(CloudFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${file.name}?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
             style: TextButton.styleFrom(foregroundColor: Colors.red),
             onPressed: () => Navigator.pop(context, true), 
             child: const Text('Delete')
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final path = _currentPath == '/' ? file.name : '$_currentPath/${file.name}';
        await CloudFileService.delete(path);
        _loadFiles();
      } catch (e) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
         }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isEmbedded ? Colors.transparent : null,
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('Cloud Files'),
        leading: _currentPath != '/' 
           ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _navigateUp)
           : null,
        actions: [
           IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles),
        ],
      ),
      body: Column(
        children: [
          // Embedded Toolbar (only if embedded)
          if (widget.isEmbedded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  if (_currentPath != '/')
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _navigateUp,
                      tooltip: 'Back',
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder), 
                    onPressed: _createFolder,
                    tooltip: 'New Folder',
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file), 
                    onPressed: _uploadFile,
                    tooltip: 'Upload File',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh), 
                    onPressed: _loadFiles,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

          // Breadcrumbs
          Container(
             height: 40,
             padding: const EdgeInsets.symmetric(horizontal: 8),
             decoration: BoxDecoration(
               color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
               borderRadius: BorderRadius.circular(8),
             ),
             child: ListView.separated(
               scrollDirection: Axis.horizontal,
               itemCount: _breadcrumbs.length,
               separatorBuilder: (context, index) => const Icon(Icons.chevron_right, size: 16),
               itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () => _navigateToBreadcrumb(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Center(
                         child: Text(
                           _breadcrumbs[index], 
                           style: TextStyle(
                             fontWeight: index == _breadcrumbs.length - 1 ? FontWeight.bold : FontWeight.normal,
                             color: index == _breadcrumbs.length - 1 ? Theme.of(context).colorScheme.primary : null,
                           )
                         ),
                      ),
                    ),
                  );
               },
             ),
          ),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _files.isEmpty 
                 ? const Center(child: Text('No files found'))
                 : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final isDir = file.type == 'directory';
                      
                      return ListTile(
                        leading: Icon(
                          isDir ? Icons.folder : Icons.insert_drive_file,
                          color: isDir ? Colors.amber : Colors.blueGrey,
                        ),
                        title: Text(file.name),
                        subtitle: isDir ? null : Text('${file.size} bytes'),
                        onTap: () {
                           if (isDir) {
                             _navigateTo(file.name);
                           } else {
                              // Open file viewer
                              FileViewerDialog.show(context, file);
                           }
                        },
                        trailing: PopupMenuButton(
                           itemBuilder: (context) => [
                             const PopupMenuItem(value: 'delete', child: Text('Delete')),
                           ],
                           onSelected: (value) {
                             if (value == 'delete') _deleteItem(file);
                           },
                        ),
                      );
                    },
                 ),
          ),
        ],
      ),
      floatingActionButton: widget.isEmbedded ? null : Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
           FloatingActionButton.small(
             heroTag: 'create_folder',
             onPressed: _createFolder,
             child: const Icon(Icons.create_new_folder),
           ),
           const SizedBox(height: 10),
           FloatingActionButton(
             heroTag: 'upload_file',
             onPressed: _uploadFile,
             child: const Icon(Icons.upload_file),
           ),
        ],
      ),
    );
  }
}
