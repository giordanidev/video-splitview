/// Seleção de ficheiros de vídeo.
library;

import 'package:file_selector/file_selector.dart';

import '../i18n/strings.dart';

const List<String> videoExtensions = [
  'mp4',
  'm4v',
  'webm',
  'mkv',
  'mov',
  'avi',
  'ogv',
  'ogg',
  'ts',
  'mts',
  'm2ts',
  '3gp',
  '3g2',
  'flv',
  'wmv',
  'asf',
  'mpg',
  'mpeg',
  'm2v',
  'vob',
  'mxf',
  'rm',
  'rmvb',
  'divx',
  'f4v',
  'bik',
];

Future<List<String>> pickVideoPaths(Strings strings) async {
  final videoGroup = XTypeGroup(label: strings.filterVideo, extensions: videoExtensions);
  final allGroup = XTypeGroup(label: strings.filterAll);
  final files = await openFiles(acceptedTypeGroups: [videoGroup, allGroup]);
  return files.map((file) => file.path).toList(growable: false);
}

String fileNameFromPath(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : path;
}
