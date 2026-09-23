/// Verificação de atualizações via GitHub Releases + abertura de URLs.
///
/// Sem dependências externas: usa `dart:io` (HttpClient) para consultar a API
/// pública de releases e o gestor de URLs do sistema para abrir a página de
/// download. Não descarrega nem instala nada — apenas informa e liga.
library;

import 'dart:convert';
import 'dart:io';

import '../generated/version.dart';

/// Repositório oficial (usado na verificação e nos links de download).
const String appRepoOwner = 'giordanidev';
const String appRepoName = 'video-splitview';
const String appRepoUrl = 'https://github.com/$appRepoOwner/$appRepoName';
const String appReleasesUrl = '$appRepoUrl/releases';

const String _latestReleaseApiUrl =
    'https://api.github.com/repos/$appRepoOwner/$appRepoName/releases/latest';

/// Resultado de uma verificação de atualização.
enum UpdatePhase {
  /// Já está na versão mais recente publicada.
  upToDate,

  /// Existe uma versão publicada mais recente.
  available,

  /// Não foi possível verificar (sem rede, repositório privado, sem releases…).
  failed,
}

class UpdateCheck {
  const UpdateCheck({
    required this.phase,
    required this.currentVersion,
    this.latestVersion,
    this.releaseUrl,
    this.error,
  });

  final UpdatePhase phase;
  final String currentVersion;
  final String? latestVersion;

  /// URL da release mais recente (ou da página de releases, em fallback).
  final String? releaseUrl;

  /// Detalhe do erro quando [phase] é [UpdatePhase.failed].
  final String? error;

  bool get hasUpdate => phase == UpdatePhase.available;

  static UpdateCheck failed(String currentVersion, [String? error]) => UpdateCheck(
        phase: UpdatePhase.failed,
        currentVersion: currentVersion,
        error: error,
      );
}

/// Compara duas versões no estilo semver (`0.0.48` > `0.0.47`).
///
/// Segmentos não numéricos contam como 0. Devolve `>0` se [a] for mais recente.
int compareVersions(String a, String b) {
  final pa = _versionParts(a);
  final pb = _versionParts(b);
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _versionParts(String value) {
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(value);
  if (match == null) return const [];
  return [
    for (final part in match.group(0)!.split('.')) int.tryParse(part) ?? 0,
  ];
}

/// Normaliza uma tag do GitHub (`v0.0.48`, `release-0.0.48`) para `0.0.48`.
String? normalizeVersion(String? tag) {
  if (tag == null) return null;
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(tag);
  return match?.group(0);
}

/// Consulta a última release publicada no GitHub.
class UpdateService {
  UpdateService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static const Duration _timeout = Duration(seconds: 8);

  Future<UpdateCheck> check() async {
    final current = appVersion;
    try {
      final request = await _client
          .getUrl(Uri.parse(_latestReleaseApiUrl))
          .timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'VideoSplitview/$current');
      request.headers.set(
          HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheck.failed(current, 'HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return UpdateCheck.failed(current, 'resposta inesperada');
      }

      final latest = normalizeVersion(decoded['tag_name']?.toString());
      if (latest == null) {
        return UpdateCheck.failed(current, 'tag sem versão');
      }

      final htmlUrl = decoded['html_url']?.toString();
      return UpdateCheck(
        phase: compareVersions(latest, current) > 0
            ? UpdatePhase.available
            : UpdatePhase.upToDate,
        currentVersion: current,
        latestVersion: latest,
        releaseUrl: htmlUrl ?? appReleasesUrl,
      );
    } catch (error) {
      return UpdateCheck.failed(current, error.toString());
    }
  }

  void dispose() => _client.close(force: true);
}

/// Abre um URL no navegador/gestor predefinido do sistema.
///
/// Devolve `true` se o comando foi lançado sem erro. Nunca lança.
Future<bool> openExternalUrl(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
    return true;
  } catch (_) {
    return false;
  }
}
