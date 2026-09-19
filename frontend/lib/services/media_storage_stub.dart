import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<String> recordingPath() async => 'chat_voice.webm';
Future<Uint8List> readRecording(String path) async {
  // record_web returns a browser-local blob URL, never an API URL.
  if (!path.startsWith('blob:')) throw Exception('Invalid recording URL.');
  final response =
      await http.get(Uri.parse(path)).timeout(const Duration(seconds: 30));
  if (response.bodyBytes.length > 10 * 1024 * 1024) {
    throw Exception('Recording must be 10 MB or smaller.');
  }
  return response.bodyBytes;
}

Future<void> removeRecording(String path) async {
  // Browser blob lifetime is managed by record_web on cancel/dispose.
}
