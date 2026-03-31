import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class FileToolService {
  static Future<String> _normalizePath(String path) async {
    // Handle home alias
    if (path.startsWith('~/')) {
      final docs = await getApplicationDocumentsDirectory();
      // Try to find the implied home root
      // Usually docs is /home/user/Documents or /data/.../app_flutter
      // We will map ~ to the parent of Documents if possible
      return path.replaceFirst('~/', '${docs.parent.path}/');
    }

    // Handle generic LLM hallucinations (linux style)
    if (path.startsWith('/home/user/')) {
       // Prioritize Downloads
       try {
         final downloads = await getDownloadsDirectory();
         if (downloads != null) {
            // Check if explicitly Documents
            if (path.contains('/Documents/')) {
               final docs = await getApplicationDocumentsDirectory();
               return path.replaceFirst(RegExp(r'^/home/user/Documents/?'), '${docs.path}/');
            }
            // Otherwise default to Downloads
            return path.replaceFirst(RegExp(r'^/home/user/[^/]+/?'), '${downloads.path}/');
         }
       } catch (_) {}
       
       // Fallback to Documents if Downloads unavailable
       final docs = await getApplicationDocumentsDirectory();
       return path.replaceFirst(RegExp(r'^/home/user/[^/]+/?'), '${docs.path}/');
    }
    
    // If just a filename, default to Downloads
    if (!path.contains('/')) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return p.join(downloads.path, path);
      } catch (_) {}
      
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, path);
    }

    return path;
  }

  /// Read a local file's content
  static Future<String> readFile(String path) async {
    try {
      final safePath = await _normalizePath(path);
      final file = File(safePath);
      if (await file.exists()) {
        return await file.readAsString();
      } else {
        return 'Error: File not found at $safePath';
      }
    } catch (e) {
      return 'Error reading file: $e';
    }
  }

  /// Search for files matching query
  static Future<List<String>> searchFiles(String query, {String? directory}) async {
    try {
      List<Directory> searchDirs = [];
      
      if (directory != null && directory.isNotEmpty) {
         // Resolve common directory names
         if (directory.toLowerCase() == 'documents') {
           searchDirs.add(await getApplicationDocumentsDirectory());
         } else if (directory.toLowerCase() == 'desktop') {
           // Desktop might not exist on mobile, fallback to docs
           try {
             searchDirs.add(Directory('${(await getApplicationDocumentsDirectory()).parent.path}/Desktop'));
           } catch (_) {
             searchDirs.add(await getApplicationDocumentsDirectory());
           }
         } else {
           final safeDir = await _normalizePath(directory);
           searchDirs.add(Directory(safeDir));
         }
      } else {
        // Default search common user folders
        searchDirs.add(await getApplicationDocumentsDirectory());
        try {
           final temp = await getTemporaryDirectory();
           searchDirs.add(temp);
           final downloads = await getDownloadsDirectory();
           if (downloads != null) searchDirs.add(downloads);
        } catch (_) {}
      }

      List<String> results = [];
      String pattern = query.replaceAll('*', '.*');
      RegExp regExp = RegExp(pattern, caseSensitive: false);

      for (var dir in searchDirs) {
        if (await dir.exists()) {
          try {
            await for (var entity in dir.list(recursive: true, followLinks: false)) {
              if (entity is File) {
                String filename = p.basename(entity.path);
                if (regExp.hasMatch(filename) || filename.contains(query)) {
                  results.add(entity.path);
                }
              }
              if (results.length >= 20) break; // Limit results
            }
          } catch (_) {}
        }
        if (results.length >= 20) break;
      }

      return results;
    } catch (e) {
      return ['Error searching files: $e'];
    }
  }

  /// Create a new file
  static Future<String> createFile(String path, String content) async {
    try {
      final safePath = await _normalizePath(path);
      final file = File(safePath);
      // Ensure directory exists
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      await file.writeAsString(content);
      return 'Success: File created at $safePath';
    } catch (e) {
      return 'Error creating file: $e';
    }
  }
}
