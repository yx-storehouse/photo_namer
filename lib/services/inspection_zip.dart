import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';


Future<Map<String, dynamic>> createInspectionZipInBackground(
  Map<String, dynamic> request,
) async {
  final photoPaths = List<String>.from(
    request['photoPaths'] as List<dynamic>? ?? const <dynamic>[],
  );
  final zipPath = (request['zipPath'] as String?)?.trim() ?? '';
  if (zipPath.isEmpty) {
    throw ArgumentError('zipPath is required');
  }

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  var addedCount = 0;
  try {
    for (final photoPath in photoPaths) {
      final file = File(photoPath);
      if (!file.existsSync()) {
        continue;
      }
      encoder.addFileSync(file);
      addedCount++;
    }
  } finally {
    encoder.closeSync();
  }

  return <String, dynamic>{'zipPath': zipPath, 'addedCount': addedCount};
}

