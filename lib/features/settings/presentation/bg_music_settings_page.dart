import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'alert_settings_controller.dart';

class BgMusicSettingsPage extends ConsumerWidget {
  const BgMusicSettingsPage({super.key});

  /// assets/music/ klasöründeki tüm mp3 dosyalarını listeler
  Future<List<String>> _loadAppMusicAssets() async {
    try {
      final manifestContent =
          await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(manifestContent);
      final musicAssets = manifest.keys
          .where((key) => key.startsWith('assets/music/') && key.endsWith('.mp3'))
          .toList()
        ..sort();
      return musicAssets;
    } catch (e) {
      debugPrint('Uygulama müzikleri yüklenirken hata: $e');
      return [];
    }
  }

  /// Dosya adını yoldan çıkarır ve güzelleştirir
  String _prettyName(String path) {
    String name = path.split('/').last.split('\\').last;
    // .mp3 uzantısını kaldır
    if (name.toLowerCase().endsWith('.mp3')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(alertSettingsProvider);
    final controller = ref.read(alertSettingsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arka Plan Müziği'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8),
            child: Text(
              'MÜZİK AYARLARI',
              style: textTheme.titleSmall?.copyWith(color: Colors.grey),
            ),
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.music_note),
                  title: const Text('Arka Plan Müzik'),
                  subtitle: const Text('Seçilen müzik sürekli çalar'),
                  value: settings.bgMusicEnabled,
                  onChanged: (value) {
                    controller.toggleBgMusic(value);
                  },
                ),
                if (settings.bgMusicEnabled) ...[
                  const Divider(height: 1),
                  // Seçili müzik bilgisi
                  ListTile(
                    leading: const Icon(Icons.audiotrack_outlined),
                    title: Text(
                      settings.bgMusicPath != null
                          ? _prettyName(settings.bgMusicPath!)
                          : 'Müzik seçilmedi',
                    ),
                    subtitle: settings.bgMusicPath != null
                        ? Text(
                            settings.bgMusicPath!.startsWith('assets/')
                                ? 'Uygulama müziği'
                                : 'Cihaz dosyası',
                          )
                        : null,
                    trailing: settings.bgMusicPath != null
                        ? IconButton(
                            icon:
                                const Icon(Icons.close, color: Colors.redAccent),
                            onPressed: () {
                              controller.setBgMusicPath(null);
                            },
                          )
                        : null,
                  ),
                  const Divider(height: 1),

                  // ── Uygulama müziklerinden seç ──
                  ListTile(
                    leading: const Icon(Icons.library_music),
                    title: const Text('Uygulama Müziklerinden Seç'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final musicList = await _loadAppMusicAssets();
                      if (musicList.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Uygulama içinde müzik dosyası bulunamadı.'),
                          ),
                        );
                        return;
                      }
                      if (!context.mounted) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) {
                          return DraggableScrollableSheet(
                            initialChildSize: 0.5,
                            minChildSize: 0.3,
                            maxChildSize: 0.85,
                            expand: false,
                            builder: (ctx, scrollController) {
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      'Uygulama Müzikleri',
                                      style: textTheme.titleMedium,
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ListView.builder(
                                      controller: scrollController,
                                      itemCount: musicList.length,
                                      itemBuilder: (ctx, index) {
                                        final assetPath = musicList[index];
                                        final isSelected =
                                            settings.bgMusicPath == assetPath;
                                        return ListTile(
                                          leading: Icon(
                                            isSelected
                                                ? Icons.check_circle
                                                : Icons.music_note_outlined,
                                            color: isSelected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : null,
                                          ),
                                          title: Text(_prettyName(assetPath)),
                                          selected: isSelected,
                                          onTap: () {
                                            controller
                                                .setBgMusicPath(assetPath);
                                            if (!settings.bgMusicEnabled) {
                                              controller.toggleBgMusic(true);
                                            }
                                            Navigator.pop(ctx);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),

                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
