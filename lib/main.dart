import 'package:flutter/material.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/services/monitor_service.dart';

class Nav {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
