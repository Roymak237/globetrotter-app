import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/chat.dart';
import '../utils/constants.dart';
import 'media_storage_stub.dart' if (dart.library.io) 'media_storage_io.dart'
    as storage;

/// Owns its HTTP client. Close when the owning screen is disposed.
/// Bearer tokens are never placed in media URLs or sent to third-party hosts.
class MediaService {
  static const maxBytes = 10 * 1024 * 1024;
  static const types = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'pdf': 'application/pdf',
  };
  final http.Client _client = http.Client();
  bool _closed = false;

  void dispose() {
    _closed = true;
    _client.close();
  }

  Uri _mediaUri(String path) {
    final base = Uri.parse(AppConstants.backendBaseUrl);
    final uri = base.resolve(path);
    if (uri.origin != base.origin ||
        !uri.path.startsWith('${AppConstants.apiPrefix}/media/')) {
      throw const FormatException('Untrusted media URL');
    }
    return uri;
  }

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 413)
      throw Exception('File must be 10 MB or smaller.');
    String message = 'Media request failed (${response.statusCode}).';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null)
        message = body['error'].toString();
    } on FormatException {/* The proxy may return an HTML error page. */}
    throw Exception(message);
  }

  Future<ChatAttachment?> pickAndUpload(String token,
      {bool imageOnly = false}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: imageOnly
          ? ['jpg', 'jpeg', 'png', 'gif', 'webp']
          : types.keys.toList(),
    );
    if (file == null || _closed) return null;
    final mime = types[file.extension?.toLowerCase()];
    if (mime == null) {
      throw Exception('Choose a photo, video, PDF or audio file.');
    }
    // Streaming rather than asking for the whole file up front means an
    // oversized pick is rejected part-way instead of after it has all been
    // pulled into memory.
    final bytes = await _readLimited(file.readAsByteStream());
    if (_closed) return null;
    _validateSize(bytes.length);
    return upload(token, bytes, file.name, mime);
  }

  Future<Uint8List> _readLimited(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (_closed) throw Exception('Upload cancelled.');
      if (builder.length + chunk.length > maxBytes) {
        throw Exception('File must be 10 MB or smaller.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _validateSize(int size) {
    if (size <= 0) throw Exception('The file is empty.');
    if (size > maxBytes) throw Exception('File must be 10 MB or smaller.');
  }

  Future<ChatAttachment> upload(
      String token, Uint8List bytes, String filename, String contentType,
      {int durationMs = 0}) async {
    _validateSize(bytes.length);
    if (_closed) throw Exception('Upload cancelled.');
    final request = http.MultipartRequest(
        'POST',
        Uri.parse(
            '${AppConstants.backendBaseUrl}${AppConstants.apiPrefix}/media'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: filename, contentType: MediaType.parse(contentType)));
    final response = await (() async =>
            http.Response.fromStream(await _client.send(request)))()
        .timeout(const Duration(seconds: 90));
    _check(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _mediaUri(json['url'] as String);
    return ChatAttachment.fromJson({...json, 'duration_ms': durationMs});
  }

  Future<Uint8List> fetchBytes(String token, String url) async {
    final request = http.Request('GET', _mediaUri(url));
    request.headers['Authorization'] = 'Bearer $token';
    return (() async {
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        _check(await http.Response.fromStream(response));
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        throw Exception('Media exceeds the 10 MB limit.');
      }
      return _readLimited(response.stream);
    })()
        .timeout(AppConstants.apiTimeout);
  }

  /// Parent backend contract: POST /api/media/<id>/ticket with bearer auth,
  /// response {url: "/api/media/<id>?ticket=...", expires_in: 300}.
  /// The ticket must permit range requests/repeated reads for its lifetime.
  Future<Uri> playbackTicket(String token, String url) async {
    final media = _mediaUri(url);
    final response = await _client
        .post(media.replace(path: '${media.path}/ticket', query: ''), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(AppConstants.apiTimeout);
    _check(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _mediaUri(data['url'] as String);
  }

  Future<String> recordingPath() => storage.recordingPath();
  Future<Uint8List> readRecording(String path) => storage.readRecording(path);
  Future<void> removeRecording(String path) => storage.removeRecording(path);
}
