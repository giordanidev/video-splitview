/// Provider Riverpod da verificação de atualizações.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
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
  Future<void> recheck() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(updateServiceProvider).check(),
    );
  }
}
