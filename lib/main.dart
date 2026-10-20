import 'package:flutter/material.dart';

void main() {
  runApp(const PrivacyNotesApp());
}

class PrivacyNotesApp extends StatelessWidget {
  const PrivacyNotesApp({super.key});

  static const Color seedColor = Color(0xFF0D9488);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Privacy Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 64,
                  color: seedColor,
                ),
                SizedBox(height: 16),
                Text(
                  'Privacy Notes',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Encrypted at rest • Zero cloud • 100% Local',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
