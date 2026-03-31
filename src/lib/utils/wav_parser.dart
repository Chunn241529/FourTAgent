import 'dart:typed_data';

class WavParser {
  // Extracts amplitude data from WAV bytes for visualization
  // Returns a list of normalized amplitudes (0.0 to 1.0)
  static List<double> getAmplitudes(Uint8List wavBytes, {int samples = 100}) {
    // 1. Basic WAV Header Parsing to find data chunk
    // WAV header is usually 44 bytes, but we should scan for 'data' marker
    int dataOffset = 44; // Default if not found
    
    // Simple scan for 'data'
    for (int i = 0; i < wavBytes.length - 4; i++) {
      if (String.fromCharCodes(wavBytes.sublist(i, i + 4)) == 'data') {
        dataOffset = i + 8; // 'data' + 4 bytes size
        break;
      }
    }
    
    if (dataOffset >= wavBytes.length) return List.filled(samples, 0.0);

    final rawData = wavBytes.sublist(dataOffset);
    final int byteDepth = 2; // Assuming 16-bit PCM for now (standard)
    final int totalSamples = rawData.length ~/ byteDepth;
    
    // 2. Downsample
    final int step = (totalSamples / samples).floor();
    if (step < 1) return List.filled(samples, 0.0);

    List<double> amplitudes = [];
    
    for (int i = 0; i < samples; i++) {
        int index = i * step * byteDepth;
        if (index + 1 >= rawData.length) break;
        
        // Read 16-bit signed integer (Little Endian)
        int sample = rawData[index] | (rawData[index + 1] << 8);
        if (sample > 32767) sample -= 65536; // Two's complement
        
        // Normalize to 0.0 - 1.0
        double normalized = sample.abs() / 32768.0;
        amplitudes.add(normalized);
    }
    
    return amplitudes;
  }
}
