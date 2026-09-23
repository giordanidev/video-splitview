/// Persistência portátil: JSON na pasta do executável.
///
/// Assim, apagar a pasta da app remove também as definições — sem vestígios
/// em AppData / SharedPreferences.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Pasta do executável (release) ou do runner (debug).
Directory portableAppDir() {
  final exe = File(Platform.resolvedExecutable);
  return exe.parent;
}

File portableFile(String name) =>
    File(p.join(portableAppDir().path, name));

/// Lê um mapa JSON do ficheiro; `null` se ausente ou inválido.
Map<String, dynamic>? readJsonMap(File file) {
  try {
    if (!file.existsSync()) return null;
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {}
  return null;
}

/// Grava um mapa como JSON (cria a pasta se necessário).
Future<void> writeJsonMap(File file, Map<String, Object?> map) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(map),
    flush: true,
  );
}
