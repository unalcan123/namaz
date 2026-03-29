import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/locations/presentation/country_page.dart';
import '../features/locations/presentation/recent_locations_page.dart';
import '../features/settings/presentation/mode_controller.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/slide_settings_page.dart';
import '../features/settings/presentation/bg_music_settings_page.dart';

import '../features/settings/presentation/alert_settings_controller.dart';


class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appMode = ref.watch(modeProvider);

    Widget item({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
    }) {
      return ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      );
    }

    return Drawer(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Modern header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.95),
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.mosque_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ezan Vakti',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Namaz • Slayt • TV Modu',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  item(
                    icon: Icons.home_outlined,
                    title: 'Namaz Vakitleri',
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                  item(
                    icon: Icons.history_outlined,
                    title: 'Son Konumlarım',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RecentLocationsPage()),
                      );
                    },
                  ),
                  item(
                    icon: Icons.location_on_outlined,
                    title: 'Yeni Konum Seç',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CountryPage()),
                      );
                    },
                  ),

                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: theme.colorScheme.outlineVariant),
                  ),
                  const SizedBox(height: 6),
                  item(
                    icon: Icons.auto_stories_outlined,
                    title: 'Hakikat Damlaları',
                    subtitle: 'Yazılı slayt gösterisi',
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(alertSettingsProvider.notifier).setSlideCategory('hakikat');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Slayt kaynağı: Hakikat Damlaları'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  item(
                    icon: Icons.photo_library_outlined,
                    title: 'Slayt ve Foto Ayarları',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SlideSettingsPage()),
                      );
                    },
                  ),

                  item(
                    icon: Icons.music_note_outlined,
                    title: 'Arka Plan Müziği',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BgMusicSettingsPage()),
                      );
                    },
                  ),
                  item(
                    icon: Icons.settings_outlined,
                    title: 'Uygulama Ayarları',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      );
                    },
                  ),

                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: theme.colorScheme.outlineVariant),
                  ),
                  const SizedBox(height: 6),

                  // TV Mode as a modern card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SwitchListTile(
                        secondary: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.tv_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: const Text('TV Modu'),
                        subtitle: Text(
                          appMode == AppMode.tv
                              ? 'Büyük ekran arayüzü açık'
                              : 'Normal arayüz açık',
                        ),
                        value: appMode == AppMode.tv,
                        onChanged: (_) => ref.read(modeProvider.notifier).toggleMode(),
                      ),
                    ),
                  ),

                  item(
                    icon: Icons.info_outline,
                    title: 'Hakkında',
                    onTap: () {
                      Navigator.pop(context);
                      showAboutDialog(
                        context: context,
                        applicationName: 'Ezan Vakti',
                        applicationVersion: '1.0.0',
                        applicationLegalese: 'Unal C. tarafından geliştirilmiştir.',
                      );
                    },
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}