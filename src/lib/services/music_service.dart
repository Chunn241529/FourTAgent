import 'dart:convert';
import '../config/api_config.dart';
import 'api_service.dart';

class MusicService {
  static Future<Map<String, dynamic>> generateMusic({
    required String tags,
    String lyrics = "",
    int bpm = 95,
    int duration = 120,
    String language = "vi",
    String keyscale = "E minor",
    int seed = -1,
    String taskType = "text2music",
    String? srcAudio,
    String? referenceAudio,
    double audioCoverStrength = 0.5,
    double repaintingStart = 0.0,
    double repaintingEnd = -1.0,
    double cfgScale = 2.0,
    double temperature = 0.85,
    String outputBitrate = "320k",
  }) async {
    final response = await ApiService.post(
      ApiConfig.musicGenerate,
      body: {
        'tags': tags,
        'lyrics': lyrics,
        'bpm': bpm,
        'duration': duration,
        'language': language,
        'keyscale': keyscale,
        'seed': seed,
        'task_type': taskType,
        if (srcAudio != null) 'src_audio': srcAudio,
        if (referenceAudio != null) 'reference_audio': referenceAudio,
        'audio_cover_strength': audioCoverStrength,
        'repainting_start': repaintingStart,
        'repainting_end': repaintingEnd,
        'cfg_scale': cfgScale,
        'temperature': temperature,
        'top_p': 0.9,
        'top_k': 0,
        'output_bitrate': outputBitrate,
      },
    );
    return ApiService.parseResponse(response);
  }

  static Future<Map<String, dynamic>> uploadAudio(String filePath) async {
    final response = await ApiService.uploadFile(
      ApiConfig.musicUpload,
      filePath,
      fileKey: 'file',
    );
    return ApiService.parseResponse(response);
  }

  static Future<List<String>> getKeyscales() async {
    final response = await ApiService.get(ApiConfig.musicKeyscales);
    final data = ApiService.parseResponse(response);
    return List<String>.from(data['keyscales'] ?? []);
  }

  static Future<List<String>> getLanguages() async {
    final response = await ApiService.get(ApiConfig.musicLanguages);
    final data = ApiService.parseResponse(response);
    return List<String>.from(data['languages'] ?? []);
  }
}
