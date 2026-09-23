/// Wrapper de um lado de reprodução: `Player` + `VideoController` do media_kit.
library;

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/models.dart';

class MpvSide {
  MpvSide(this.side);

  final Side side;
  late final Player player;
  late final VideoController controller;

  NativePlayer? get native {
    final platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> init() async {
    player = Player();
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        vo: 'libmpv',
        // Windows: o media_kit só suporta modos copy-back (ver docs).
        hwdec: 'auto-copy',
      ),
    );
  }

  Future<void> dispose() async {
    await player.dispose();
  }
}
