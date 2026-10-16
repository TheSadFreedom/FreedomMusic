import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List?> pickImageBytes() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final bytes = result.files.first.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  return bytes;
}
