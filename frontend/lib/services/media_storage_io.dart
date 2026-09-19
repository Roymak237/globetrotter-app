import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String> recordingPath() async =>
    '${(await getTemporaryDirectory()).path}/chat_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
Future<Uint8List> readRecording(String path) async {
  final file = File(path);
  if (await file.length() > 10 * 1024 * 1024) {
    throw Exception('Recording must be 10 MB or smaller.');
  }
  return file.readAsBytes();
}

Future<void> removeRecording(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
