import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/alert_settings.dart';
import 'alert_settings_controller.dart';

class BgMusicSettingsPage extends ConsumerWidget {
  const BgMusicSettingsPage({super.key});

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
                        ? settings.bgMusicPath!.split('/').last.split('\\').last
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
                          icon: const Icon(Icons.close, color: Colors.redAccent),
                          onPressed: () {
                            controller.setBgMusicPath(null);
                          },
                        )
                      : null,
                ),
                const Divider(height: 1),
                // Uygulama müziklerinden seç
                ListTile(
                  leading: const Icon(Icons.library_music_outlined),
                  title: const Text('Uygulama Müziklerinden Seç'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final manifestContent =
                        await rootBundle.loadString('AssetManifest.json');
                    final Map<String, dynamic> manifest =
                        json.decode(manifestContent);
                    final musicFiles = manifest.keys
                        .where((k) =>
                            k.contains('assets/music/') &&
                            (k.endsWith('.mp3') ||
                                k.endsWith('.m4a') ||
                                k.endsWith('.wav') ||
                                k.endsWith('.ogg')))
                        .toList();

                    if (musicFiles.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'assets/music/ klasöründe müzik dosyası yok')),
                        );
                      }
                      return;
                    }

                    if (!context.mounted) return;
                    final selected = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Müzik Seçin'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: musicFiles.length,
                            itemBuilder: (ctx, i) {
                              final path = musicFiles[i];
                              final name = path.split('/').last;
                              final isSelected = settings.bgMusicPath == path;
                              return ListTile(
                                leading: Icon(
                                  isSelected
                                      ? Icons.music_note
                                      : Icons.music_note_outlined,
                                  color: isSelected ? Colors.blue : null,
                                ),
                                title: Text(name),
                                selected: isSelected,
                                onTap: () => Navigator.pop(ctx, path),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                    if (selected != null) {
                      controller.setBgMusicPath(selected);
                      if (!settings.bgMusicEnabled) {
                        controller.toggleBgMusic(true);
                      }
                    }
                  },
                ),
                const Divider(height: 1),
                // Cihazdan dosya seç
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Cihazdan Müzik Seç'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.audio,
                    );
                    if (result != null && result.files.single.path != null) {
                      controller.setBgMusicPath(result.files.single.path!);
                      if (!settings.bgMusicEnabled) {
                        controller.toggleBgMusic(true);
                      }
                    }
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
