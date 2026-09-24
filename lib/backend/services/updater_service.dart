/// Descarrega e aplica uma atualização a partir das releases do GitHub.
///
/// Estratégia por plataforma:
///   - **Windows**: descarrega o instalador (`*-windows-x64-setup.exe`), lança-o
///     e termina a app para que os ficheiros possam ser substituídos.
///   - **Linux (AppImage)**: descarrega o novo `.AppImage` e substitui o ficheiro
///     em execução através de um script que espera pelo fim do processo e
///     volta a arrancar.
///   - **Outros** (`.deb`/`.rpm`/instalador): abre o pacote descarregado no
///     gestor do sistema (requer privilégios) e não termina a app.
///
/// A lista de artefactos vem da API de releases do GitHub (só é consultada
/// quando o utilizador pede para atualizar). Sem dependências externas.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../generated/version.dart';
import 'update_service.dart';

/// Endpoint da release mais recente (inclui a lista de artefactos anexados).
const String latestReleaseApiUrl =
    'https://api.github.com/repos/$appRepoOwner/$appRepoName/releases/latest';

/// Um ficheiro anexado a uma release do GitHub.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;
}

/// Fase da aplicação de uma atualização.
enum UpdateInstallPhase {
  /// Nada em curso.
  idle,

  /// A descarregar o artefacto.
  downloading,

  /// Descarregado; a lançar o instalador/substituto.
  installing,

  /// Falhou.
  failed,
}

class UpdateInstallState {
  const UpdateInstallState({
    this.phase = UpdateInstallPhase.idle,
    this.progress = 0,
    this.assetName,
    this.error,
  });

  final UpdateInstallPhase phase;

  /// Progresso do download (0.0–1.0); 0 quando o total é desconhecido.
  final double progress;
  final String? assetName;
  final String? error;

  bool get isBusy =>
      phase == UpdateInstallPhase.downloading ||
      phase == UpdateInstallPhase.installing;
}

/// Descarrega e aplica a atualização mais recente para esta plataforma.
class UpdaterService {
  UpdaterService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static const Duration _timeout = Duration(seconds: 15);
  static const Duration _downloadTimeout = Duration(minutes: 30);

  /// Consulta a release mais recente e devolve o artefacto desta plataforma.
  Future<ReleaseAsset> fetchLatestAsset() async {
    final request = await _client
        .getUrl(Uri.parse(latestReleaseApiUrl))
        .timeout(_timeout);
    request.headers.set(
        HttpHeaders.userAgentHeader, 'VideoSplitview/$appVersion');
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join().timeout(_timeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['assets'] is! List) {
      throw const FormatException('resposta inesperada');
    }

    final assets = <ReleaseAsset>[
      for (final raw in decoded['assets'] as List)
        if (raw is Map &&
            raw['name'] is String &&
            raw['browser_download_url'] is String)
          ReleaseAsset(
            name: raw['name'] as String,
            url: raw['browser_download_url'] as String,
            size: (raw['size'] as num?)?.toInt() ?? 0,
          ),
    ];
    final asset = pickAsset(assets);
    if (asset == null) {
      throw const FormatException('sem artefacto para esta plataforma');
    }
    return asset;
  }

  /// Escolhe o artefacto adequado à plataforma atual.
  ReleaseAsset? pickAsset(List<ReleaseAsset> assets) {
    bool has(ReleaseAsset a, String needle) =>
        a.name.toLowerCase().contains(needle);
    ReleaseAsset? firstWhere(bool Function(ReleaseAsset) test) {
      for (final asset in assets) {
        if (test(asset)) return asset;
      }
      return null;
    }

    if (Platform.isWindows) {
      return firstWhere((a) => has(a, 'windows') && has(a, 'setup')) ??
          firstWhere((a) => a.name.toLowerCase().endsWith('.exe'));
    }
    if (Platform.isLinux) {
      return firstWhere((a) => a.name.toLowerCase().endsWith('.appimage')) ??
          firstWhere((a) => a.name.toLowerCase().endsWith('.deb')) ??
          firstWhere((a) => a.name.toLowerCase().endsWith('.rpm'));
    }
    if (Platform.isMacOS) {
      return firstWhere((a) => a.name.toLowerCase().endsWith('.dmg'));
    }
    return null;
  }

  /// URL direta de um asset (sem API), a partir do número de versão conhecido.
  ///
  /// O padrão de nomes é `video-splitview-v<versão>-<so>-<arch>-<tipo>` e a tag
  /// é `v<versão>` (ver `tool/package.ps1`). Construir o URL evita a API REST do
  /// GitHub — que é limitada a 60 pedidos/hora por IP — porque
  /// `releases/download/...` não é servido pela API.
  ReleaseAsset? _directAsset(String? version) {
    if (version == null) return null;
    final v = version.trim().replaceFirst(RegExp('^v'), '');
    if (v.isEmpty) return null;
    final arch = _archTag();
    if (arch == null) return null;

    final String name;
    if (Platform.isWindows) {
      name = 'video-splitview-v$v-windows-$arch-setup.exe';
    } else if (Platform.isLinux) {
      name = 'video-splitview-v$v-linux-$arch.AppImage';
    } else {
      return null;
    }
    return ReleaseAsset(
      name: name,
      url: '$appReleasesUrl/download/v$v/$name',
      size: 0,
    );
  }

  /// Arquitetura atual no sufixo usado nos nomes dos artefactos, ou `null`.
  String? _archTag() => switch (Abi.current()) {
        Abi.windowsX64 || Abi.linuxX64 => 'x64',
        Abi.windowsArm64 || Abi.linuxArm64 => 'arm64',
        _ => null,
      };

  /// Descarrega e aplica a atualização, reportando o estado via [onState].
  ///
  /// Usa primeiro o URL direto (sem API) quando [version] é conhecida; se essa
  /// descarga falhar, recorre à lista de artefactos da API (último recurso).
  Future<void> install({
    required void Function(UpdateInstallState) onState,
    String? version,
  }) async {
    final direct = _directAsset(version);
    if (direct != null) {
      try {
        await _downloadAndApply(direct, onState);
        return;
      } catch (_) {
        // URL direta indisponível (nome/tag diferentes): cai para a API.
      }
    }
    await _downloadAndApply(await fetchLatestAsset(), onState);
  }

  Future<void> _downloadAndApply(
    ReleaseAsset asset,
    void Function(UpdateInstallState) onState,
  ) async {
    onState(UpdateInstallState(
      phase: UpdateInstallPhase.downloading,
      assetName: asset.name,
    ));

    final file = await _download(asset, onState: (received, total) {
      onState(UpdateInstallState(
        phase: UpdateInstallPhase.downloading,
        progress: total > 0 ? (received / total).clamp(0.0, 1.0) : 0,
        assetName: asset.name,
      ));
    });

    onState(UpdateInstallState(
      phase: UpdateInstallPhase.installing,
      progress: 1,
      assetName: asset.name,
    ));
    await _apply(asset, file);
    // Em Windows/AppImage `_apply` termina a app antes daqui; nos pacotes
    // (.deb/.rpm) apenas abrimos o ficheiro, por isso limpamos o estado.
    onState(const UpdateInstallState());
  }

  Future<File> _download(
    ReleaseAsset asset, {
    required void Function(int received, int total) onState,
  }) async {
    final dir = await Directory.systemTemp.createTemp('video-splitview-update');
    final safeName = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');

    final request = await _client.getUrl(Uri.parse(asset.url)).timeout(_timeout);
    request.headers.set(
        HttpHeaders.userAgentHeader, 'VideoSplitview/$appVersion');
    request.followRedirects = true;

    final response = await request.close().timeout(_downloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}');
    }
    final total = response.contentLength > 0 ? response.contentLength : asset.size;

    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(_downloadTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onState(received, total);
      }
    } finally {
      await sink.close();
    }
    return file;
  }

  Future<void> _apply(ReleaseAsset asset, File file) async {
    if (Platform.isWindows) {
      await Process.start(
        file.path,
        const ['/CLOSEAPPLICATIONS', '/NORESTART'],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }

    final appImagePath = Platform.environment['APPIMAGE'];
    if (Platform.isLinux &&
        appImagePath != null &&
        asset.name.toLowerCase().endsWith('.appimage')) {
      await _selfReplaceAppImage(file, appImagePath);
      return;
    }

    // .deb/.rpm/instalador: abre o pacote no gestor do sistema.
    await openExternalUrl(file.path);
  }

  /// Substitui o AppImage em execução por [file] após a app terminar.
  Future<void> _selfReplaceAppImage(File file, String appImagePath) async {
    final script = File(
      '${file.parent.path}${Platform.pathSeparator}apply-update.sh',
    );
    final content = '''
#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.4; done
mv -f "${file.path}" "$appImagePath"
chmod +x "$appImagePath"
"$appImagePath" >/dev/null 2>&1 &
''';
    await script.writeAsString(content);
    await Process.run('chmod', ['+x', script.path]);
    await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
    exit(0);
  }

  void dispose() => _client.close(force: true);
}
