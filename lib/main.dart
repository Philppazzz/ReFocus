import 'package:flutter/material.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class Nav {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

/// Background task handler - runs even when app is closed
/// This keeps monitoring and enforcement active at all times
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

/// Handler for background monitoring tasks
class BackgroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🚀 Background task started at $timestamp');
    // Monitoring will be started by MonitorService when app initializes
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This is called periodically by the foreground service
    // The actual monitoring is handled by MonitorService's timer
    // This just keeps the service alive
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool sendPort) async {
    print('🛑 Background task destroyed at $timestamp');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground task
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'refocus_monitoring',
      channelName: 'ReFocus Monitoring',
      channelDescription: 'Keeps ReFocus monitoring your app usage',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000), // Check every 5 seconds
      autoRunOnBoot: true, // Auto-start on device boot
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

  // Initialize notification service
  await NotificationService.initialize();
  await NotificationService.requestPermission();

  runApp(const MyApp());
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Ensure monitoring continues when app resumes
    if (state == AppLifecycleState.resumed) {
      // Restart monitoring service if it was killed
      MonitorService.restartMonitoring();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ReFocus',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey: Nav.navigatorKey,
      home: const IntroPage(),
    );
  }
}
