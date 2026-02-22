const List<String> prayerNames = ['İmsak', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'];

const List<int> preNotificationMinutes = [30, 20, 10];

const Map<int, String> preNotificationAssets = {
  30: 'assets/audio/dakikakivaruyarisisesi_30.mp3',
  20: 'assets/audio/dakikakivaruyarisisesi_20.mp3',
  10: 'assets/audio/dakikakivaruyarisisesi_10.mp3',
};

class AlertSettings {
  final Map<String, bool> prayerAlarms;
  final AlertType alertType;
  final List<String> customAudioPaths;
  final String? selectedCustomAudioPath; 
  final Map<int, bool> preNotifications;
  final int slideDuration; 
  final String slideCategory; 
  final int lastUpdate; 
  final Map<String, String> userCategories;
  final String? bgMusicPath;
  final bool bgMusicEnabled;

  AlertSettings({
    Map<String, bool>? prayerAlarms,
    this.alertType = AlertType.ezan,
    this.customAudioPaths = const [],
    this.selectedCustomAudioPath,
    Map<int, bool>? preNotifications,
    this.slideDuration = 15,
    this.slideCategory = 'resim',
    this.lastUpdate = 0,
    this.userCategories = const {},
    this.bgMusicPath,
    this.bgMusicEnabled = false,
  })  : prayerAlarms = prayerAlarms ?? {for (var v in prayerNames) v: false},
        preNotifications = preNotifications ?? {for (var m in preNotificationMinutes) m: false};

  bool isPrayerEnabled(String prayerName) {
    return prayerAlarms[prayerName] ?? false;
  }

  bool isPreNotificationEnabled(int minute) {
    return preNotifications[minute] ?? false;
  }

  AlertSettings copyWith({
    Map<String, bool>? prayerAlarms,
    AlertType? alertType,
    List<String>? customAudioPaths,
    String? selectedCustomAudioPath,
    Map<int, bool>? preNotifications,
    int? slideDuration,
    String? slideCategory,
    int? lastUpdate,
    Map<String, String>? userCategories,
    String? bgMusicPath,
    bool clearBgMusicPath = false,
    bool? bgMusicEnabled,
  }) {
    return AlertSettings(
      prayerAlarms: prayerAlarms ?? this.prayerAlarms,
      alertType: alertType ?? this.alertType,
      customAudioPaths: customAudioPaths ?? this.customAudioPaths,
      selectedCustomAudioPath: selectedCustomAudioPath ?? this.selectedCustomAudioPath,
      preNotifications: preNotifications ?? this.preNotifications,
      slideDuration: slideDuration ?? this.slideDuration,
      slideCategory: slideCategory ?? this.slideCategory,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      userCategories: userCategories ?? this.userCategories,
      bgMusicPath: clearBgMusicPath ? null : (bgMusicPath ?? this.bgMusicPath),
      bgMusicEnabled: bgMusicEnabled ?? this.bgMusicEnabled,
    );
  }
}

enum AlertType {
  ezan,
  custom;

  String get displayName => const {
        AlertType.ezan: 'Ezan Oku',
        AlertType.custom: 'Özel Seslerim',
      }[this]!;
}
