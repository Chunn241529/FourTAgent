import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class UpdateInfo {
  final String version;
  final String? windowsUrl;
  final String? linuxUrl;
  final String? changelog;
  final DateTime? publishedAt;

  UpdateInfo({
    required this.version,
    this.windowsUrl,
    this.linuxUrl,
    this.changelog,
    this.publishedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      windowsUrl: json['windows_url'],
      linuxUrl: json['linux_url'],
      changelog: json['changelog'],
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'])
          : null,
    );
  }

  String? get downloadUrl {
    if (Platform.isWindows) return windowsUrl;
    if (Platform.isLinux) return linuxUrl;
    return null;
  }
}

class UpdateService {
  static const String apiBaseUrl = 'http://localhost:8000'; // TODO: Update in production
  
  /// Check if there's a new version available
  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      print('Current version: $currentVersion');
      
      // Fetch latest version from backend
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/updates/version'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // No releases available
        if (data['version'] == null) {
          print('No releases available');
          return null;
        }
        
        final updateInfo = UpdateInfo.fromJson(data);
        print('Latest version: ${updateInfo.version}');
        
        // Compare versions
        if (_isNewerVersion(currentVersion, updateInfo.version)) {
          print('New version available: ${updateInfo.version}');
          return updateInfo;
        } else {
          print('Already on latest version');
          return null;
        }
      } else {
        print('Failed to check for updates: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error checking for updates: $e');
      return null;
    }
  }
  
  /// Download update file to temporary directory
  static Future<String?> downloadUpdate(String url) async {
    try {
      print('Downloading update from: $url');
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = url.split('/').last;
        final filePath = '${tempDir.path}/$fileName';
        
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        
        print('Update downloaded to: $filePath');
        return filePath;
      } else {
        print('Failed to download update: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error downloading update: $e');
      return null;
    }
  }
  
  /// Install update (platform-specific)
  static Future<bool> installUpdate(String filePath) async {
    try {
      if (Platform.isWindows) {
        return await _installWindowsUpdate(filePath);
      } else if (Platform.isLinux) {
        return await _installLinuxUpdate(filePath);
      }
      return false;
    } catch (e) {
      print('Error installing update: $e');
      return false;
    }
  }
  
  static Future<bool> _installWindowsUpdate(String zipPath) async {
    try {
      // Extract zip to current directory (will replace files)
      final currentDir = Directory.current.path;
      
      // Use PowerShell to extract and replace
      final result = await Process.run('powershell', [
        '-Command',
        'Expand-Archive',
        '-Path',
        zipPath,
        '-DestinationPath',
        currentDir,
        '-Force'
      ]);
      
      if (result.exitCode == 0) {
        print('Update extracted successfully');
        // Restart application
        await Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);
        exit(0);
        return true;
      } else {
        print('Failed to extract update: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('Error installing Windows update: $e');
      return false;
    }
  }
  
  static Future<bool> _installLinuxUpdate(String tarPath) async {
    try {
      // Extract tar.gz to current directory
      final currentDir = Directory.current.path;
      
      final result = await Process.run('tar', [
        '-xzf',
        tarPath,
        '-C',
        currentDir,
        '--overwrite'
      ]);
      
      if (result.exitCode == 0) {
        print('Update extracted successfully');
        // Restart application
        await Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);
        exit(0);
        return true;
      } else {
        print('Failed to extract update: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('Error installing Linux update: $e');
      return false;
    }
  }
  
  /// Compare version strings (simple semver comparison)
  static bool _isNewerVersion(String current, String latest) {
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    // Ensure both have 3 parts
    while (currentParts.length < 3) currentParts.add(0);
    while (latestParts.length < 3) latestParts.add(0);
    
    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    
    return false; // Equal versions
  }
}
