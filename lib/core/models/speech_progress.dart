import 'dart:convert';

class SpeechProgress {
  const SpeechProgress({
    required this.bookId,
    required this.anchorJson,
    required this.percent,
    required this.mode,
    required this.updatedAt,
  });

  final String bookId;
  final String anchorJson;
  final double percent;
  final String mode;
  final DateTime updatedAt;

  Map<String, dynamic> get anchor {
    try {
      final decoded = jsonDecode(anchorJson);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
