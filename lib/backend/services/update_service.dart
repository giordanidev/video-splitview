/// Verificação de atualizações via `version.json` + abertura de URLs.
///
/// Sem dependências externas: usa `dart:io` (HttpClient). A versão mais recente
/// é lida de várias fontes por ordem de prioridade (a primeira que responder
/// vence), de modo que a verificação continua a funcionar mesmo quando uma está
/// indisponível:
///   1. `releases/latest/download/version.json` — asset da release mais recente.
///      O GitHub redireciona este URL sem chamar a API REST, logo não está
///      sujeito ao limite de 60 pedidos/hora por IP (a fonte preferida).
///   2. jsDelivr (CDN) a servir o `version.json` do ramo `main`.
///   3. raw.githubusercontent.com do ramo `main`.
///   4. API REST de releases do GitHub (último recurso, limitada por IP).
///
/// Não descarrega nem instala nada — apenas informa e abre a página de releases.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../generated/version.dart';

/// Repositório oficial (usado na verificação e nos links de download).
const String appRepoOwner = 'giordanidev';
const String appRepoName = 'video-splitview';
const String appRepoUrl = 'https://github.com/$appRepoOwner/$appRepoName';
const String appReleasesUrl = '$appRepoUrl/releases';

/// Asset da release mais recente: o GitHub redireciona sem chamar a API REST,
/// pelo que não está sujeito ao limite de pedidos por IP.
const String _releaseAssetUrl =
    '$appRepoUrl/releases/latest/download/version.json';

/// Mesmo ficheiro publicado no ramo `main`, servido por CDN e, em seguida, cru.
const List<String> _versionJsonUrls = [
  'https://cdn.jsdelivr.net/gh/$appRepoOwner/$appRepoName@main/version.json',
  'https://raw.githubusercontent.com/$appRepoOwner/$appRepoName/main/version.json',
];

/// Último recurso: a API REST de releases (limitada a 60 pedidos/hora por IP).
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

/// Lê a versão de um payload JSON (`version` no `version.json`, `tag_name` na API).
String? _versionFromPayload(Object? data) {
  if (data is! Map) return null;
  final raw = data['version'] ?? data['tag_name'];
  return normalizeVersion(raw?.toString());
}

/// Lê o URL de release de um payload JSON, se presente.
String? _releaseUrlFromPayload(Object? data) {
  if (data is! Map) return null;
  final raw = data['releaseUrl'] ?? data['html_url'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  return null;
}

/// Uma versão obtida de uma fonte, com o respetivo URL de release (opcional).
class _SourceResult {
  const _SourceResult(this.version, this.releaseUrl);

  final String version;
  final String? releaseUrl;
}

/// Consulta a última versão publicada, com fallback entre várias fontes.
class UpdateService {
  UpdateService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static const Duration _timeout = Duration(seconds: 8);

  UpdateCheck? _cached;
  Future<UpdateCheck>? _inFlight;

  /// Devolve o resultado do cache quando disponível; caso contrário consulta.
  ///
  /// Com [force] a true ignora o cache (botão "Verificar atualizações").
  /// Chamadas concorrentes partilham a mesma consulta em curso.
  Future<UpdateCheck> check({bool force = false}) {
    if (!force && _cached != null && _cached!.phase != UpdatePhase.failed) {
      return Future.value(_cached!);
    }
    final pending = _inFlight;
    if (pending != null) return pending;

    final future = _runCheck();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<UpdateCheck> _runCheck() async {
    final current = appVersion;
    var lastError = 'sem resposta';
    for (final url in [
      _releaseAssetUrl,
      ..._versionJsonUrls,
      _latestReleaseApiUrl,
    ]) {
      final result = await _fetchVersion(url);
      if (result != null) {
        final check = UpdateCheck(
          phase: compareVersions(result.version, current) > 0
              ? UpdatePhase.available
              : UpdatePhase.upToDate,
          currentVersion: current,
          latestVersion: result.version,
          releaseUrl: result.releaseUrl ?? appReleasesUrl,
        );
        _cached = check;
        return check;
      }
      lastError = 'sem versão em $url';
    }
    // Falhas não são cacheadas: a próxima verificação volta a tentar.
    return UpdateCheck.failed(current, lastError);
  }

  /// Procura uma versão num URL, devolvendo `null` em qualquer falha.
  Future<_SourceResult?> _fetchVersion(String url) async {
    try {
      final request = await _client
          .getUrl(Uri.parse(url))
          .timeout(_timeout);
      request.headers.set(
          HttpHeaders.userAgentHeader, 'VideoSplitview/$appVersion');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        // Consome o corpo para libertar a ligação antes de desistir.
        await response.drain<void>();
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      final decoded = jsonDecode(body);
      final version = _versionFromPayload(decoded);
      if (version == null) return null;
      return _SourceResult(version, _releaseUrlFromPayload(decoded));
    } catch (_) {
      return null;
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
