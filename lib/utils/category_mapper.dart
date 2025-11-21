/// Maps Play Store categories to ReFocus category system
/// Handles automatic categorization of installed apps
class CategoryMapper {
  /// ReFocus category constants
  static const String categorySocial = 'Social';
  static const String categoryGames = 'Games';
  static const String categoryEntertainment = 'Entertainment';
  static const String categoryOthers = 'Others';

  /// List of all valid ReFocus categories
  static const List<String> allCategories = [
    categorySocial,
    categoryGames,
    categoryEntertainment,
    categoryOthers,
  ];

  /// Map Play Store category to ReFocus category
  ///
  /// Play Store categories (from Android ApplicationInfo.category):
  /// - SOCIAL, GAME, AUDIO, VIDEO, IMAGE, NEWS, MAPS, PRODUCTIVITY, UNDEFINED, etc.
  ///
  /// Returns one of: Social, Games, Entertainment, Others
  static String mapPlayStoreCategory(String? playStoreCategory) {
    if (playStoreCategory == null || playStoreCategory.isEmpty) {
      return categoryOthers;
    }

    final category = playStoreCategory.toUpperCase();

    // Social Media
    if (_isSocialCategory(category)) {
      return categorySocial;
    }

    // Games
    if (_isGameCategory(category)) {
      return categoryGames;
    }

    // Entertainment
    if (_isEntertainmentCategory(category)) {
      return categoryEntertainment;
    }

    // Default to Others
    return categoryOthers;
  }

  /// Check if category is Social (ONLY social media, NOT messaging)
  /// ⚠️ CRITICAL: COMMUNICATION is NOT included!
  /// - Messaging apps (WhatsApp, Telegram, Messenger) use COMMUNICATION → goes to "Others"
  /// - Only pure social media apps (Facebook, Instagram, TikTok) should be monitored
  /// - "Others" category is NEVER monitored or locked, so messaging apps stay accessible
  static bool _isSocialCategory(String category) {
    const socialCategories = [
      'SOCIAL', // Pure social media from Play Store (Facebook, Instagram, Twitter)
      'DATING', // Dating apps (Tinder, Bumble) - can be monitored
      // ❌ COMMUNICATION REMOVED - messaging apps must NOT be locked!
      // WhatsApp, Telegram, Messenger will go to "Others" and remain unlocked
    ];
    return socialCategories.contains(category);
  }

  /// Check if category is Games
  static bool _isGameCategory(String category) {
    const gameCategories = [
      'GAME',
      'GAME_ACTION',
      'GAME_ADVENTURE',
      'GAME_ARCADE',
      'GAME_BOARD',
      'GAME_CARD',
      'GAME_CASINO',
      'GAME_CASUAL',
      'GAME_EDUCATIONAL',
      'GAME_MUSIC',
      'GAME_PUZZLE',
      'GAME_RACING',
      'GAME_ROLE_PLAYING',
      'GAME_SIMULATION',
      'GAME_SPORTS',
      'GAME_STRATEGY',
      'GAME_TRIVIA',
      'GAME_WORD',
    ];
    return gameCategories.contains(category);
  }

  /// Check if category is Entertainment
  static bool _isEntertainmentCategory(String category) {
    const entertainmentCategories = [
      'MUSIC_AND_AUDIO',
      'VIDEO_PLAYERS',
      'VIDEO_PLAYERS_AND_EDITORS',
      'ENTERTAINMENT',
      'PHOTOGRAPHY',
      'MEDIA_AND_VIDEO',
      'MUSIC',
      'AUDIO',
      'VIDEO',
      'IMAGE',
    ];
    return entertainmentCategories.contains(category);
  }

  /// Check if package is a system app that should be ignored
  /// Returns true for Android system apps, launchers, ReFocus app itself, etc.
  static bool isSystemApp(String packageName) {
    const systemPackagePrefixes = [
      'com.android.',
      'com.google.android.ext',
      'com.google.android.gsf',
      'com.google.android.gms',
      'com.google.android.tts',
      'android',
      'com.samsung.android',
      'com.sec.android',
      'com.miui',
      'com.xiaomi',
      'com.huawei',
      'com.oppo',
      'com.vivo',
      'com.oneplus',
      'com.coloros',
      'com.bbk',
    ];

    const systemPackageNames = [
      'com.google.android.packageinstaller',
      'com.google.android.permissioncontroller',
      'com.android.vending', // Google Play Store
      'com.android.chrome', // Chrome (debatable, but often considered system)
      'com.example.refocus_app', // ✅ ReFocus app itself - never track our own app
    ];

    // Check prefixes
    for (final prefix in systemPackagePrefixes) {
      if (packageName.startsWith(prefix)) {
        return true;
      }
    }

    // Check exact matches
    if (systemPackageNames.contains(packageName)) {
      return true;
    }

    return false;
  }

  /// Check if a category should be monitored by default
  /// Social, Games, and Entertainment are monitored; Others are not
  static bool shouldMonitorCategory(String category) {
    return category == categorySocial ||
        category == categoryGames ||
        category == categoryEntertainment;
  }

  /// Check if an app is a messaging app that should NOT be tracked
  /// Messaging apps are essential and should never be included in usage statistics
  /// Returns true for WhatsApp, Telegram, Messenger, Discord, SMS apps, etc.
  static bool isMessagingApp(String packageName) {
    // List of known messaging app package names
    const messagingPackages = [
      'com.whatsapp', // WhatsApp
      'com.whatsapp.w4b', // WhatsApp Business
      'org.telegram.messenger', // Telegram
      'org.telegram.plus', // Telegram X
      'com.facebook.orca', // Messenger
      'com.discord', // Discord
      'com.viber.voip', // Viber
      'com.skype.raider', // Skype
      'com.google.android.apps.messaging', // Google Messages (SMS)
      'com.android.mms', // Default SMS app
      'com.samsung.android.messaging', // Samsung Messages
      'com.microsoft.teams', // Microsoft Teams
      'com.slack', // Slack
      'com.tencent.mm', // WeChat
      'com.linecorp.line', // LINE
      'com.kakao.talk', // KakaoTalk
      'com.snapchat.android', // Snapchat (has messaging but also social)
      // Note: Snapchat is tricky - it's both social and messaging
      // We'll keep it as Social for now since it's primarily social media
    ];

    // Check exact package name matches
    if (messagingPackages.contains(packageName)) {
      return true;
    }

    // Check for common messaging app patterns
    final lowerPackage = packageName.toLowerCase();
    if (lowerPackage.contains('messenger') ||
        lowerPackage.contains('message') ||
        lowerPackage.contains('sms') ||
        lowerPackage.contains('mms') ||
        (lowerPackage.contains('chat') && !lowerPackage.contains('snapchat'))) {
      return true;
    }

    return false;
  }

  /// Validate if a category is valid
  static bool isValidCategory(String category) {
    return allCategories.contains(category);
  }

  /// Get category color for UI display
  static String getCategoryColor(String category) {
    switch (category) {
      case categorySocial:
        return '#FF1976D2'; // Blue
      case categoryGames:
        return '#FF9C27B0'; // Purple
      case categoryEntertainment:
        return '#FFF44336'; // Red
      case categoryOthers:
        return '#FF757575'; // Grey
      default:
        return '#FF000000'; // Black
    }
  }

  /// Get category icon for UI display
  static String getCategoryIcon(String category) {
    switch (category) {
      case categorySocial:
        return '👥'; // People
      case categoryGames:
        return '🎮'; // Game controller
      case categoryEntertainment:
        return '🎬'; // Movie camera
      case categoryOthers:
        return '📱'; // Phone
      default:
        return '❓'; // Question mark
    }
  }

  /// Get category description
  static String getCategoryDescription(String category) {
    switch (category) {
      case categorySocial:
        return 'Social media apps (Facebook, Instagram, TikTok, Twitter)';
      case categoryGames:
        return 'Mobile games and gaming platforms';
      case categoryEntertainment:
        return 'Streaming, music, videos, and media apps';
      case categoryOthers:
        return 'Messaging, productivity, utilities (never locked)';
      default:
        return 'Unknown category';
    }
  }

  /// Hardcoded package-to-category mappings (fallback for common apps)
  ///
  /// ⚠️ CRITICAL DISTINCTION:
  /// - Social Media (monitored, can lock): Facebook, Instagram, TikTok, Twitter, Snapchat
  /// - Messaging Apps (NOT monitored, never locked): WhatsApp, Telegram, Messenger, Discord
  ///
  /// Used as fallback when Play Store category is UNDEFINED or unavailable.
  /// Primary categorization still comes from Play Store metadata.
  static String? mapPackageToCategory(String packageName) {
    const Map<String, String> essentialMappings = {
      // ✅ SOCIAL MEDIA ONLY (can be monitored and locked)
      'com.facebook.katana': categorySocial, // Facebook app
      'com.facebook.lite': categorySocial, // Facebook Lite
      'com.instagram.android': categorySocial, // Instagram
      'com.instagram.barcelona': categorySocial, // Threads
      'com.twitter.android': categorySocial, // Twitter/X
      'com.snapchat.android': categorySocial, // Snapchat
      'com.tiktok.android': categorySocial, // TikTok
      'com.zhiliaoapp.musically': categorySocial, // TikTok (alternative package)
      'com.reddit.frontpage': categorySocial, // Reddit
      'com.linkedin.android': categorySocial, // LinkedIn
      'com.pinterest': categorySocial, // Pinterest
      'com.tumblr': categorySocial, // Tumblr

      // ✅ MESSAGING APPS → "Others" (NEVER monitored, NEVER locked)
      'com.whatsapp': categoryOthers, // WhatsApp - essential messaging
      'com.whatsapp.w4b': categoryOthers, // WhatsApp Business
      'org.telegram.messenger': categoryOthers, // Telegram - essential messaging
      'org.telegram.plus': categoryOthers, // Telegram X
      'com.facebook.orca': categoryOthers, // Messenger - essential messaging
      'com.discord': categoryOthers, // Discord - essential for many
      'com.viber.voip': categoryOthers, // Viber
      'com.skype.raider': categoryOthers, // Skype
      'com.google.android.apps.messaging': categoryOthers, // Google Messages (SMS)
      'com.android.mms': categoryOthers, // Default SMS app

      // ✅ ENTERTAINMENT (can be monitored and locked)
      'com.google.android.youtube': categoryEntertainment, // YouTube
      'com.google.android.apps.youtube.music': categoryEntertainment, // YouTube Music
      'com.netflix.mediaclient': categoryEntertainment, // Netflix
      'com.spotify.music': categoryEntertainment, // Spotify
      'com.amazon.avod.thirdpartyclient': categoryEntertainment, // Prime Video
      'com.hulu.plus': categoryEntertainment, // Hulu
      'com.disney.disneyplus': categoryEntertainment, // Disney+
    };

    return essentialMappings[packageName];
  }
}
