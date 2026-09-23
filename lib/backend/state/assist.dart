/// Estado do modal de assistência de reprodução.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/playback_bridge.dart';

class AssistController extends ChangeNotifier {
  bool open = false;
  Side side = Side.a;
  String? path;
  String? fileName;
  String message = '';
  String? code;
  EngineInfo? engine;
  bool busy = false;
  String? feedback;

  void show(Side side, String? path, String message) {
    open = true;
    this.side = side;
    this.path = path;
    fileName = path == null ? null : _fileName(path);
    this.message = message;
    code = null;
    engine = null;
    feedback = null;
    busy = false;
    notifyListeners();
  }

  void close() {
    open = false;
    notifyListeners();
  }

  Future<void> verify(PlaybackBridge bridge) async {
    busy = true;
    notifyListeners();
    try {
      engine = await bridge.engineInfo();
      feedback = engine!.message;
    } catch (error) {
      feedback = '$error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> copyDiagnostic(PlaybackBridge bridge, Strings strings) async {
    busy = true;
    notifyListeners();
    try {
      engine = await bridge.engineInfo();
      await Clipboard.setData(
        ClipboardData(text: _buildDiagnostic(engine!, strings)),
      );
      feedback = strings.copyDiagnostic;
    } catch (error) {
      feedback = '$error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _buildDiagnostic(EngineInfo engine, Strings s) {
    final sideLabel = sideLabelOf(side, s);
    return [
      s.diagTitle,
      '${s.diagDate}: ${DateTime.now().toIso8601String()}',
      '${s.diagSide}: $sideLabel',
      '${s.diagFile}: ${fileName ?? s.diagUnknown}',
      '${s.diagPath}: ${path ?? s.diagUnknown}',
      '${s.diagCode}: ${code ?? s.diagNotAvailable}',
      '${s.diagEngineMessage}: $message',
      '${s.diagEngineFound}: ${engine.found ? s.diagYes : s.diagNo}',
      '${s.diagEngineBundled}: ${engine.bundled ? s.diagYes : s.diagNo}',
      '${s.diagEnginePath}: ${engine.path ?? s.diagNotAvailable}',
      '${s.diagEngineVersion}: ${engine.version ?? s.diagNotAvailable}',
      '${s.diagEngineState}: ${engine.ok ? s.diagOk : s.diagUnavailable}',
    ].join('\n');
  }

  static String _fileName(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : path;
  }
}
