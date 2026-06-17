import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'settings_provider.dart';

class PresenceService with WidgetsBindingObserver {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  SettingsProvider? _settingsProvider;

  void initialize(SettingsProvider settingsProvider) {
    _settingsProvider = settingsProvider;
    WidgetsBinding.instance.addObserver(this);
    _updatePresence(true);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatePresence(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updatePresence(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _updatePresence(false);
    }
  }

  Future<void> _updatePresence(bool isOnline) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // If online status is hidden, we still update the 'isOnline' but we don't show it in UI
    // Alternatively, we can stop updating it altogether if that's the preferred privacy model.
    // Given the requirement "Hide presence indicators for blocked contacts" and "Respect user privacy toggles",
    // we'll update it in Firestore but the UI (ChatsScreen, ChatScreen) will check the 'onlineHidden' flag.
    
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isOnline': isOnline,
      'lastActive': FieldValue.serverTimestamp(),
    });
  }
}
