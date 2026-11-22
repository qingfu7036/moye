import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Throw-away JSON persistence for the Phase 0 spike only.
///
/// This is intentionally small. It is NOT the V1 database. Writes go through a
/// temp file and retain a last-known-good `.bak` so an interrupted process does
/// not truncate the only copy. Phase 1 replaces this with SQLite transactions.
class Phase0Store {
  Phase0Store._();

  static final Phase0Store instance = Phase0Store._();

  Future<Directory> _directory() async {
    final directory = await getApplicationSupportDirectory();
    final phase0 =
        Directory('${directory.path}${Platform.pathSeparator}phase0');
    if (!await phase0.exists()) await phase0.create(recursive: true);
    return phase0;
  }

  Future<File> _file(String name) async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  Future<Object?> readJson(String name) async {
    final file = await _file(name);
    if (await file.exists()) {
      try {
        return jsonDecode(await file.readAsString());
      } catch (_) {
        // Fall through to the last-known-good copy.
      }
    }
    final backup = File('${file.path}.bak');
    if (await backup.exists()) {
      try {
        return jsonDecode(await backup.readAsString());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> writeJson(String name, Object? value) async {
    final file = await _file(name);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );

    if (await file.exists()) {
      // Only retain a backup if the current file is valid JSON. Never copy a
      // corrupt file over the last-known-good copy.
      var valid = false;
      try {
        jsonDecode(await file.readAsString());
        valid = true;
      } catch (_) {
        valid = false;
      }
      if (valid) {
        await file.copy('${file.path}.bak');
      }
      await file.delete();
    }
    await temp.rename(file.path);
  }
}
