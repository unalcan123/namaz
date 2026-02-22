import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // ✅ gerekli
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/presentation/alert_settings_controller.dart';

class SlaytWidget extends ConsumerStatefulWidget {
  final double height;
  final int currentIndex;
  final Function(int)? onPageChanged;
  final List<String>? userImages;

  final bool hideOnPortrait;

  /// Tam ekran butonu gösterilsin mi?
  final bool showFullscreenButton;

  const SlaytWidget({
    super.key,
    this.userImages,
    required this.height,
    this.currentIndex = 0,
    this.onPageChanged,
    this.hideOnPortrait = false,
    this.showFullscreenButton = true,
  });

  @override
  ConsumerState<SlaytWidget> createState() => _SlaytWidgetState();
}

class _SlaytWidgetState extends ConsumerState<SlaytWidget> {
  List<String> assetImages = [];
  List<String> userImages = [];
  bool isLoading = true;

  int _initialPage = 0;
  bool _initialPageLoaded = false;

  // ✅ Web storage (IndexedDB) - Hive box
  Box? get _webBox {
    const boxName = 'web_user_images';
    return Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;
  }

  final CarouselSliderController _carouselController = CarouselSliderController();

  // ✅ listenManual subscription — dispose'da kapatılacak
  ProviderSubscription? _settingsSub;

  // ✅ Aktif image stream listener (eski listener temizliği için)
  ImageStream? _activeStream;
  ImageStreamListener? _activeListener;

  String _getEffectiveCategory(String category) {
    if (category == 'Kullanıcı Foto') return 'user';
    if (category == 'Genel Resimler') return 'resim';
    if (category == 'Hadis-i Şerifler') return 'hadis';
    if (category == 'Dualar') return 'dua';
    if (category == 'Besmele') return 'besmele';
    if (category == 'Namaz Bilgileri') return 'namaz';
    if (category == 'Ramazan') return 'ramazan';
    return category;
  }

  String _webKey(String category) {
    final cat = _getEffectiveCategory(category);
    return 'userImages_$cat';
  }

  /// ✅ WEB: Kaydet (bytes -> base64 list)
  Future<void> addUserImagesWeb(String category) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final key = _webKey(category);
    final box = _webBox;
    if (box == null) return;
    final List existing = (box.get(key) as List?) ?? [];

    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      existing.add(base64Encode(bytes));
    }

    await box.put(key, existing);

    // ✅ slaytı güncelle
    await _loadUserImages(category);

    // ✅ başka widget'lar da dinliyorsa tetikle (opsiyonel ama iyi)
    ref.read(alertSettingsProvider.notifier).triggerRefresh();
  }

  /// ✅ WEB: Oku
  Future<List<String>> _loadUserImagesWeb(String category) async {
    final box = _webBox;
    if (box == null) return [];
    final key = _webKey(category);
    final List list = (box.get(key) as List?) ?? [];
    return list.map((e) => 'base64:$e').cast<String>().toList();
  }

  String _pageKey(String category) {
    final cat = _getEffectiveCategory(category);
    return 'slayt_last_index_$cat';
  }

  Future<void> _loadLastPage(String category) async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getInt(_pageKey(category)) ?? 0;

    if (!mounted) return;
    setState(() {
      _initialPage = saved;
      _initialPageLoaded = true;
    });
  }

  Future<void> _saveLastPage(String category, int index) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_pageKey(category), index);
  }

  List<String> _getAllImages(String category) {
    if (category == 'Kullanıcı Foto') return userImages;
    return [...assetImages, ...userImages];
  }

  @override
  void initState() {
    super.initState();

    // ✅ İlk yükleme
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final category = ref.read(alertSettingsProvider).slideCategory;
      await _loadLastPage(category);
      await _loadAllImages(category);
    });

    // ✅ Ayar değişince yeniden yükle (subscription saklanıyor)
    _settingsSub = ref.listenManual(alertSettingsProvider, (prev, next) async {
      if (prev == null) return;

      if (prev.slideCategory != next.slideCategory ||
          prev.lastUpdate != next.lastUpdate) {
        setState(() => _initialPageLoaded = false);
        await _loadLastPage(next.slideCategory);
        await _loadAllImages(next.slideCategory);
      }
    });
  }

  @override
  void dispose() {
    _settingsSub?.close();
    // ✅ Aktif image stream listener'ını temizle
    if (_activeStream != null && _activeListener != null) {
      _activeStream!.removeListener(_activeListener!);
    }
    super.dispose();
  }

  Future<void> _loadAllImages(String category) async {
    if (!mounted) return;
    setState(() => isLoading = true);

    if (category != 'Kullanıcı Foto') {
      await _loadAssetImages(category);
    } else {
      assetImages = [];
    }

    await _loadUserImages(category);

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadAssetImages(String category) async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final cat = _getEffectiveCategory(category).toLowerCase();
      final patternA = 'assets/resim/$cat/';
      final patternB = 'resim/$cat/';

      final images = manifestMap.keys.where((key) {
        final k = key.toLowerCase();
        final okFolder = k.contains(patternA) || k.contains(patternB);
        final okExt = k.endsWith('.jpg') ||
            k.endsWith('.jpeg') ||
            k.endsWith('.png') ||
            k.endsWith('.webp');
        return okFolder && okExt;
      }).toList();

      if (mounted) setState(() => assetImages = images);
    } catch (e) {
      debugPrint("Asset yükleme hatası: $e");
    }
  }

  Future<void> _loadUserImages(String category) async {
    try {
      if (kIsWeb) {
        final imgs = await _loadUserImagesWeb(category);
        if (mounted) setState(() => userImages = imgs);
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();
      final cat = _getEffectiveCategory(category);
      final categoryDir = Directory('${appDir.path}/userImages/$cat');

      if (await categoryDir.exists()) {
        final imageFiles = categoryDir
            .listSync()
            .where((f) {
          final p = f.path.toLowerCase();
          return p.endsWith('.jpg') ||
              p.endsWith('.jpeg') ||
              p.endsWith('.png') ||
              p.endsWith('.webp');
        })
            .map((f) => f.path)
            .toList();

        if (mounted) setState(() => userImages = imageFiles);
      } else {
        if (mounted) setState(() => userImages = []);
      }
    } catch (e) {
      debugPrint("Kullanıcı resimleri yükleme hatası: $e");
    }
  }

  ImageProvider _getImageProvider(String path) {
    final p = path.toLowerCase();

    if (p.startsWith('base64:')) {
      final b64 = path.substring('base64:'.length);
      final bytes = base64Decode(b64);
      return MemoryImage(Uint8List.fromList(bytes));
    }

    final isAsset = p.startsWith('assets/') ||
        p.startsWith('resim/') ||
        p.contains('/resim/') ||
        p.startsWith('images/') ||
        p.contains('/images/');

    if (isAsset) return AssetImage(path);

    if (kIsWeb) return NetworkImage(path);
    return FileImage(File(path));
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Portrait’te slaytı gizle (geri sayım tek başına kalsın)
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    if (widget.hideOnPortrait && isPortrait) {
      return const SizedBox.shrink();
    }

    final settings = ref.watch(alertSettingsProvider);
    final allImages = _getAllImages(settings.slideCategory);

    return LayoutBuilder(
      builder: (context, constraints) {
        final actualHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (widget.height > 0 ? widget.height : MediaQuery.sizeOf(context).height);

        final safeInitialPage =
        (allImages.isNotEmpty && _initialPage < allImages.length) ? _initialPage : 0;

        final Widget content;

        if (isLoading || !_initialPageLoaded) {
          content = const Center(
              child: CircularProgressIndicator(color: Colors.white));
        } else if (allImages.isNotEmpty) {
          content = CarouselSlider.builder(
            key: ValueKey(
              '${settings.slideCategory}_${settings.lastUpdate}_${allImages.length}_$safeInitialPage',
            ),
            carouselController: _carouselController,
            itemCount: allImages.length,
            itemBuilder: (context, index, realIdx) {
              final imagePath = allImages[index];
              return ClipRect(
                child: SizedBox(
                  width: double.infinity,
                  height: actualHeight,
                  child: _SmartFittedImage(
                    provider: _getImageProvider(imagePath),
                  ),
                ),
              );
            },
            options: CarouselOptions(
              height: actualHeight,
              viewportFraction: 1.0,
              initialPage: safeInitialPage,
              enlargeCenterPage: false,
              autoPlay: allImages.length > 1,
              autoPlayInterval: Duration(
                seconds: settings.slideDuration > 0
                    ? settings.slideDuration
                    : 15,
              ),
              autoPlayAnimationDuration:
                  const Duration(milliseconds: 1200),
              scrollPhysics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i, reason) {
                widget.onPageChanged?.call(i);
                _saveLastPage(settings.slideCategory, i);
              },
            ),
          );
        } else {
          content = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image_not_supported_outlined,
                    color: Colors.white24, size: 48),
                const SizedBox(height: 8),
                Text(
                  "Görsel bulunamadı: ${settings.slideCategory}",
                  style: const TextStyle(color: Colors.white38),
                ),
              ],
            ),
          );
        }

        return Container(
          color: Colors.black,
          width: double.infinity,
          height: actualHeight,
          child: Stack(
            children: [
              Positioned.fill(child: content),
              // ✅ Tam ekran butonu
              if (widget.showFullscreenButton && allImages.isNotEmpty && !isLoading)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FullScreenSlaytPage(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.fullscreen,
                        color: Colors.white70,
                        size: 28,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SmartFittedImage extends StatefulWidget {
  const _SmartFittedImage({required this.provider});
  final ImageProvider provider;

  @override
  State<_SmartFittedImage> createState() => _SmartFittedImageState();
}

class _SmartFittedImageState extends State<_SmartFittedImage> {
  double? _imageRatio;
  ImageStream? _activeStream;
  ImageStreamListener? _activeListener;

  @override
  void initState() {
    super.initState();
    _resolveRatio();
  }

  @override
  void dispose() {
    if (_activeStream != null && _activeListener != null) {
      _activeStream!.removeListener(_activeListener!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SmartFittedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _imageRatio = null;
      _resolveRatio();
    }
  }

  void _resolveRatio() {
    // ✅ Eski listener'ı temizle (hızlı rebuild'lerde stale callback'i önler)
    if (_activeStream != null && _activeListener != null) {
      _activeStream!.removeListener(_activeListener!);
    }

    final stream = widget.provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;

    listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (mounted) setState(() => _imageRatio = (h == 0) ? null : (w / h));
      stream.removeListener(listener);
      _activeStream = null;
      _activeListener = null;
    }, onError: (_, __) {
      stream.removeListener(listener);
      _activeStream = null;
      _activeListener = null;
    });

    _activeStream = stream;
    _activeListener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final screenRatio = c.maxWidth / c.maxHeight;
        final imgRatio = _imageRatio;

        final fit = (imgRatio != null && (imgRatio - screenRatio).abs() < 0.35)
            ? BoxFit.cover
            : BoxFit.contain;

        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Image(
              image: widget.provider,
              fit: fit,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.error, color: Colors.white24)),
            ),
          ),
        );
      },
    );
  }
  }


// ─────────────────────────────────────────────────────────
// ✅ TAM EKRAN SLAYT SAYFASI
// ─────────────────────────────────────────────────────────

class FullScreenSlaytPage extends ConsumerStatefulWidget {
  const FullScreenSlaytPage({super.key});

  @override
  ConsumerState<FullScreenSlaytPage> createState() =>
      _FullScreenSlaytPageState();
}

class _FullScreenSlaytPageState extends ConsumerState<FullScreenSlaytPage> {
  bool _showOverlay = true;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isMuted = false;
  bool _musicLoaded = false;

  @override
  void initState() {
    super.initState();
    // Tam ekran immersive mod (oryantasyon serbest)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 3 saniye sonra overlay'i gizle
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showOverlay = false);
    });

    // Arka plan müziğini başlat
    _initMusic();
  }

  Future<void> _initMusic() async {
    final settings = ref.read(alertSettingsProvider);
    if (!settings.bgMusicEnabled || settings.bgMusicPath == null) return;

    try {
      final path = settings.bgMusicPath!;
      if (path.startsWith('assets/')) {
        await _audioPlayer.setAsset(path);
      } else {
        await _audioPlayer.setFilePath(path);
      }
      _audioPlayer.setLoopMode(LoopMode.all);
      _audioPlayer.setVolume(1.0);
      await _audioPlayer.play();
      if (mounted) setState(() => _musicLoaded = true);
    } catch (e) {
      debugPrint('Arka plan müzik hatası: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
    if (_showOverlay) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showOverlay = false);
      });
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _audioPlayer.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          children: [
            // Slayt — tam ekran
            Positioned.fill(
              child: SlaytWidget(
                height: screenSize.height,
                showFullscreenButton: false,
              ),
            ),

            // Kapat butonu (sağ üst)
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showOverlay,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: const Icon(
                            Icons.fullscreen_exit,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Müzik mute/unmute butonu (sol alt)
            if (ref.watch(alertSettingsProvider).bgMusicEnabled)
              Positioned(
                bottom: 0,
                left: 0,
                child: AnimatedOpacity(
                  opacity: _showOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_showOverlay,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GestureDetector(
                          onTap: _toggleMute,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              _isMuted ? Icons.volume_off : Icons.volume_up,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

