import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../features/settings/presentation/alert_settings_controller.dart';

/// ✅ Global arka plan müzik servisi — uygulama açıldığı anda çalmaya başlar
final bgMusicServiceProvider = Provider<BgMusicService>((ref) {
  final service = BgMusicService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Mute durumunu takip eden StateProvider
final bgMusicMutedProvider = StateProvider<bool>((ref) => false);

class BgMusicService {
  final Ref _ref;
  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  String? _currentPath;

  BgMusicService(this._ref);

  AudioPlayer get player => _player;

  /// Uygulama başlangıcında çağrılır
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Ayar değişikliklerini dinle (her zaman kayıt ol)
    _ref.listen(alertSettingsProvider, (prev, next) {
      if (prev == null) return;

      // Müzik kapatıldıysa dur
      if (!next.bgMusicEnabled) {
        _player.stop();
        _currentPath = null;
        return;
      }

      // Müzik açıldı veya dosya değiştiyse yeniden yükle
      if (next.bgMusicPath != null &&
          (next.bgMusicPath != _currentPath || !prev.bgMusicEnabled)) {
        _loadAndPlay(next.bgMusicPath!);
      }
    });

    // Mute dinle
    _ref.listen(bgMusicMutedProvider, (prev, next) {
      _player.setVolume(next ? 0.0 : 1.0);
    });

    // İlk açılışta müziği çalmaya başla
    final settings = _ref.read(alertSettingsProvider);
    if (settings.bgMusicEnabled && settings.bgMusicPath != null) {
      await _loadAndPlay(settings.bgMusicPath!);
    }
  }

  Future<void> _loadAndPlay(String path) async {
    try {
      _currentPath = path;
      if (path.startsWith('assets/')) {
        await _player.setAsset(path);
      } else if (kIsWeb) {
        await _player.setUrl(path);
      } else {
        await _player.setFilePath(path);
      }
      _player.setLoopMode(LoopMode.all);

      final isMuted = _ref.read(bgMusicMutedProvider);
      _player.setVolume(isMuted ? 0.0 : 1.0);

      await _player.play();
    } catch (e) {
      debugPrint('BgMusicService hata: $e');
    }
  }

  void toggleMute() {
    final notifier = _ref.read(bgMusicMutedProvider.notifier);
    notifier.state = !notifier.state;
  }

  void dispose() {
    _player.stop();
    _player.dispose();
  }
}
