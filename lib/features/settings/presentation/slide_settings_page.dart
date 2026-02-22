import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';

import '../data/alert_settings.dart';
import 'alert_settings_controller.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

/// ✅ GÖRSEL İŞLEME YARDIMCISI (TV İÇİN NORMALLEŞTİRME)
class ImageTvFixer {
  /// Görseli 1920x1080 (16:9) formatına merkezden kırparak (cover mantığı) ölçekler
  static img.Image resizeCoverAndCrop(
      img.Image src, {
        int targetW = 1920,
        int targetH = 1080,
      }) {
    final double srcAspect = src.width / src.height;
    final double targetAspect = targetW / targetH;

    img.Image resized;
    if (srcAspect > targetAspect) {
      resized = img.copyResize(
        src,
        height: targetH,
        interpolation: img.Interpolation.linear,
      );
    } else {
      resized = img.copyResize(
        src,
        width: targetW,
        interpolation: img.Interpolation.linear,
      );
    }

    int x = ((resized.width - targetW) ~/ 2);
    int y = ((resized.height - targetH) ~/ 2);

    x = x.clamp(0, (resized.width - targetW).clamp(0, resized.width));
    y = y.clamp(0, (resized.height - targetH).clamp(0, resized.height));

    return img.copyCrop(resized, x: x, y: y, width: targetW, height: targetH);
  }

  /// ✅ NEW: Döndürme için "contain + padding" (kırpma yok, bozulma yok)
  static img.Image resizeContainWithPadding(
      img.Image src, {
        int targetW = 1920,
        int targetH = 1080,
      }) {
    final double srcAspect = src.width / src.height;
    final double targetAspect = targetW / targetH;

    int newW, newH;
    if (srcAspect > targetAspect) {
      newW = targetW;
      newH = (targetW / srcAspect).round();
    } else {
      newH = targetH;
      newW = (targetH * srcAspect).round();
    }

    final resized = img.copyResize(
      src,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );

    final canvas = img.Image(width: targetW, height: targetH);
    img.fill(canvas, color: img.ColorUint8.rgb(0, 0, 0)); // siyah letterbox

    final dx = ((targetW - newW) ~/ 2).clamp(0, targetW);
    final dy = ((targetH - newH) ~/ 2).clamp(0, targetH);


    // ✅ HER IMAGE SÜRÜMÜYLE ÇALIŞIR
    img.compositeImage(
      canvas,
      resized,
      dstX: dx,
      dstY: dy,
    );

    return canvas;
  }

  /// Görseli TV standartlarına getirir (Bake Orientation + Force Landscape + 16:9 cover)
  static img.Image processForTv(img.Image input) {
    var processed = img.bakeOrientation(input);
    if (processed.height > processed.width) {
      processed = img.copyRotate(processed, angle: 90);
    }
    return resizeCoverAndCrop(processed);
  }

  static Future<void> _evictAndClearImageCache(File file) async {
    await FileImage(file).evict();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// Dosyayı manuel olarak 90 derece sağa döndürür (kırpma yok!)
  static Future<void> rotateFile90Degrees(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      decoded = img.bakeOrientation(decoded);
      final rotated = img.copyRotate(decoded, angle: 90);

      // ✅ rotate sonrası coverCrop YOK -> bozulma/kırpılma biter
      final fixed = resizeContainWithPadding(rotated);

      await file.writeAsBytes(img.encodeJpg(fixed, quality: 85), flush: true);
      await _evictAndClearImageCache(file);
    } catch (e) {
      debugPrint("Döndürme hatası: $e");
    }
  }

  /// Dosyayı manuel olarak 90 derece sola döndürür (kırpma yok!)
  static Future<void> rotateFileMinus90Degrees(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      decoded = img.bakeOrientation(decoded);
      final rotated = img.copyRotate(decoded, angle: -90);

      // ✅ rotate sonrası coverCrop YOK -> bozulma/kırpılma biter
      final fixed = resizeContainWithPadding(rotated);

      await file.writeAsBytes(img.encodeJpg(fixed, quality: 85), flush: true);
      await _evictAndClearImageCache(file);
    } catch (e) {
      debugPrint("Döndürme hatası: $e");
    }
  }

  static Future<void> normalizeFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final fixed = processForTv(decoded);
      await file.writeAsBytes(img.encodeJpg(fixed, quality: 85), flush: true);
      await _evictAndClearImageCache(file);
    } catch (e) {
      debugPrint("Dosya düzeltme hatası: $path -> $e");
    }
  }

  static Future<int> normalizeAllUserPhotos() async {
    if (kIsWeb) return 0;
    final appDir = await getApplicationDocumentsDirectory();
    final userImagesDir = Directory('${appDir.path}/userImages');
    if (!await userImagesDir.exists()) return 0;

    int count = 0;
    final entities = userImagesDir.listSync(recursive: true);
    for (var entity in entities) {
      if (entity is File) {
        final p = entity.path.toLowerCase();
        if (p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png')) {
          await normalizeFile(entity.path);
          count++;
        }
      }
    }
    return count;
  }
}

class SlideSettingsPage extends ConsumerWidget {
  const SlideSettingsPage({super.key});
  Box get _webBox => Hive.box('web_user_images');

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

  Future<void> addUserImagesWeb(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(alertSettingsProvider);
    final fullMap = _getFullCategoryMap(settings);

    // ✅ Kategori seçme dialogu
    final String? selectedKey = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Kategori Seçin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: fullMap.entries
              .map((e) => ListTile(
                    title: Text(e.value),
                    onTap: () => Navigator.pop(context, e.key),
                  ))
              .toList(),
        ),
      ),
    );
    if (selectedKey == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true, // ✅ Web'de bytes zorunlu
    );
    if (result == null) return;

    final key = _webKey(selectedKey);
    final List existing = (_webBox.get(key) as List?) ?? [];

    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      existing.add(base64Encode(bytes));
    }

    await _webBox.put(key, existing);
    ref.read(alertSettingsProvider.notifier).touchLastUpdate();
  }
  static const Map<String, String> defaultCategoryMap = {
    'resim': 'Genel Resimler',
    'hadis': 'Hadis-i Şerifler',
    'dua': 'Dualar',
    'besmele': 'Besmele',
    'namaz': 'Namaz Bilgileri',
    'ramazan': 'Ramazan',
    'Kullanıcı Foto': 'Benim Fotoğraflarım',
  };

  Map<String, String> _getFullCategoryMap(AlertSettings settings) {
    return {...defaultCategoryMap, ...settings.userCategories};
  }

  String _getInternalDir(String key) => key == 'Kullanıcı Foto' ? 'user' : key;

  @override

  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(alertSettingsProvider);
    final alertController = ref.read(alertSettingsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final fullCategoryMap = _getFullCategoryMap(settings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Slayt ve Foto Ayarları'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8),
            child: Text(
              'SLAYT AYARLARI',
              style: textTheme.titleSmall?.copyWith(color: Colors.grey),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Görüntülenecek Kategori'),
                  trailing: DropdownButton<String>(
                    value: settings.slideCategory,
                    onChanged: (value) {
                      if (value != null) {
                        alertController.setSlideCategory(value);
                      }
                    },
                    items: fullCategoryMap.entries.map((entry) {
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('Fotoğraf Değişim Süresi'),
                  trailing: DropdownButton<int>(
                    value: settings.slideDuration,
                    onChanged: (value) {
                      if (value != null) {
                        alertController.setSlideDuration(value);
                      }
                    },
                    items: [5, 10, 15, 20, 30, 45, 60].map((seconds) {
                      return DropdownMenuItem<int>(
                        value: seconds,
                        child: Text('$seconds sn'),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.add_a_photo_outlined),
                  title: const Text('Yeni Fotoğraf Ekle'),
                  subtitle: const Text('Seçilenleri TV formatına uygun ekler'),
                  onTap: () async {
                    if (kIsWeb) {
                      await addUserImagesWeb(context, ref);
                      if (context.mounted) Navigator.pop(context);
                    } else {
                      await _pickUserImageWithCategory(context, ref);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_fix_high, color: Colors.blue),
                  title: const Text('Eski Fotoğrafları Düzenle'),
                  subtitle: const Text('Tüm yüklenenleri yatay ve 16:9 yapar'),
                  onTap: () async {
                    _showLoadingDialog(context);
                    final count = await ImageTvFixer.normalizeAllUserPhotos();
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("$count fotoğraf TV formatına uygun düzenlendi.")),
                      );
                      ref.read(alertSettingsProvider.notifier).triggerRefresh();
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('Yeni Kategori Oluştur'),
                  onTap: () => _addNewCategory(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Fotoğraflarımı Yönet'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showUserImageManager(context),
                ),
              ],
            ),
          ),

          if (settings.userCategories.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 8),
              child: Text(
                'KATEGORİLERİMİ YÖNET',
                style: textTheme.titleSmall?.copyWith(color: Colors.grey),
              ),
            ),
            Card(
              child: Column(
                children: settings.userCategories.entries.map((e) {
                  return ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: Text(e.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _confirmDeleteCategory(context, e.key, e.value, alertController),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _addNewCategory(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text("Yeni Kategori"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Kategori adı girin"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Ekle"),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await ref.read(alertSettingsProvider.notifier).addUserCategory(name);
    }
  }

  Future<void> _pickUserImageWithCategory(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(alertSettingsProvider);
    final fullMap = _getFullCategoryMap(settings);

    final String? selectedKey = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text("Kategori Seçin"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: fullMap.entries
              .map((e) => ListTile(
            title: Text(e.value),
            onTap: () => Navigator.pop(context, e.key),
          ))
              .toList(),
        ),
      ),
    );

    if (selectedKey == null) return;

    if (!kIsWeb) {
      await Permission.photos.request();
      await Permission.storage.request();
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final appDir = await getApplicationDocumentsDirectory();
      final internalDir = _getInternalDir(selectedKey);
      final categoryDir = Directory('${appDir.path}/userImages/$internalDir');

      if (!await categoryDir.exists()) {
        await categoryDir.create(recursive: true);
      }

      if (!context.mounted) return;
      _showLoadingDialog(context);
      int count = 0;

      for (var file in result.files) {
        if (file.path == null) continue;

        // 1) EXIF düzelt (dosyayı doğru yöne çevirir)
        final rotatedFile = await FlutterExifRotation.rotateAndSaveImage(path: file.path!);
        final bytes = await rotatedFile.readAsBytes();

        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;

        // 2) TV slayt standardı (cover + crop)
        final processed = ImageTvFixer.processForTv(decoded);

        final fileName = '${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File('${categoryDir.path}/$fileName')
            .writeAsBytes(img.encodeJpg(processed, quality: 85), flush: true);

        count++;
      }

      if (context.mounted) {
        Navigator.pop(context);
        ref.read(alertSettingsProvider.notifier).triggerRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$count fotoğraf TV formatında eklendi.")),
        );
      }
    }
  }

  void _confirmDeleteCategory(
      BuildContext context,
      String key,
      String name,
      AlertSettingsNotifier controller,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Kategoriyi Sil"),
        content: Text("$name kategorisini ve içindeki tüm fotoğrafları silmek istiyor musunuz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await controller.removeUserCategory(key);
    }
  }

  void _showUserImageManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const UserImageManagerSheet(),
    );
  }
}

class UserImageManagerSheet extends ConsumerStatefulWidget {
  const UserImageManagerSheet({super.key});

  @override
  ConsumerState<UserImageManagerSheet> createState() => _UserImageManagerSheetState();
}

class _UserImageManagerSheetState extends ConsumerState<UserImageManagerSheet> {
  // Native: dosya yolları | Web: base64 string'ler
  List<String> userImages = [];
  bool isLoading = true;
  String currentCategoryKey = 'resim';

  Box get _webBox => Hive.box('web_user_images');

  @override
  void initState() {
    super.initState();
    currentCategoryKey = ref.read(alertSettingsProvider).slideCategory;
    _loadUserImages();
  }

  String _getInternalDir(String key) => key == 'Kullanıcı Foto' ? 'user' : key;

  String _webKey(String category) {
    final cat = category == 'Kullanıcı Foto'
        ? 'user'
        : category == 'Genel Resimler'
            ? 'resim'
            : category == 'Hadis-i Şerifler'
                ? 'hadis'
                : category == 'Dualar'
                    ? 'dua'
                    : category == 'Besmele'
                        ? 'besmele'
                        : category == 'Namaz Bilgileri'
                            ? 'namaz'
                            : category == 'Ramazan'
                                ? 'ramazan'
                                : category;
    return 'userImages_$cat';
  }

  Future<void> _loadUserImages() async {
    setState(() => isLoading = true);

    if (kIsWeb) {
      // ✅ Web: Hive'dan base64 listesi oku
      final key = _webKey(currentCategoryKey);
      final List raw = (_webBox.get(key) as List?) ?? [];
      userImages = raw.cast<String>();
    } else {
      // ✅ Native: dosya sistemi
      final appDir = await getApplicationDocumentsDirectory();
      final internalDir = _getInternalDir(currentCategoryKey);
      final categoryDir = Directory('${appDir.path}/userImages/$internalDir');

      if (await categoryDir.exists()) {
        userImages = categoryDir
            .listSync()
            .where((f) =>
                f.path.toLowerCase().endsWith('.jpg') ||
                f.path.toLowerCase().endsWith('.jpeg') ||
                f.path.toLowerCase().endsWith('.png'))
            .map((f) => f.path)
            .toList();
      } else {
        userImages = [];
      }
    }

    if (mounted) setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(alertSettingsProvider);
    final fullMap = {...SlideSettingsPage.defaultCategoryMap, ...settings.userCategories};

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: fullMap.entries
                      .map(
                        (e) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: currentCategoryKey == e.key,
                        onSelected: (val) {
                          if (val) {
                            setState(() => currentCategoryKey = e.key);
                            _loadUserImages();
                          }
                        },
                      ),
                    ),
                  )
                      .toList(),
                ),
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : userImages.isEmpty
                        ? const Center(
                            child: Text('Hiç fotoğraf yok.',
                                style: TextStyle(color: Colors.white)))
                        : GridView.builder(
                            controller: controller,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: userImages.length,
                            itemBuilder: (context, index) {
                              final item = userImages[index];
                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      // ✅ Web: base64 | Native: dosya
                                      child: kIsWeb
                                          ? Image.memory(
                                              base64Decode(item),
                                              fit: BoxFit.cover,
                                              key: ValueKey(
                                                  '${index}_${settings.lastUpdate}'),
                                            )
                                          : Image.file(
                                              File(item),
                                              fit: BoxFit.cover,
                                              key: ValueKey(
                                                  '${item}_${settings.lastUpdate}'),
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Row(
                                      children: [
                                        if (!kIsWeb) ...[
                                          // 🔄 SAĞA DÖNDÜR (sadece native)
                                          GestureDetector(
                                            onTap: () async {
                                              await ImageTvFixer
                                                  .rotateFile90Degrees(item);
                                              ref
                                                  .read(alertSettingsProvider
                                                      .notifier)
                                                  .triggerRefresh();
                                              _loadUserImages();
                                            },
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                color: Colors.blueAccent,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(6),
                                              child: const Icon(
                                                  Icons.rotate_right,
                                                  color: Colors.white,
                                                  size: 18),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // 🔄 SOLA DÖNDÜR (sadece native)
                                          GestureDetector(
                                            onTap: () async {
                                              await ImageTvFixer
                                                  .rotateFileMinus90Degrees(
                                                      item);
                                              ref
                                                  .read(alertSettingsProvider
                                                      .notifier)
                                                  .triggerRefresh();
                                              _loadUserImages();
                                            },
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                color: Colors.blueAccent,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(6),
                                              child: const Icon(
                                                  Icons.rotate_left,
                                                  color: Colors.white,
                                                  size: 18),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        // 🗑 SİL
                                        GestureDetector(
                                          onTap: () async {
                                            if (kIsWeb) {
                                              // ✅ Web: Hive listesinden çıkar
                                              final key =
                                                  _webKey(currentCategoryKey);
                                              final List raw =
                                                  (_webBox.get(key) as List?) ??
                                                      [];
                                              raw.removeAt(index);
                                              await _webBox.put(key, raw);
                                            } else {
                                              await File(item).delete();
                                            }
                                            ref
                                                .read(alertSettingsProvider
                                                    .notifier)
                                                .triggerRefresh();
                                            _loadUserImages();
                                          },
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            child: const Icon(Icons.delete,
                                                color: Colors.white, size: 18),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
