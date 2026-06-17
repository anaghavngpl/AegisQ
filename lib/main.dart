import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'services/theme_service.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

import 'package:provider/provider.dart';
import 'services/settings_provider.dart';
import 'services/presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase already initialized or failed: $e');
  }

  // Restore Night Vision (dark mode) preference before UI renders
  await ThemeService().loadSavedTheme();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const QuantumChatApp(),
    ),
  );
}

class QuantumChatApp extends StatefulWidget {
  const QuantumChatApp({Key? key}) : super(key: key);
  @override
  State<QuantumChatApp> createState() => _QuantumChatAppState();
}

class _QuantumChatAppState extends State<QuantumChatApp> {
  @override
  void initState() {
    super.initState();
    // Initialize presence after first frame is drawn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        PresenceService().initialize(settings);
      }
    });

    // Secondary flags (non-blocking) applied based on settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Platform.isAndroid) {
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        _applySecurityFlags(settings.screenshotProtection);
      }
    });
  }

  void _applySecurityFlags(bool protect) {
    if (protect) {
      FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE).catchError((_) {});
    } else {
      FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        // Apply security flags globally whenever settings change
        if (Platform.isAndroid) {
          if (settings.screenshotProtection) {
            FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE).catchError((_) {});
          } else {
            FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE).catchError((_) {});
          }
        }

        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService().themeMode,
          builder: (context, mode, child) {
            return MaterialApp(
              title: 'AegisQ',
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: const Color(0xFFB57BEE),
                brightness: Brightness.light,
                scaffoldBackgroundColor: const Color(0xFFF7F0FF),
              ).copyWith(
                colorScheme: const ColorScheme.light(
                  primary:    Color(0xFF9333EA),
                  secondary:  Color(0xFFCBA6F7),
                  surface:    Color(0xFFF3E8FF),
                  onPrimary:  Colors.white,
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: const Color(0xFFB57BEE),
                brightness: Brightness.dark,
                scaffoldBackgroundColor: const Color(0xFF120C1A),
              ).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary:   Color(0xFFD946EF),
                  secondary: Color(0xFF9333EA),
                  surface:   Color(0xFF1F122B),
                  onPrimary: Colors.white70,
                ),
              ),
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
