import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A picked file exposed without leaking the file_picker package into the UI.
///
/// The stream works for desktop paths and Android SAF content URIs.
class PickedBookSource {
  const PickedBookSource({
    required this.name,
    required this.openStream,
  });

  final String name;
  final Stream<List<int>> Function() openStream;
}

abstract interface class BookPicker {
  Future<List<PickedBookSource>> pickBooks();
}

class SystemBookPicker implements BookPicker {
  const SystemBookPicker();

  @override
  Future<List<PickedBookSource>> pickBooks() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    return [
      for (final file in files)
        PickedBookSource(
          name: file.name,
          openStream: () => file.readAsByteStream(),
        ),
    ];
  }
}

final bookPickerProvider = Provider<BookPicker>((ref) {
  return const SystemBookPicker();
});
