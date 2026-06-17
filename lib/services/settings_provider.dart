import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

class SettingsProvider with ChangeNotifier {
  bool _stealthMode = false;
  bool _screenshotProtection = true;
  bool _readReceipts = true;
  bool _onlineHidden = true;
  bool _lastSeenHidden = true;
  bool _disappearingMessages = false;
  int _disappearDuration = 60;
  bool _autoDeleteMedia = false;
  List<String> _blockedUsers = [];
  List<String> _archivedChats = [];
  String? _name;
  String? _photoUrl;
  String? _bio;

  bool get stealthMode => _stealthMode;
  bool get screenshotProtection => _screenshotProtection;
  bool get readReceipts => _readReceipts;
  bool get onlineHidden => _onlineHidden;
  bool get lastSeenHidden => _lastSeenHidden;
  bool get disappearingMessages => _disappearingMessages;
  int get disappearDuration => _disappearDuration;
  bool get autoDeleteMedia => _autoDeleteMedia;
  List<String> get blockedUsers => _blockedUsers;
  List<String> get archivedChats => _archivedChats;
  String? get name => _name;
  String? get photoUrl => _photoUrl;
  String? get bio => _bio;

  SettingsProvider() {
    _loadFromLocal();
    _setupFirestoreListener();
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    _stealthMode = prefs.getBool('stealthMode') ?? false;
    _screenshotProtection = prefs.getBool('screenshotProtection') ?? true;
    _disappearingMessages = prefs.getBool('global_disappearing') ?? false;
    _disappearDuration = prefs.getInt('global_disappear_duration') ?? 60;
    _autoDeleteMedia = prefs.getBool('auto_delete_media') ?? false;
    notifyListeners();
  }

  void _setupFirestoreListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
          if (doc.exists) {
            final data = doc.data()!;
            _readReceipts = data['readReceipts'] ?? true;
            _onlineHidden = data['onlineHidden'] ?? true;
            _lastSeenHidden = data['lastSeenHidden'] ?? true;
            _screenshotProtection = data['screenshotProtection'] ?? _screenshotProtection;
            _blockedUsers = List<String>.from(data['blockedUsers'] ?? []);
            _archivedChats = List<String>.from(data['archivedChats'] ?? []);
            _name = data['name'];
            _photoUrl = data['photoUrl'];
            _bio = data['bio'];
            notifyListeners();
          }
        });
      } else {
        _reset();
      }
    });
  }

  void _reset() {
    _readReceipts = true;
    _onlineHidden = true;
    _lastSeenHidden = true;
    _blockedUsers = [];
    _archivedChats = [];
    _name = null;
    _photoUrl = null;
    _bio = null;
    notifyListeners();
  }

  Future<void> toggleStealthMode(bool value) async {
    _stealthMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stealthMode', value);
    notifyListeners();
  }

  Future<void> toggleScreenshotProtection(bool value) async {
    _screenshotProtection = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('screenshotProtection', value);
    // Persist to Firestore so the other chat participant can read it
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'screenshotProtection': value});
    }
    
    // Dynamically update window flags
    try {
      if (Platform.isAndroid) {
        if (value) {
          FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
        } else {
          FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
        }
      }
    } catch (_) {}
    
    notifyListeners();
  }

  Future<void> toggleReadReceipts(bool value) async {
    _readReceipts = value;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'readReceipts': value});
    }
    notifyListeners();
  }

  Future<void> toggleOnlineHidden(bool value) async {
    _onlineHidden = value;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'onlineHidden': value});
    }
    notifyListeners();
  }

  Future<void> toggleLastSeenHidden(bool value) async {
    _lastSeenHidden = value;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'lastSeenHidden': value});
    }
    notifyListeners();
  }

  Future<void> toggleDisappearingMessages(bool enabled, int duration) async {
    _disappearingMessages = enabled;
    _disappearDuration = duration;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('global_disappearing', enabled);
    await prefs.setInt('global_disappear_duration', duration);
    notifyListeners();
  }

  Future<void> toggleArchiveChat(String chatId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    if (_archivedChats.contains(chatId)) {
      _archivedChats.remove(chatId);
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'archivedChats': FieldValue.arrayRemove([chatId]),
      });
    } else {
      _archivedChats.add(chatId);
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'archivedChats': FieldValue.arrayUnion([chatId]),
      });
    }
    notifyListeners();
  }

  Future<void> toggleBlockUser(String userId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_blockedUsers.contains(userId)) {
      _blockedUsers.remove(userId);
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'blockedUsers': FieldValue.arrayRemove([userId]),
      });
    } else {
      _blockedUsers.add(userId);
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'blockedUsers': FieldValue.arrayUnion([userId]),
      });
    }
    notifyListeners();
  }

  /// Permanently blocks a user — can never be undone via the UI.
  Future<void> blockUserPermanently(String userId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_blockedUsers.contains(userId)) return; // already blocked

    _blockedUsers.add(userId);
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'blockedUsers': FieldValue.arrayUnion([userId]),
    });
    notifyListeners();
  }

  Future<void> updateProfile(String? name, String? bio, String? photoBase64) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final Map<String, dynamic> updates = {};
    if (name != null) {
      updates['name'] = name;
      _name = name;
    }
    if (bio != null) {
      updates['bio'] = bio;
      _bio = bio;
    }
    if (photoBase64 != null) {
      updates['photoUrl'] = photoBase64;
      _photoUrl = photoBase64;
    }

    if (updates.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);
      if (name != null) {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      }
      notifyListeners();
    }
  }

  Future<void> toggleAutoDeleteMedia(bool value) async {
    _autoDeleteMedia = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_delete_media', value);
    notifyListeners();
  }
}
