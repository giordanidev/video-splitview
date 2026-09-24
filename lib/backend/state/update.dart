/// Provider Riverpod da verificação de atualizações.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';
import '../services/updater_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.dispose);
  return service;
});

final updaterServiceProvider = Provider<UpdaterService>((ref) {
  final service = UpdaterService();
  ref.onDispose(service.dispose);
  return service;
});

/// Estado da verificação: `loading` enquanto consulta, depois o resultado.
final updateProvider =
    AsyncNotifierProvider<UpdateController, UpdateCheck>(UpdateController.new);

class UpdateController extends AsyncNotifier<UpdateCheck> {
  @override
  Future<UpdateCheck> build() => ref.watch(updateServiceProvider).check();

  /// Repete a verificação (botão "Verificar atualizações").
  ///
  /// Força uma consulta nova, ignorando o resultado em cache.
  Future<void> recheck() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(updateServiceProvider).check(force: true),
    );
  }
}

/// Estado da aplicação (download + instalação) de uma atualização.
final updateInstallProvider =
    NotifierProvider<UpdateInstallController, UpdateInstallState>(
        UpdateInstallController.new);

class UpdateInstallController extends Notifier<UpdateInstallState> {
  @override
  UpdateInstallState build() => const UpdateInstallState();

  /// Descarrega e aplica a atualização mais recente (botão "Atualizar").
  Future<void> install() async {
    if (state.isBusy) return;
    state = const UpdateInstallState(phase: UpdateInstallPhase.downloading);
    try {
      final version = ref.read(updateProvider).value?.latestVersion;
      await ref.read(updaterServiceProvider).install(
            version: version,
            onState: (next) => state = next,
          );
    } catch (error) {
      state = UpdateInstallState(
        phase: UpdateInstallPhase.failed,
        error: error.toString(),
      );
    }
  }
}
