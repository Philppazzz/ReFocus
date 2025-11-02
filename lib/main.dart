import 'package:flutter/material.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  await DatabaseHelper.instance.database;
  
  print("✅ App initialized");
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ReFocus',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const IntroPage(),
    );
  }
}