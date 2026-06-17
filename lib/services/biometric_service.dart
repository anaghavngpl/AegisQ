import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  static const String _biometricEnabledKey = 'app_lock_v2'; // New key for fresh start
  static const String _chatLockPrefix = 'chat_lock_';

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // Check if device supports any authentication
  Future<bool> isAuthAvailable() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException catch (e) {
      debugPrint('Auth check error: $e');
      return false;
    }
  }

  // Get available authentication methods
  Future<List<String>> getAvailableMethods() async {
    try {
      final types = await _localAuth.getAvailableBiometrics();
      return types.map((t) {
        switch (t) {
          case BiometricType.fingerprint:
            return 'Fingerprint';
          case BiometricType.face:
            return 'Face ID';
          case BiometricType.iris:
            return 'Iris';
          default:
            return 'Biometric';
        }
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  // Authenticate using biometrics or device credentials
  Future<bool> authenticate({String reason = 'Authenticate to access AegisQ'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Auth error: $e');
      return false;
    }
  }

  // App Lock methods
  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
  }

  Future<bool> authenticateForAppUnlock() async {
    if (!await isBiometricEnabled()) return true;
    return authenticate(reason: 'Unlock AegisQ');
  }

  // Per-chat lock methods
  Future<bool> isChatLockedForUser(String chatId) async {
    final value = await _storage.read(key: '$_chatLockPrefix$chatId');
    return value == 'true';
  }

  Future<void> setChatLockedForUser(String chatId, bool locked) async {
    await _storage.write(key: '$_chatLockPrefix$chatId', value: locked.toString());
  }

  Future<bool> authenticateForChat(String chatId) async {
    if (!await isChatLockedForUser(chatId)) return true;
    return authenticate(reason: 'Authenticate to open chat');
  }
}
