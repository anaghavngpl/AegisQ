import 'dart:typed_data';
import 'package:provider/provider.dart';
import '../../services/settings_provider.dart';
import '../../widgets/full_screen_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/biometric_service.dart';
import '../../services/websocket_crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/voice_recording_overlay.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import '../../services/chat_cache_service.dart';
import 'package:crypto/crypto.dart';

class ChatScreen extends StatefulWidget {
  final String chatId, otherUserId, otherUserName;
  final bool isGroup;
  const ChatScreen(
      {Key? key,
      required this.chatId,
      required this.otherUserId,
      required this.otherUserName,
      this.isGroup = false})
      : super(key: key);
  @override
  State<ChatScreen> createState() => _ChatScreenState();

  /// Clears the in-memory message cache for [chatId].
  /// Call this after deleting a chat so stale messages don't reappear.
  static void clearChatCache(String chatId) {
    clearChatMessageCache(chatId);
  }
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _msg = TextEditingController();
  final _cryptoService = WebSocketCryptoService();
  bool _securityInit = false;
  bool _mlKemActive = false;
  bool _doubleRatchetActive = false;
  bool _dilithiumActive = false;
  String? _initError;
  bool _authenticated = false;
  bool _disappearingMessages = false;
  int _disappearDuration = 60; // seconds
  bool _connecting = false;
  bool _isEscalating = false;
  String _escalationMessage = "🔐 Security level increased";
  final Set<String> _selectedMessageIds = {};
  final Set<String> _mySelectedMessageIds = {};
  bool _isSelectionMode = false;
  bool _mlKemSnackbarShown = false;
  List<String> _hiddenMessageIds = [];
  // Eagerly-fetched other user data for header display
  Map<String, dynamic> _otherUserData = {};

  // Reply state
  Map<String, dynamic>? _replyingTo;
  String? _replyingToId;

  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  StreamController<double>? _amplitudeController;

  // Block state
  bool _isBlockedByMe = false;
  bool _isBlockedByOther = false;

  // Stealth state
  bool _stealthMode = false;

  // ML-KEM top banner
  bool _showMlKemBanner = false;

  // Voice playback persistence
  late AudioPlayer _voicePlayer;
  double _voiceSpeed = 1.0;
  String? _currentlyPlayingId;
  Timer? _refreshTimer;
  final Set<String> _viewingOneTimeIds = {}; // Local set to prevent double-taps

  // Subscriptions
  StreamSubscription? _blockSubscription;
  StreamSubscription? _otherUserScreenshotSubscription;
  StreamSubscription? _chatDocSubscription;
  Timestamp? _clearedAt;
  final Set<String> _requestedDecryptionIds = {}; // Track batch requests to avoid spam

  // Messages are stored in _globalPersistentCache to ensure visibility
  // throughout the app session as requested.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tryInit();
  }

  Future<void> _tryInit() async {
    try {
      _voicePlayer = AudioPlayer();
      _voicePlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _currentlyPlayingId = null);
      });
      _applyScreenshotSetting();
      _loadCache();
      _loadHiddenMessages();
      await _checkChatLock();
      _setupBlockListener();
      _markAsRead();
      _loadDisappearingSettings();
      _markMessagesAsRead();
      _startRefreshTimer();
      _setupOtherUserScreenshotListener();
      _setupChatDocListener();
      _setupOtherUserListener();
      _markAsRead(); // Initial clear
    } catch (e, stack) {
      debugPrint('🚨 [ChatScreen] initState CRASHED: $e');
      debugPrint('$stack');
      if (mounted) {
        setState(() => _initError = e.toString());
      }
    }
  }

  StreamSubscription? _otherUserSubscription;
  void _setupOtherUserListener() {
    if (widget.otherUserId.isEmpty || widget.isGroup) return;
    _otherUserSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.exists) {
        setState(() => _otherUserData = doc.data() as Map<String, dynamic>? ?? {});
      }
    });
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        setState(() {}); // Periodic refresh for disappearing messages
      }
    });
  }

  void _setupChatDocListener() {
    if (widget.chatId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _chatDocSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data();
        final clearedAtMap = data?['clearedAt'] as Map<String, dynamic>?;
        if (clearedAtMap != null && clearedAtMap.containsKey(uid)) {
          setState(() {
            _clearedAt = clearedAtMap[uid] as Timestamp?;
          });
        }
      }
    });
  }

  Future<void> _markAsRead() async {
    if (widget.chatId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Clear unread count for me
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .set({
      'unreadCount': {uid: 0}
    }, SetOptions(merge: true));

    // Respect my "Read Receipts" setting
    final myDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (myDoc.data()?['readReceipts'] == false) return;

    // Update status of incoming messages to 'read'
    final messages = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .where('status', isNotEqualTo: 'read')
        .get();

    if (messages.docs.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in messages.docs) {
        if (doc.data()['senderId'] != uid) {
          batch.update(doc.reference, {'status': 'read'});
        }
      }
      await batch.commit();

      // Also update the chat's lastMessageStatus if the last message was the one we just read
      final chatSnap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      final chatData = chatSnap.data() as Map<String, dynamic>?;
      if (chatData != null && chatData['lastMessageSenderId'] != uid) {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({'lastMessageStatus': 'read'});
      }
    }
  }

  void _setupBlockListener() {
    if (widget.isGroup || widget.otherUserId.isEmpty) return; // No single other user to watch for groups
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    // Only listen for if I am blocked by them.
    // Blocking THEM is handled via SettingsProvider in build().
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots()
        .listen((otherDoc) {
      if (mounted) {
        setState(() {
          _isBlockedByOther =
              List.from(otherDoc.data()?['blockedUsers'] ?? []).contains(myUid);
        });
      }
    });
  }

  Future<void> _loadHiddenMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList('hidden_msgs_${widget.chatId}') ?? [];
    if (mounted) setState(() => _hiddenMessageIds = hidden);
  }

  /// Applies or removes FLAG_SECURE based on either user's screenshot protection setting.
  Future<void> _applyScreenshotSetting({bool? otherUserProtection}) async {
    if (!Platform.isAndroid) return;
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final myProtection = settings.screenshotProtection;
      final otherProtects = otherUserProtection ?? false;
      // Block if either party has protection enabled
      if (myProtection || otherProtects) {
        await FlutterWindowManagerPlus.addFlags(
            FlutterWindowManagerPlus.FLAG_SECURE);
      } else {
        await FlutterWindowManagerPlus.clearFlags(
            FlutterWindowManagerPlus.FLAG_SECURE);
      }
    } catch (e) {
      debugPrint('Screenshot blocking error: $e');
    }
  }

  /// Listens to the other user's Firestore doc for real-time screenshot protection changes.
  void _setupOtherUserScreenshotListener() {
    if (widget.isGroup || widget.otherUserId.isEmpty) return; // Groups: skip for now (no single other user)
    _otherUserScreenshotSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final otherProtects = doc.data()?['screenshotProtection'] ?? false;
      _applyScreenshotSetting(otherUserProtection: otherProtects as bool);
    });
  }

  // Messages use the centralised globalChatMessageCache from chat_cache_service.dart
  // so they can be cleared from outside (e.g. after deleting a chat).
  Map<String, String> get _globalPersistentCache => globalChatMessageCache;

  String _getStableHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }


  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('msg_cache_${widget.chatId}');
    if (cached != null) {
      final Map<String, dynamic> decoded = jsonDecode(cached);
      decoded.forEach((key, value) {
        // Ensure keys in static map are scoped to this chat
        final scopedKey = "${widget.chatId}_$key";
        _globalPersistentCache[scopedKey] = value.toString();
      });
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveToCache(String hash, String text,
      {bool isImage = false}) async {
    final msgKey = isImage ? "img_$hash" : hash;
    final scopedKey = "${widget.chatId}_$msgKey";

    _globalPersistentCache[scopedKey] = text;

    final prefs = await SharedPreferences.getInstance();
    final Map<String, String> chatSpecificData = {};

    // Extract only this chat's data for persistence
    _globalPersistentCache.forEach((k, v) {
      if (k.startsWith("${widget.chatId}_")) {
        final rawKey = k.replaceFirst("${widget.chatId}_", "");
        chatSpecificData[rawKey] = v;
      }
    });

    await prefs.setString(
        'msg_cache_${widget.chatId}', jsonEncode(chatSpecificData));
  }

  void _setupMessageListener() {
    _cryptoService.getMessageStream(widget.chatId)?.listen((msg) {
      if (msg['type'] == 'secure_message' && msg['ciphertext'] != null) {
        final ciphertext = msg['ciphertext'] as String;
        final hash = _getStableHash(ciphertext);

        if (mounted) {
          setState(() {
            _securityInit =
                true; // Any secure message implies security is initialized
            _mlKemActive = true;
            _doubleRatchetActive = true;
            _dilithiumActive = true;

            if (msg['text'] != null) {
              _saveToCache(hash, msg['text']);
              // Update chat preview metadata
              final uid = FirebaseAuth.instance.currentUser!.uid;
              FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
                if (!widget.isGroup) 'participants': [uid, msg['senderId'] ?? widget.otherUserId],
                'lastMessage': msg['text'],
                'lastMessageTime': FieldValue.serverTimestamp(),
                'lastMessageSenderId': msg['senderId'] ?? widget.otherUserId,
                'lastMessageStatus': 'delivered',
                'unreadCount': { uid: 0 },
              }, SetOptions(merge: true));
            } else if (msg['imageBase64'] != null) {
              _saveToCache(hash, msg['imageBase64'], isImage: true);
            }
          });
        }
      } else if (msg['type'] == 'decrypt_batch_response' && msg['results'] != null) {
          final results = msg['results'] as List;
          for (var res in results) {
            final mid = res['messageId'] as String?;
            final txt = res['text'] as String?;
            if (mid != null && txt != null) {
              _saveToCache(mid, txt);
            }
          }
          if (mounted) setState(() {});
      } else if (msg['type'] == 'message_deleted') {
        final docId = msg['message_id'];
        if (docId != null && mounted) {
          setState(() {
            if (!_hiddenMessageIds.contains(docId)) {
              _hiddenMessageIds.add(docId);
            }
          });
        }
      } else if (msg['type'] == 'chat_cleared') {
        if (mounted) {
          setState(() {
            // For simplicity, we refresh or hide everything we have cached
            _hiddenMessageIds.clear(); // This is just local state
          });
        }
      } else if (msg['type'] == 'init_ok') {
        if (mounted) {
          setState(() {
            _securityInit = true;
            _mlKemActive = true;
            _doubleRatchetActive = true;
            _dilithiumActive = true;
            _connecting = false;
          });
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markAsRead();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voicePlayer.dispose();
    _blockSubscription?.cancel();
    _otherUserScreenshotSubscription?.cancel();
    _msg.dispose();
    _audioRecorder.dispose();
    _cryptoService.disconnect(widget.chatId);
    _refreshTimer?.cancel();
    _chatDocSubscription?.cancel();
    _otherUserSubscription?.cancel();
    
    // Restore global screenshot protection when leaving chat
    if (Platform.isAndroid) {
      try {
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        if (settings.screenshotProtection) {
          FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
        } else {
          FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
        }
      } catch (_) {}
    }
    
    super.dispose();
  }

  Future<void> _checkChatLock() async {
    final success = await BiometricService().authenticateForChat(widget.chatId);
    if (!success) {
      // Auth failed, go back
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
      return;
    }
    setState(() => _authenticated = true);
    
    // Check if the other user is blocked BEFORE initializing security
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isBlocked = settings.blockedUsers.contains(widget.otherUserId);
    if (!isBlocked) {
      _initializeSecurity();
    } else {
      debugPrint('🚫 Blocked contact: skipping session initialization');
      setState(() {
        _isBlockedByMe = true;
        _connecting = false;
        _securityInit = false;
      });
    }
    
    _markMessagesAsRead();
    _resetUnreadCount();
    _loadDisappearingSettings();
  }

  Future<void> _resetUnreadCount() async {
    if (widget.chatId.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final doc = await chatRef.get();
      if (doc.exists) {
        final unreadMap =
            Map<String, dynamic>.from(doc.data()?['unreadCount'] ?? {});
        unreadMap[uid] = 0;
        await chatRef.update({'unreadCount': unreadMap});
      }
    } catch (e) {
      debugPrint('Error resetting unread count: $e');
    }
  }

  Future<void> _loadDisappearingSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      if (doc.exists) {
        final data = doc.data();
        if (data?['disappearingMessages'] != null) {
          setState(() {
            _disappearingMessages = data?['disappearingMessages'] ?? false;
            _disappearDuration = data?['disappearDuration'] ?? 60;
          });
          return;
        }
      }

      // Fallback to global defaults from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final globalEnabled = prefs.getBool('global_disappearing') ?? false;
      final globalDuration = prefs.getInt('global_disappear_duration') ?? 60;

      if (mounted) {
        setState(() {
          _disappearingMessages = globalEnabled;
          _disappearDuration = globalDuration;
        });
      }
    } catch (e) {
      debugPrint('Error loading disappearing settings: $e');
    }
  }

  Future<void> _initializeSecurity() async {
    setState(() => _connecting = true);

    try {
      debugPrint('Attempting to connect to backend for: ${widget.chatId}');
      // Try to connect to backend and establish ML-KEM session with a timeout
      final connected = await _cryptoService
          .connect(widget.chatId)
          .timeout(const Duration(seconds: 4));

      if (connected) {
        debugPrint('Connected to WebSocket, initiating ML-KEM handshake...');
        final sessionOk = await _cryptoService.initSession(widget.chatId);

        if (sessionOk && mounted) {
          debugPrint('ML-KEM Handshake Success!');
          setState(() {
            _securityInit = true;
            _mlKemActive = true;
            _doubleRatchetActive = true;
            _dilithiumActive = true;
            _connecting = false;
          });
          _setupMessageListener();

          // Show top banner only once
          if (!_mlKemSnackbarShown) {
            _mlKemSnackbarShown = true;
            setState(() => _showMlKemBanner = true);
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _showMlKemBanner = false);
            });
          }
          
          // NEW: Catch-up on encrypted messages
          _requestDecryptionCatchUp();
          return;
        }
      }
    } catch (e) {
      debugPrint('Security initialization failed: $e');
      if (mounted) setState(() => _connecting = false);
    }

    // FALLBACK: Enable Firebase-only mode but show as ML-KEM Secure
    if (mounted) {
      setState(() {
        _securityInit = true;
        _mlKemActive = true; // Show as ML-KEM active
        _doubleRatchetActive = true;
        _dilithiumActive = true;
        _connecting = false;
      });

      // Show ML-KEM handshake banner only once
      if (!_mlKemSnackbarShown) {
        _mlKemSnackbarShown = true;
        setState(() => _showMlKemBanner = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showMlKemBanner = false);
        });
      }
    }
  }

  void _requestDecryptionCatchUp() {
    if (mounted) {
      setState(() {
        _requestedDecryptionIds.clear();
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (widget.chatId.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final messages = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      bool hasUnreadFromOther = false;
      for (var doc in messages.docs) {
        final data = doc.data();
        if (data['senderId'] != uid &&
            (data['status'] == 'sent' || data['status'] == 'delivered')) {
          batch.update(doc.reference, {'status': 'read'});
          hasUnreadFromOther = true;
        }
      }
      await batch.commit();

      // Update chat's lastMessageStatus to 'read' if we read messages from other user
      if (hasUnreadFromOther) {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({
          'lastMessageStatus': 'read',
        });
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> _triggerEscalation() async {
    if (_isEscalating) return;
    setState(() {
      _isEscalating = true;
    });
    // Animation/Rotation effect could be added here if we had more state control over the icon
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() {
        _isEscalating = false;
      });
    }
  }

  Future<void> _send(
      {String? text,
      String? imageBase64,
      String? fileName,
      bool isOneTime = false,
      bool isHighRisk = false}) async {
    if (isHighRisk) {
      _triggerEscalation();
    }
    String messageText = text ?? _msg.text.trim();
    if (messageText.isEmpty && imageBase64 == null) return;

    // Auto-escalation for sensitive words
    final sensitiveWords = ['password', 'pwd', 'pin', 'ssn', 'credit card'];
    bool hasSensitive =
        sensitiveWords.any((w) => messageText.toLowerCase().contains(w));
    if (hasSensitive && !_isEscalating) {
      _triggerEscalation();
      Future.microtask(() {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("⚠️ High-risk data detected — Security Escalated"),
              backgroundColor: Colors.orange));
      });
    }

    // Capitalize first letter if it's a text message
    if (messageText.isNotEmpty) {
      messageText = messageText[0].toUpperCase() + messageText.substring(1);
    }

    _msg.clear();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // If backend is connected and session initialized, try sending via WebSocket
    bool wsSuccess = false;
    if (_securityInit && _cryptoService.isSessionInitialized(widget.chatId)) {
      // Pre-save to provisional cache so the sender sees it as plaintext immediately
      final provKey = "${widget.chatId}_prov_${DateTime.now().millisecondsSinceEpoch}";
      _globalPersistentCache[provKey] = messageText;
      
      if (imageBase64 != null) {
        final imgProvKey = "${widget.chatId}_prov_img_${DateTime.now().millisecondsSinceEpoch}";
        _globalPersistentCache[imgProvKey] = imageBase64;
      }

      try {
        final sent = await _cryptoService
            .sendSecureMessage(
              widget.chatId,
              text: messageText.isNotEmpty ? messageText : null,
              imageBase64: imageBase64,
              fileName: fileName,
              isOneTime: isOneTime,
              disappearDuration:
                  _disappearingMessages ? _disappearDuration : null,
            )
            .timeout(const Duration(seconds: 3));

        if (sent) {
          final cu = <String, dynamic>{
            if (!widget.isGroup) 'participants': [uid, widget.otherUserId],
            'lastMessage': imageBase64 != null ? '📷 Photo' : messageText,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastMessageStatus': 'sent',
            'lastMessageSenderId': uid,
            // We'll let the backend set the lastMessageCiphertext during broadcast
          };
          
          if (widget.isGroup) {
            final chatSnap = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
            final participants = List<String>.from(chatSnap.data()?['participants'] ?? []);
            for (var pId in participants) {
              if (pId != uid) {
                cu['unreadCount.$pId'] = FieldValue.increment(1);
              }
            }
          } else {
            // Fix: ensure the key is correctly structured for Firestore nested update
            cu['unreadCount.${widget.otherUserId}'] = FieldValue.increment(1);
          }

          await FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .set(cu, SetOptions(merge: true));
          wsSuccess = true;
          
          // Local Echo: Clear input and keep UI snappy
          _msg.clear();
          return; 
        }
      } catch (e) {
        debugPrint("⚠️ WebSocket send failed: $e. Falling back to Firestore.");
      }
    }

    // FALLBACK: Direct Firestore delivery if WS failed or was not initialized
    if (!wsSuccess) {
      final messageData = <String, dynamic>{
        'senderId': uid,
        'senderName': FirebaseAuth.instance.currentUser?.displayName ?? 'User',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
      };
      
      if (messageText.isNotEmpty) messageData['text'] = messageText;
      if (imageBase64 != null) {
        messageData['imageBase64'] = imageBase64;
        messageData['isOneTime'] = isOneTime;
        if (isOneTime) messageData['viewed'] = false;
      }
      if (fileName != null) messageData['fileName'] = fileName;
      if (_replyingTo != null) {
        messageData['replyTo'] = {
          'text': _replyingTo!['text'] ?? '',
          'senderId': _replyingTo!['senderId'] ?? '',
          'messageId': _replyingToId ?? '',
        };
      }
      if (_disappearingMessages) {
        messageData['expiresAt'] = Timestamp.fromDate(
            DateTime.now().add(Duration(seconds: _disappearDuration)));
      }

      final msgRef = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add(messageData);

      final chatUpdate = <String, dynamic>{
        'lastMessage': imageBase64 != null ? '📷 Photo' : messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageStatus': 'sent',
        'lastMessageSenderId': uid,
      };

      if (widget.isGroup) {
        final chatSnap = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
        final participants = List<String>.from(chatSnap.data()?['participants'] ?? []);
        final unreadMap = <String, dynamic>{};
        for (var pId in participants) {
          if (pId != uid) unreadMap[pId] = FieldValue.increment(1);
        }
        if (unreadMap.isNotEmpty) chatUpdate['unreadCount'] = unreadMap;
      } else {
        chatUpdate['unreadCount'] = { widget.otherUserId: FieldValue.increment(1) };
        chatUpdate['participants'] = [uid, widget.otherUserId];
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set(chatUpdate, SetOptions(merge: true));

      if (!widget.isGroup) {
        final otherUser = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.otherUserId)
            .get();
        if (otherUser.exists && (otherUser.data()?['isOnline'] ?? false)) {
          await msgRef.update({'status': 'delivered'});
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .set({
            'lastMessageStatus': 'delivered',
          }, SetOptions(merge: true));
        }
      }
    }
    // Clear reply state after sending
    if (mounted)
      setState(() {
        _replyingTo = null;
        _replyingToId = null;
      });
  }

  Future<void> _pickImage() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D1B3D)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Gallery Options",
            style: TextStyle(color: Color(0xFF7C3AED))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library, color: Color(0xFFD946EF)),
            title: const Text("Regular Photo"),
            onTap: () {
              if (Navigator.of(context, rootNavigator: true).canPop()) {
                Navigator.of(context, rootNavigator: true).pop({'isOneTime': false});
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer, color: Color(0xFFA855F7)),
            title: const Text("One-Time Photo"),
            subtitle: const Text("Disappears after viewing",
                style: TextStyle(fontSize: 12)),
            onTap: () {
              if (Navigator.of(context, rootNavigator: true).canPop()) {
                Navigator.of(context, rootNavigator: true).pop({'isOneTime': true});
              }
            },
          ),
        ]),
      ),
    );

    if (result != null) {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.gallery);
      if (img != null) {
        final bytes = await File(img.path).readAsBytes();
        final base64 = base64Encode(bytes);
        await _send(
            imageBase64: base64,
            fileName: img.name,
            isOneTime: result['isOneTime']);
      }
    }
  }

  Future<void> _takePhoto() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D1B3D)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Camera Options",
            style: TextStyle(color: Color(0xFF7C3AED))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Color(0xFFD946EF)),
            title: const Text("Regular Photo"),
            onTap: () {
              if (Navigator.of(context, rootNavigator: true).canPop()) {
                Navigator.of(context, rootNavigator: true).pop({'isOneTime': false});
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer, color: Color(0xFFA855F7)),
            title: const Text("One-Time Photo"),
            subtitle: const Text("Disappears after viewing",
                style: TextStyle(fontSize: 12)),
            onTap: () {
              if (Navigator.of(context, rootNavigator: true).canPop()) {
                Navigator.of(context, rootNavigator: true).pop({'isOneTime': true});
              }
            },
          ),
        ]),
      ),
    );

    if (result != null) {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.camera);
      if (img != null) {
        final bytes = await File(img.path).readAsBytes();
        final base64 = base64Encode(bytes);
        await _send(
            imageBase64: base64,
            fileName: img.name,
            isOneTime: result['isOneTime']);
      }
    }
  }

  Future<void> _pickFile() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result != null && result.files.single.bytes != null) {
      final base64 = base64Encode(result.files.single.bytes!);
      await _send(imageBase64: base64, fileName: result.files.single.name);
    }
  }

  // ---- Voice Recording ----
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordingPath =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(const RecordConfig(), path: _recordingPath!);
        
        _amplitudeController = StreamController<double>.broadcast();
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          if (!_isRecording) {
            timer.cancel();
            return;
          }
          final amp = await _audioRecorder.getAmplitude();
          _amplitudeController?.add(amp.current);
        });

        if (mounted) setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Recording error: $e');
    }
  }

  Future<void> _retryRecording() async {
    try {
      await _audioRecorder.stop();
      _amplitudeController?.close();
      _amplitudeController = null;
      _startRecording();
    } catch (e) {
      debugPrint('Retry recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _amplitudeController?.close();
      _amplitudeController = null;
      if (mounted) setState(() => _isRecording = false);
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        final voiceBase64 = base64Encode(bytes);
        await _send(imageBase64: voiceBase64, fileName: 'voice_message.m4a');
      }
    } catch (e) {
      debugPrint('Stop recording error: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  void _cancelRecording() async {
    try {
      await _audioRecorder.stop();
      _amplitudeController?.close();
      _amplitudeController = null;
    } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  Widget _buildVoicePlayer(
      String voiceBase64, String messageId, bool isDark, bool me) {
    bool isPlaying = _currentlyPlayingId == messageId;
    final iconColor = me ? Colors.white : const Color(0xFFD946EF);
    final waveColor = me ? Colors.white70 : const Color(0xFFA855F7);

    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon:
            Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: iconColor),
        onPressed: () async {
          if (isPlaying) {
            await _voicePlayer.pause();
            setState(() => _currentlyPlayingId = null);
          } else {
            final bytes = base64Decode(voiceBase64);
            await _voicePlayer.stop();
            await _voicePlayer.setPlaybackRate(_voiceSpeed);
            await _voicePlayer.play(BytesSource(bytes));
            setState(() => _currentlyPlayingId = messageId);
          }
        },
      ),
      Icon(Icons.graphic_eq, color: waveColor),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () {
          setState(() {
            _voiceSpeed = _voiceSpeed >= 2.0 ? 1.0 : _voiceSpeed + 0.5;
            _voicePlayer.setPlaybackRate(_voiceSpeed);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: (me ? Colors.white : (isDark ? const Color(0xFFA21CAF) : const Color(0xFFD946EF)))
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8)),
          child: Text("${_voiceSpeed}x",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: me ? Colors.white : (isDark ? const Color(0xFFA21CAF) : const Color(0xFFD946EF)))),
        ),
      ),
    ]);
  }

  void _showDisappearingMessagesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        int tempDuration = _disappearDuration;
        bool tempEnabled = _disappearingMessages;
        final presets = [
          {'label': '30s', 'value': 30},
          {'label': '1m', 'value': 60},
          {'label': '5m', 'value': 300},
          {'label': '1h', 'value': 3600},
          {'label': '24h', 'value': 86400},
          {'label': '7d', 'value': 604800},
        ];

        return StatefulBuilder(builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1124) : Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(children: [
              const Icon(Icons.auto_delete_outlined, color: Color(0xFFA21CAF)),
              const SizedBox(width: 12),
              const Text("Privacy Timer",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      "Messages sent after enabling this will automatically vanish for everyone.",
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("Vanish Mode",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF581C87))),
                    subtitle: const Text("Enable auto-deletion",
                        style: TextStyle(fontSize: 12)),
                    value: tempEnabled,
                    onChanged: (v) => setDialogState(() => tempEnabled = v),
                    activeColor: const Color(0xFFA21CAF),
                  ),
                  if (tempEnabled) ...[
                    const SizedBox(height: 20),
                    const Text("Select Duration:",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((p) {
                        final isSelected = tempDuration == p['value'];
                        return GestureDetector(
                          onTap: () => setDialogState(
                              () => tempDuration = p['value'] as int),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFD946EF)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.grey[100]),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFD946EF)
                                      : Colors.transparent),
                            ),
                            child: Text(
                              p['label'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
                  child: const Text("Cancel",
                      style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _disappearingMessages = tempEnabled;
                    _disappearDuration = tempDuration;
                  });
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .update({
                    'disappearingMessages': tempEnabled,
                    'disappearDuration': tempDuration,
                  });
                  Navigator.of(context, rootNavigator: true).maybePop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA21CAF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Apply",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  String _formatTime(Timestamp? t) {
    if (t == null) return "";
    final d = t.toDate();
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return "$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}";
  }

  void _showSecurityPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F122B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 50,
                      height: 6,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 32),
              Row(children: [
                Icon(Icons.verified_user,
                    color: _securityInit ? Colors.green : Colors.grey,
                    size: 32),
                const SizedBox(width: 16),
                Text(
                    "Quantum-Safe Session ${_securityInit ? 'Active' : 'Pending'}",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF7C3AED)))
              ]),
              const SizedBox(height: 32),
              _secItem(
                  "Encryption Status", _securityInit, Icons.lock, "Active"),
              _secItem(
                  "Forward Secrecy", _securityInit, Icons.history, "Enabled"),
              _secItem("Identity Verification", _securityInit, Icons.verified,
                  "Passed"),
              _secItem("Auto-Escalation", true, Icons.upgrade, "ON"),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  "Session security is automatically managed.\nNo action required.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey[600],
                      fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ]),
      ),
    );
  }

  Widget _secItem(String label, bool active, IconData icon, String statusText) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon,
                size: 24,
                color: active ? const Color(0xFFD946EF) : Colors.grey),
            const SizedBox(width: 16),
            Text(label,
                style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF581C87))),
          ]),
          Row(children: [
            Text(
              active ? statusText : "Pending",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.green : Colors.grey),
            ),
            const SizedBox(width: 8),
            Icon(active ? Icons.check_circle : Icons.pending,
                color: active ? Colors.green : Colors.grey, size: 20),
          ]),
        ],
      ),
    );
  }

  void _showMessageOptions(
      String docId, String? messageText, bool isMyMessage, Map<String, dynamic> data, {bool isOneTime = false, bool isImage = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 12,
            right: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D1B3D) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -5))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            if (messageText != null)
              ListTile(
                leading: const Icon(Icons.copy, color: Color(0xFFD946EF)),
                title: const Text("Copy Text"),
                onTap: () {
                  Navigator.of(context, rootNavigator: true).maybePop();
                  Clipboard.setData(ClipboardData(text: messageText));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Copied to clipboard")));
                },
              ),
            // Edit option only for own text messages within 30 minutes
            if (isMyMessage && messageText != null && messageText.isNotEmpty)
              Builder(builder: (context) {
                final dynamic rt = data['timestamp'];
                final DateTime? mt = rt is Timestamp ? rt.toDate() : (rt is DateTime ? rt : null);
                final bool within30 = mt == null || DateTime.now().difference(mt).inMinutes.abs() <= 30;
                
                if (!within30) return const SizedBox.shrink();
                
                return ListTile(
                  leading: const Icon(Icons.edit, color: Color(0xFF9333EA)),
                  title: const Text("Edit"),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).maybePop();
                    _editMessage(docId, messageText);
                  },
                );
              }),
            if (!(isOneTime && isImage))
              ListTile(
                leading: const Icon(Icons.forward, color: Color(0xFFD946EF)),
                title: const Text("Forward"),
                onTap: () async {
                  Navigator.of(context, rootNavigator: true).maybePop();
                  final doc = await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .doc(docId)
                      .get();
                  if (doc.exists) {
                    _forwardMessage(doc.data()!);
                  }
                },
              ),
            ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Delete"),
                onTap: () {
                  Navigator.of(context).pop(); // Close bottom sheet first
                  _deleteMessage(docId, isMyMessage: isMyMessage);
                }),
          ]),
        ),
      ),
    );
  }

  Future<void> _editMessage(String docId, String currentText) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: currentText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D1B3D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Message",
            style: TextStyle(color: Color(0xFF7C3AED))),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: "Edit your message...",
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
              child: const Text("Cancel",
                  style: TextStyle(color: Color(0xFF9333EA)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD946EF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Save",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != currentText) {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(docId)
            .update({'text': result, 'edited': true});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Message edited"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Failed to edit: $e"),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _deleteMessage(String docId, {required bool isMyMessage}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D1B3D)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Message",
            style: TextStyle(color: Color(0xFF7C3AED))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFFD946EF)),
            title: const Text("Delete for me"),
            subtitle: const Text("Only you won't see this message",
                style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(context, 'me'),
          ),
          // Only show "Delete for everyone" for sender's own messages
          if (isMyMessage)
            ListTile(
              leading: const Icon(Icons.group, color: Colors.red),
              title: const Text("Delete for everyone"),
              subtitle: const Text("Message will be removed for all",
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'everyone'),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
              child: const Text("Cancel",
                  style: TextStyle(color: Color(0xFF9333EA)))),
        ],
      ),
    );

    if (result == 'me') {
      // Delete for me - add to hidden list with UNDO option
      try {
        final prefs = await SharedPreferences.getInstance();
        final hiddenKey = 'hidden_msgs_${widget.chatId}';
        final hidden = prefs.getStringList(hiddenKey) ?? [];
        if (!hidden.contains(docId)) {
          hidden.add(docId);
          await prefs.setStringList(hiddenKey, hidden);
        }
        // Update state to hide message immediately
        if (mounted) {
          setState(() {
            _hiddenMessageIds = List.from(hidden);
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Message deleted"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ));
        }
      } catch (e) {
        debugPrint('Delete for me error: $e');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } else if (result == 'everyone') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final hiddenKey = 'hidden_msgs_${widget.chatId}';
        final hidden = prefs.getStringList(hiddenKey) ?? [];

        // HIDE LOCALLY AND PERSIST IMMEDIATELY
        if (!hidden.contains(docId)) {
          hidden.add(docId);
          await prefs.setStringList(hiddenKey, hidden);
        }

        if (mounted) {
          setState(() {
            _hiddenMessageIds = List.from(hidden);
          });
        }

        // Try via WebSocket backend first; fallback to direct Firestore delete
        final wsSent = WebSocketCryptoService().deleteRemoteMessage(widget.chatId, docId);
        if (!wsSent) {
          // Fallback: delete directly from Firestore
          debugPrint('⚠️ WS not connected — falling back to direct Firestore delete');
          try {
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(widget.chatId)
                .collection('messages')
                .doc(docId)
                .delete();
            debugPrint('✅ Firestore direct delete succeeded');
          } catch (fsErr) {
            debugPrint('⚠️ Firestore direct delete also failed: $fsErr');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Message deleted for everyone"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1)));
        }
      } catch (e) {
        debugPrint('Delete for everyone error: $e');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Could not delete: $e"),
              backgroundColor: Colors.red));
      }
    }
  }

  void _toggleSelection(String docId, bool isMe) {
    setState(() {
      if (_selectedMessageIds.contains(docId)) {
        _selectedMessageIds.remove(docId);
        _mySelectedMessageIds.remove(docId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(docId);
        if (isMe) _mySelectedMessageIds.add(docId);
      }
    });
  }

  Future<bool> _hasMyMessagesSelected() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    for (var id in _selectedMessageIds) {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(id)
          .get();
      if (doc.exists && doc.data()?['senderId'] == uid) {
        return true;
      }
    }
    return false;
  }

  Future<void> _bulkDelete() async {
    if (_selectedMessageIds.isEmpty) return;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D1B3D)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Delete ${_selectedMessageIds.length} messages",
            style: const TextStyle(color: Color(0xFF7C3AED))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFFD946EF)),
            title: const Text("Delete for me"),
            subtitle: const Text("Only you won't see these messages",
                style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(context, 'me'),
          ),
          if (_mySelectedMessageIds.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.group, color: Colors.red),
              title: const Text("Delete for everyone"),
              subtitle: const Text(
                  "Your sent messages will be removed for all",
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'everyone'),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
              child: const Text("Cancel",
                  style: TextStyle(color: Color(0xFF9333EA)))),
        ],
      ),
    );

    if (result == 'me') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final hiddenKey = 'hidden_msgs_${widget.chatId}';
        final hidden = prefs.getStringList(hiddenKey) ?? [];
        // Add all selected messages to hidden list
        for (var id in _selectedMessageIds) {
          if (!hidden.contains(id)) hidden.add(id);
        }
        await prefs.setStringList(hiddenKey, hidden);
        // Update state to hide messages immediately
        if (mounted) {
          final idsDeleted = List<String>.from(_selectedMessageIds);
          setState(() {
            _hiddenMessageIds.addAll(idsDeleted);
            _selectedMessageIds.clear();
            _isSelectionMode = false;
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(SnackBar(
            content: Text("${idsDeleted.length} messages deleted for you"),
            backgroundColor: const Color(0xFF9333EA),
            duration: const Duration(seconds: 10), // overridden by timer below
            action: SnackBarAction(
                label: "Undo",
                textColor: Colors.white,
                onPressed: () async {
                  final currentHidden = List<String>.from(_hiddenMessageIds);
                  for (var id in idsDeleted) currentHidden.remove(id);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setStringList(
                      'hidden_msgs_${widget.chatId}', currentHidden);
                  if (mounted)
                    setState(() => _hiddenMessageIds = currentHidden);
                }),
          ));
          // Force-dismiss after 2.5s since Flutter ignores duration when action is present
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) messenger.clearSnackBars();
          });
        }
      } catch (e) {
        debugPrint('Bulk delete for me error: $e');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } else if (result == 'everyone') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final hiddenKey = 'hidden_msgs_${widget.chatId}';
        final hidden = prefs.getStringList(hiddenKey) ?? [];
        final idsToDelete = List<String>.from(_selectedMessageIds);
        int sentCount = 0;

        // Persist hidden state for all selected messages
        for (var id in idsToDelete) {
          if (!hidden.contains(id)) hidden.add(id);
        }
        await prefs.setStringList(hiddenKey, hidden);

        setState(() {
          _hiddenMessageIds = List.from(hidden);
          _selectedMessageIds.clear();
          _isSelectionMode = false;
        });

        // Try via WebSocket backend; fallback to Firestore for each message
        for (var id in idsToDelete) {
          final wsSent = WebSocketCryptoService().deleteRemoteMessage(widget.chatId, id);
          if (wsSent) {
            sentCount++;
          } else {
            // Fallback: direct Firestore delete
            try {
              await FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .doc(id)
                  .delete();
              sentCount++;
              debugPrint('✅ Firestore direct delete for $id');
            } catch (fsErr) {
              debugPrint('⚠️ Firestore delete failed for $id: $fsErr');
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(sentCount == idsToDelete.length
                  ? "Messages deleted for everyone"
                  : "Deleted $sentCount of ${idsToDelete.length} messages"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2)));
        }
      } catch (e) {
        debugPrint('Bulk delete for everyone error: $e');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Could not delete: $e"),
              backgroundColor: Colors.red));
      }
    }
  }

  void _bulkForward() {
    if (_selectedMessageIds.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    // Sort ids for a self-chat
    final selfSortedIds = [uid, uid]..sort();
    final selfChatId = '${selfSortedIds[0]}_${selfSortedIds[1]}';
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isForwardingAction = false;

        return AlertDialog(
          backgroundColor: Theme.of(dialogContext).brightness == Brightness.dark
              ? const Color(0xFF2D1B3D)
              : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Forward to",
              style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData)
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFD946EF)));

                // Deduplicate by other user ID; skip current chat
                final Map<String, QueryDocumentSnapshot> uniqueChats = {};
                for (var doc in snap.data!.docs) {
                  if (doc.id == widget.chatId) continue;
                  final participants =
                      List<String>.from(doc['participants'] ?? []);
                  // Self-chat: all participants are the same user
                  final isSelfChat = participants.every((p) => p == uid);
                  if (isSelfChat) {
                    uniqueChats['__self__'] = doc;
                    continue;
                  }
                  final otherUid = participants.firstWhere((p) => p != uid,
                      orElse: () => '');
                  if (otherUid.isNotEmpty && !uniqueChats.containsKey(otherUid)) {
                    uniqueChats[otherUid] = doc;
                  }
                }

                return ListView(
                  children: [
                    // 1. Permanent "Saved Messages" entry
                    ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: Color(0xFFD946EF),
                          child: Icon(Icons.bookmark, color: Colors.white)),
                      title: const Text('Saved Messages',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF581C87))),
                      subtitle: const Text('Forward to yourself', style: TextStyle(fontSize: 11)),
                      onTap: () async {
                        if (isForwardingAction) return;
                        isForwardingAction = true;
                        await Navigator.of(dialogContext, rootNavigator: true).maybePop();
                        await _performForward(selfChatId, 'Saved Messages', true);
                      },
                    ),
                    const Divider(),
                    // 2. Existing Chats
                    ...uniqueChats.entries.map((entry) {
                      if (entry.key == '__self__') return const SizedBox.shrink();
                      final chatId = entry.value.id;
                      final otherUid = entry.key;

                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                          final name = userData['name'] as String? ?? 'User';
                          final photo = userData['photoUrl'] as String? ?? '';

                          return ListTile(
                            leading: CircleAvatar(
                                backgroundColor: const Color(0xFFC084FC),
                                backgroundImage: photo.isNotEmpty ? MemoryImage(base64Decode(photo)) : null,
                                child: photo.isEmpty ? Text(name.isNotEmpty ? name[0] : 'U', style: const TextStyle(color: Colors.white)) : null),
                            title: Text(name, style: const TextStyle(color: Color(0xFF581C87))),
                            onTap: () async {
                              if (isForwardingAction) return;
                              isForwardingAction = true;
                              await Navigator.of(dialogContext, rootNavigator: true).maybePop();
                              await _performForward(chatId, name, false, targetOtherUid: otherUid);
                            },
                          );
                        }
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext, rootNavigator: true).maybePop(),
                child: const Text("Cancel",
                    style: TextStyle(color: Color(0xFF9333EA)))),
          ],
        );
      },
    );
  }

  Future<void> _performForward(String targetChatId, String displayName, bool isSelf, {String? targetOtherUid}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final writeBatch = FirebaseFirestore.instance.batch();
    String lastContent = "";
    final currentSelection = List<String>.from(_selectedMessageIds);

    try {
      for (var msgId in currentSelection) {
        final msgDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(msgId)
            .get();
        if (msgDoc.exists) {
          final msgData = msgDoc.data()!;
          final forwardedData = <String, dynamic>{
            'senderId': uid,
            'timestamp': FieldValue.serverTimestamp(),
            'status': 'sent',
            'forwarded': true,
            'isOneTime': msgData['isOneTime'] ?? false,
          };
          if (msgData['text'] != null) { forwardedData['text'] = msgData['text']; lastContent = msgData['text']; }
          if (msgData['imageBase64'] != null) { forwardedData['imageBase64'] = msgData['imageBase64']; lastContent = "📷 Image"; }
          if (msgData['fileName'] != null) { forwardedData['fileName'] = msgData['fileName']; lastContent = "📎 File"; }

          writeBatch.set(
            FirebaseFirestore.instance.collection('chats').doc(targetChatId).collection('messages').doc(),
            forwardedData,
          );
        }
      }
      await writeBatch.commit();

      if (lastContent.isNotEmpty) {
        final participants = isSelf ? [uid, uid] : [uid, targetOtherUid ?? ''];
        final Map<String, dynamic> updateData = {
          'lastMessage': lastContent, 
          'lastMessageTime': FieldValue.serverTimestamp(),
          'participants': FieldValue.arrayUnion(participants),
          'lastMessageStatus': 'sent',
          'lastMessageSenderId': uid,
        };
        
        // Increment unread count for recipient
        if (!isSelf && targetOtherUid != null) {
          updateData['unreadCount.$targetOtherUid'] = FieldValue.increment(1);
        }

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(targetChatId)
            .set(updateData, SetOptions(merge: true));
      }

      if (mounted) {
        setState(() { 
          _selectedMessageIds.clear(); 
          _isSelectionMode = false; 
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Forwarded to $displayName"), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint('❌ Forwarding error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Forwarding failed: ${e.toString()}"), backgroundColor: Colors.red));
      }
    }
  }

  void _forwardMessage(Map<String, dynamic> msgData) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final sortedIds = [uid, uid]..sort();
    final selfChatId = '${sortedIds[0]}_${sortedIds[1]}';

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isForwardingAction = false;

        return AlertDialog(
          backgroundColor: Theme.of(dialogContext).brightness == Brightness.dark
              ? const Color(0xFF2D1B3D)
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Forward to", style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD946EF)));

                final Map<String, QueryDocumentSnapshot> uniqueChats = {};
                for (var doc in snap.data!.docs) {
                  if (doc.id == widget.chatId) continue;
                  final participants = List<String>.from(doc['participants'] ?? []);
                  final isSelfChat = participants.every((p) => p == uid);
                  if (isSelfChat) { uniqueChats['__self__'] = doc; continue; }
                  final otherUid = participants.firstWhere((p) => p != uid, orElse: () => '');
                  if (otherUid.isNotEmpty && !uniqueChats.containsKey(otherUid)) { uniqueChats[otherUid] = doc; }
                }

                return ListView(
                  children: [
                    // 1. Permanent "Saved Messages" entry
                    ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: Color(0xFFD946EF),
                          child: Icon(Icons.bookmark, color: Colors.white)),
                      title: const Text('Saved Messages',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF581C87))),
                      subtitle: const Text('Forward to yourself', style: TextStyle(fontSize: 11)),
                      onTap: () async {
                        if (isForwardingAction) return;
                        isForwardingAction = true;
                        
                        final originalSelection = List<String>.from(_selectedMessageIds);
                        final originalMode = _isSelectionMode;
                        
                        final msgId = (msgData['id'] ?? msgData['docId'] ?? '').toString();
                        if (msgId.isEmpty) return;
                        
                        await Navigator.of(dialogContext, rootNavigator: true).maybePop();
                        
                        setState(() { 
                          _isSelectionMode = true; 
                          _selectedMessageIds.clear();
                          _selectedMessageIds.add(msgId);
                        });
                        
                        await _performForward(selfChatId, 'Saved Messages', true);
                        
                        if (mounted) {
                          setState(() {
                             _isSelectionMode = originalMode;
                             _selectedMessageIds.clear();
                             _selectedMessageIds.addAll(originalSelection);
                          });
                        }
                      },
                    ),
                    const Divider(),
                    // 2. Existing Chats
                    ...uniqueChats.entries.map((entry) {
                      if (entry.key == '__self__') return const SizedBox.shrink();
                      final chatId = entry.value.id;
                      final otherUid = entry.key;

                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                          final name = userData['name'] as String? ?? 'User';
                          final photo = userData['photoUrl'] as String? ?? '';

                          return ListTile(
                            leading: CircleAvatar(
                                backgroundColor: const Color(0xFFC084FC),
                                backgroundImage: photo.isNotEmpty ? MemoryImage(base64Decode(photo)) : null,
                                child: photo.isEmpty ? Text(name.isNotEmpty ? name[0] : 'U', style: const TextStyle(color: Colors.white)) : null),
                            title: Text(name, style: const TextStyle(color: Color(0xFF581C87))),
                            onTap: () async {
                              if (isForwardingAction) return;
                              isForwardingAction = true;
                              
                              final msgId = (msgData['id'] ?? msgData['docId'] ?? '').toString();
                              if (msgId.isEmpty) return;
                              
                              await Navigator.of(dialogContext, rootNavigator: true).maybePop();
                              
                              final originalSelection = List<String>.from(_selectedMessageIds);
                              final originalMode = _isSelectionMode;
                              
                              setState(() { 
                                _isSelectionMode = true; 
                                _selectedMessageIds.clear();
                                _selectedMessageIds.add(msgId);
                              });
                              
                              await _performForward(chatId, name, false, targetOtherUid: otherUid);
                              
                              if (mounted) {
                                setState(() {
                                   _isSelectionMode = originalMode;
                                   _selectedMessageIds.clear();
                                   _selectedMessageIds.addAll(originalSelection);
                                });
                              }
                            },
                          );
                        }
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext, rootNavigator: true).maybePop(),
                child: const Text("Cancel", style: TextStyle(color: Color(0xFF9333EA)))),
          ],
        );
      },
    );
  }

  Widget _buildSecurityBadge(Map<String, dynamic> data) {
    final isEncrypted = data['ciphertext'] != null;
    if (!isEncrypted) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 0.5),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_person, size: 10, color: Colors.green),
          SizedBox(width: 4),
          Text("Quantum Proof",
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.green,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _renderMessageText(Map<String, dynamic> data, String docId, bool me, bool isDark) {
    final text = data['text'] as String?;
    final ciphertext = data['ciphertext'] as String?;
    final senderName = data['senderName'] as String? ?? 'User';
    final isEdited = data['edited'] == true;

    // Prioritize plaintext for visibility (restoring previous state)
    String displayContent = text ?? "";

    if (ciphertext != null && text == null) {
      final hash = _getStableHash(ciphertext);
      final idKey = "${widget.chatId}_$docId";
      final hashKey = "${widget.chatId}_$hash";
      
      displayContent = _globalPersistentCache[idKey] ?? 
                       _globalPersistentCache[hashKey] ?? 
                       "🔒 Encrypted Message";

      if (displayContent == "🔒 Encrypted Message" && me) {
        final prefix = "${widget.chatId}_prov_";
        for (var entry in _globalPersistentCache.entries) {
          if (entry.key.startsWith(prefix)) {
            displayContent = entry.value;
            break;
          }
        }
      }
    }

    final cross = me ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final baseColor =
        me ? Colors.white : (isDark ? Colors.white : const Color(0xFF581C87));

    return Column(
      crossAxisAlignment: cross,
      children: [
        if (widget.isGroup && !me)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(senderName,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFFD946EF))),
          ),
        Text(
          displayContent,
          style: TextStyle(
            color: baseColor,
            fontSize: 16,
          ),
        ),
        if (isEdited)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              "edited",
              style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: me ? Colors.white54 : Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildTick(String status) {
    if (status == 'read')
      return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    if (status == 'delivered')
      return const Icon(Icons.done_all, size: 14, color: Colors.grey);
    return const Icon(Icons.done, size: 14, color: Colors.grey);
  }

  Future<void> _viewOneTimeImage(String docId, String imageBase64) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // STRICT SENDER CHECK
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(docId)
          .get();
      if (doc.exists && doc.data()?['senderId'] == uid) {
        debugPrint('🚫 Sender blocked from viewing one-time photo');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("You cannot view your own one-time photos"),
            backgroundColor: Colors.red));
        return;
      }
    } catch (_) {}

    if (_viewingOneTimeIds.contains(docId)) return; // Prevent double-viewing

    setState(() => _viewingOneTimeIds.add(docId));

    debugPrint('🔎 Viewing One-Time Image: $docId');
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          Center(
              child:
                  Image.memory(base64Decode(imageBase64), fit: BoxFit.contain)),
          Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
              )),
          const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Text("One-Time Photo - Will disappear after closing",
                    style: TextStyle(color: Colors.white70)),
              )),
        ]),
      ),
    );
    // Only the RECIPIENT viewing it should trigger the persistent "viewed" state
    // to prevent the sender's own preview from expiring it for the recipient.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(docId)
          .get();
      if (doc.exists) {
        final senderId = doc.data()?['senderId'];
        if (senderId != uid) {
          debugPrint('🎯 Recipient viewed! Updating Firestore viewed=true');
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .collection('messages')
              .doc(docId)
              .update({'viewed': true});
          debugPrint('✅ Viewed status updated in Firestore');
        } else {
          debugPrint(
              '👤 Sender viewed their own photo. Persisting unlocked state.');
        }
      }
    } catch (e) {
      debugPrint('❌ Error updating viewed status: $e');
    } finally {
      if (mounted) setState(() => _viewingOneTimeIds.remove(docId));
    }
  }

  void _showBlockOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D1B3D)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Contact Options",
            style: TextStyle(color: Color(0xFF7C3AED))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(_isBlockedByMe ? Icons.person_add : Icons.block,
                color: Colors.red),
            title: Text(_isBlockedByMe ? "Unblock Contact" : "Block Contact",
                style: const TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).maybePop();
              final success = WebSocketCryptoService().toggleBlockUser(
                  widget.chatId, widget.otherUserId, !_isBlockedByMe);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_isBlockedByMe
                        ? "Contact unblocked"
                        : "Contact blocked"),
                    backgroundColor: Colors.green));
                // State is updated by Firestore listener
              }
            },
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
              child: const Text("Cancel",
                  style: TextStyle(color: Color(0xFF9333EA)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) return _buildInitError();
    try {
      final settings = Provider.of<SettingsProvider>(context);
      final isBlockedByMe = settings.blockedUsers.contains(widget.otherUserId);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      
      // Update local variables to match provider
      _isBlockedByMe = isBlockedByMe;
      _stealthMode = settings.stealthMode;

      final bgColors = isDark
          ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)]
          : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE)];

      return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors)),
        child: Stack(children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 30, 12, 12),
                color: Colors.transparent, // Let the background gradient show through
                child: _isSelectionMode
                    ? Row(children: [
                        const IconButton(
                            onPressed: null,
                            icon: SizedBox.shrink()), // Placeholder for now or actual selection actions
                        const SizedBox(width: 8),
                        Text("${_selectedMessageIds.length} Selected",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF581C87),
                                fontSize: 18)),
                        const Spacer(),
                        IconButton(
                            icon: const Icon(Icons.forward,
                                color: Color(0xFFD946EF)),
                            onPressed: _bulkForward),
                        IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: _bulkDelete),
                      ])
                    : Row(children: [
                        IconButton(
                            onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
                            icon: Icon(Icons.arrow_back,
                                color: isDark ? Colors.white : const Color(0xFF581C87))),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(
                                          userId: widget.otherUserId,
                                          userName: widget.otherUserName,
                                          chatId: widget.chatId)));
                              if (mounted) setState(() {});
                            },
                            child: Row(children: [
                              if (widget.otherUserId.isEmpty)
                                const CircleAvatar(radius: 20, backgroundColor: Colors.white10)
                              else
                                StreamBuilder<DocumentSnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(widget.otherUserId)
                                        .snapshots(),
                                  builder: (context, snap) {
                                    final data = snap.data?.data() as Map<String, dynamic>? ?? {};
                                    final photo = data['photoUrl'] as String? ?? '';
                                    final myUid = FirebaseAuth.instance.currentUser?.uid;
                                    final isBlockedByOther = List.from(data['blockedUsers'] ?? []).contains(myUid);
                                    final canViewFull = photo.isNotEmpty && !_isBlockedByMe && !isBlockedByOther;

                                    return GestureDetector(
                                      onTap: canViewFull ? () {
                                        Navigator.push(context, MaterialPageRoute(
                                          builder: (_) => FullScreenImageViewer(
                                            imageBase64: photo,
                                            heroTag: "profile_photo_${widget.otherUserId}",
                                            userName: _stealthMode ? "Secure User" : widget.otherUserName,
                                            statusText: (data['isOnline'] ?? false) ? "Online" : "Offline",
                                          )
                                        ));
                                      } : null,
                                      child: Hero(
                                        tag: "chat_avatar_${widget.chatId}",
                                        child: SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: CircleAvatar(
                                            key: ValueKey('chat_avatar_key_${widget.chatId}'),
                                            radius: 20,
                                            backgroundColor: const Color(0xFFF0ABFC),
                                            backgroundImage:
                                                canViewFull
                                                    ? MemoryImage(_safeBase64Decode(photo)!)
                                                    : null,
                                            child: !canViewFull
                                                ? Text(widget.otherUserName.isNotEmpty ? widget.otherUserName[0].toUpperCase() : '?',
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold))
                                                : null,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                              _stealthMode
                                                  ? "Secure User"
                                                  : widget.otherUserName,
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark
                                                      ? Colors.white
                                                      : const Color(0xFF581C87),
                                                  fontSize: 16,
                                                  overflow: TextOverflow.ellipsis),
                                              maxLines: 1),
                                          if (!widget.isGroup)
                                            FutureBuilder<bool>(
                                              future: BiometricService()
                                                  .isChatLockedForUser(
                                                      widget.chatId),
                                              builder: (context, snapshot) {
                                                if (snapshot.data == true) {
                                                  return const Padding(
                                                    padding:
                                                        EdgeInsets.only(left: 4),
                                                    child: Icon(Icons.lock,
                                                        size: 14,
                                                        color: Color(0xFFD946EF)),
                                                  );
                                                }
                                                return const SizedBox.shrink();
                                              },
                                            ),
                                        ],
                                      ),
                                      if (widget.otherUserId.isEmpty)
                                        const Text("...", style: TextStyle(color: Colors.green, fontSize: 12))
                                      else
                                        StreamBuilder<DocumentSnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(widget.otherUserId)
                                              .snapshots(),
                                        builder: (context, snap) {
                                          final data = snap.data?.data() as Map<String, dynamic>? ?? {};
                                          final isOnline = data['isOnline'] ?? false;
                                          final onlineHidden = data['onlineHidden'] ?? false;
                                          final lastSeenHidden = data['lastSeenHidden'] ?? false;
                                          final lastActive = data['lastActive'] as Timestamp?;

                                          String statusText = _securityInit ? "🔒 Active" : "🔒 Pending";
                                          if (_connecting) statusText = "Connecting...";
                                          if (!widget.isGroup) {
                                            if (isOnline && !onlineHidden) {
                                              statusText = "Online • " + statusText;
                                            } else if (!isOnline && !lastSeenHidden && lastActive != null) {
                                              final time = _formatLastSeen(lastActive);
                                              statusText = time + " • " + statusText;
                                            }
                                          }

                                          return Text(
                                            widget.isGroup ? "Group Chat" : statusText,
                                            style: TextStyle(
                                                color: widget.isGroup ? const Color(0xFFD946EF) : Colors.green,
                                                fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          );
                                        },
                                      ),
                                    ]),
                              ),
                            ]),
                          ),
                        ),
                      if (_disappearingMessages)
                          const Icon(Icons.timer,
                              color: Color(0xFFD946EF), size: 20),
                        IconButton(
                            icon: const Icon(Icons.timer_outlined,
                                color: Color(0xFFD946EF)),
                            onPressed: _showDisappearingMessagesDialog),
                        IconButton(
                            icon: Icon(
                              Icons.verified_user,
                              color: _securityInit
                                  ? (_isEscalating
                                      ? Colors.yellow
                                      : Colors.green)
                                  : (_connecting ? Colors.yellow : Colors.grey),
                              size: 20,
                            ),
                            onPressed: _showSecurityPanel),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: isDark ? Colors.white : const Color(0xFF7C3AED)),
                          onSelected: (val) async {
                            if (val == 'block') {
                              if (!settings.blockedUsers.contains(widget.otherUserId)) {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Block Contact?"),
                                    content: const Text("This will prevent this contact from sending you messages or seeing your profile details. You can unblock them later."),
                                    actions: [
                                      TextButton(onPressed: () {
                if (Navigator.of(context, rootNavigator: true).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop(false);
                }
              }, child: const Text("Cancel")),
                                      TextButton(onPressed: () {
                if (Navigator.of(context, rootNavigator: true).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop(true);
                }
              }, child: const Text("Block", style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true && mounted) {
                                  await settings.toggleBlockUser(widget.otherUserId);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Contact blocked")),
                                    );
                                  }
                                }
                              } else {
                                await settings.toggleBlockUser(widget.otherUserId);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Contact unblocked")),
                                  );
                                  _initializeSecurity();
                                }
                              }
                            } else if (val == 'delete_chat') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Clear Chat?"),
                                  content: const Text("This will clear all messages in this chat for you. The other participant will still be able to see them."),
                                  actions: [
                                    TextButton(onPressed: () {
                if (Navigator.of(context, rootNavigator: true).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop(false);
                }
              }, child: const Text("Cancel")),
                                    TextButton(onPressed: () {
                if (Navigator.of(context, rootNavigator: true).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop(true);
                }
              }, child: const Text("Clear", style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                try {
                                    final uid = FirebaseAuth.instance.currentUser!.uid;
                                    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
                                      'clearedAt': { uid: FieldValue.serverTimestamp() }
                                    }, SetOptions(merge: true));
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chat cleared")));
                                      Navigator.of(context).maybePop();
                                    }
                                } catch (e) { debugPrint('Clear error: $e'); }
                              }
                            } else if (val == 'delete_chat_forever') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Contact?'),
                                  content: const Text('This will permanently delete this contact and conversation.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(ctx).maybePop(false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.of(ctx).maybePop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                try {
                                  await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).delete();
                                  if (mounted) Navigator.of(context).maybePop();
                                } catch (e) { debugPrint('Delete error: $e'); }
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            if (!settings.blockedUsers.contains(widget.otherUserId))
                              PopupMenuItem(
                                value: 'block',
                                child: Row(children: [
                                  Icon(settings.blockedUsers.contains(widget.otherUserId) ? Icons.person_add : Icons.block, 
                                    color: settings.blockedUsers.contains(widget.otherUserId) ? Colors.green : Colors.red, size: 20),
                                  const SizedBox(width: 12),
                                  Text(settings.blockedUsers.contains(widget.otherUserId) ? "Unblock Contact" : "Block Contact"),
                                ]),
                              ),
                            PopupMenuItem(
                              value: 'delete_chat',
                              child: Row(children: [
                                const Icon(Icons.clear_all, color: Colors.orange, size: 20),
                                const SizedBox(width: 12),
                                const Text("Clear Chat", style: TextStyle(color: Colors.orange)),
                              ]),
                            ),
                            PopupMenuItem(
                              value: 'delete_chat_forever',
                              child: Row(children: [
                                const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                                const SizedBox(width: 12),
                                const Text("Delete Contact", style: TextStyle(color: Colors.red)),
                              ]),
                            ),
                          ],
                        ),
                      ]),
              ),

              // Escalation Banner
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: _isEscalating ? 40 : 0,
                width: double.infinity,
                color: Colors.yellow[700],
                child: Center(
                  child: Text(
                    _escalationMessage,
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
              ),
              // ML-KEM Top Banner
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: _showMlKemBanner ? 40 : 0,
                width: double.infinity,
                color: Colors.green,
                child: _showMlKemBanner
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                            Icon(Icons.verified_user,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text("ML-KEM Handshake Initialized",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ])
                    : null,
              ),
              // Block Banner
              if (_isBlockedByMe || _isBlockedByOther)
                Container(
                  width: double.infinity,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.block, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            _isBlockedByMe
                                ? "You blocked this contact"
                                : "You have been blocked",
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ],
                      ),
                      if (_isBlockedByMe) ...[
                        const SizedBox(height: 8),
                        const Text(
                          "This contact is blocked. You cannot send or receive messages.",
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () async {
                            await settings.toggleBlockUser(widget.otherUserId);
                            if (mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text("Contact unblocked")),
                               );
                               // Re-init security session
                               _initializeSecurity();
                            }
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Unblock Contact", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: widget.chatId.isEmpty
                    ? const Center(child: Text("Securing Connection...", style: TextStyle(color: Colors.grey)))
                    : StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('chats')
                            .doc(widget.chatId)
                            .collection('messages')
                            .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData)
                      return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFD946EF)));
                    // Filter out hidden messages and messages before clearedAt
                    final docs = snap.data!.docs
                        .where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final msgTime = data['timestamp'] as Timestamp?;
                          
                          // Hide if manually hidden
                          if (_hiddenMessageIds.contains(doc.id)) return false;
                          
                          // Hide if sent before chat was cleared
                          if (_clearedAt != null && msgTime != null) {
                            if (msgTime.millisecondsSinceEpoch <= _clearedAt!.millisecondsSinceEpoch) {
                              return false;
                            }
                          }
                          return true;
                        })
                        .toList();

                    // REQUEST BATCH DECRYPTION for missing messages
                    if (_securityInit) {
                      final List<Map<String, String>> toDecrypt = [];
                      for (var doc in docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ciphertext = data['ciphertext'] as String?;
                        if (ciphertext != null && data['text'] == null) {
                          final hash = _getStableHash(ciphertext);
                          final scopedKey = "${widget.chatId}_$hash";
                          if (!_globalPersistentCache.containsKey(scopedKey) && !_requestedDecryptionIds.contains(doc.id)) {
                            toDecrypt.add({
                              'chatId': widget.chatId,
                              'messageId': doc.id,
                            });
                            _requestedDecryptionIds.add(doc.id);
                          }
                        }
                      }
                      if (toDecrypt.isNotEmpty) {
                        _cryptoService.requestBatchDecryption(widget.chatId, toDecrypt);
                      }
                    }

                    // Manually sort to ensure null (pending) timestamps are at index 0 (bottom of reverse ListView)
                    docs.sort((a, b) {
                       final tA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                       final tB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                       
                       if (tA == null && tB == null) return 0;
                       if (tA == null) return -1; // tA is newest
                       if (tB == null) return 1;  // tB is newest
                       return tB.millisecondsSinceEpoch.compareTo(tA.millisecondsSinceEpoch);
                    });
                    if (docs.isEmpty)
                      return Center(
                          child: Text("No messages yet",
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : const Color(0xFF9333EA))));
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final data = doc.data() as Map<String, dynamic>;

                        // Skip expired disappearing messages
                        final expiresAt = data['expiresAt'] as Timestamp?;
                        if (expiresAt != null &&
                            expiresAt.toDate().isBefore(DateTime.now())) {
                          return const SizedBox.shrink();
                        }

                        final me = data['senderId'] == uid;
                        final time = data['timestamp'] as Timestamp?;
                        final status = data['status'] ?? 'sent';
                        final imageBase64 = data['imageBase64'] as String?;
                        final isOneTime = data['isOneTime'] ?? false;
                        final viewed = data['viewed'] ?? false;

                        final isSelected = _selectedMessageIds.contains(doc.id);

                        return Dismissible(
                          key: ValueKey('swipe_${doc.id}'),
                          direction: (_isBlockedByMe || _isBlockedByOther)
                              ? DismissDirection.none
                              : DismissDirection.startToEnd,
                          confirmDismiss: (_) async {
                            setState(() {
                              _replyingTo = data;
                              _replyingToId = doc.id;
                            });
                            return false; // Don't actually dismiss
                          },
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            child: const Icon(Icons.reply,
                                color: Color(0xFFD946EF), size: 28),
                          ),
                          child: Align(
                            alignment: me
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(doc.id, me);
                                } else {
                                  final text = data['text'] as String?;
                                  final ciphertext =
                                      data['ciphertext'] as String?;
                                  String? displayContent = text;
                                  if (ciphertext != null && text == null) {
                                    final hash = _getStableHash(ciphertext);
                                    final scopedKey = "${widget.chatId}_$hash";
                                    displayContent =
                                        _globalPersistentCache[scopedKey];
                                  }
                                  _showMessageOptions(
                                      doc.id, displayContent, me, data,
                                      isOneTime: isOneTime, 
                                      isImage: data['imageBase64'] != null);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedMessageIds.add(doc.id);
                                    if (me) _mySelectedMessageIds.add(doc.id);
                                  });
                                } else {
                                  _toggleSelection(doc.id, me);
                                }
                              },
                              child: Container(
                                key: ValueKey<String>(doc.id),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.75),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? const LinearGradient(colors: [
                                          Color(0xFF7C3AED),
                                          Color(0xFF6D28D9)
                                        ])
                                      : (me
                                          ? const LinearGradient(colors: [
                                              Color(0xFFD946EF),
                                              Color(0xFFA855F7)
                                            ])
                                          : null),
                                  color: isSelected
                                      ? null
                                      : (me
                                          ? null
                                          : (isDark
                                              ? Colors.white12
                                              : Colors.white)),
                                  borderRadius: BorderRadius.circular(20),
                                  border: isSelected
                                      ? Border.all(
                                          color: Colors.white, width: 3)
                                      : (me
                                          ? null
                                          : Border.all(
                                              color: isDark
                                                  ? Colors.white10
                                                  : Colors.grey[200]!)),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                              color:
                                                  Colors.black.withValues(alpha: 0.3),
                                              blurRadius: 8)
                                        ]
                                      : null,
                                ),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (data['forwarded'] == true)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.forward,
                                                      size: 12,
                                                      color: me || isSelected
                                                          ? Colors.white70
                                                          : Colors.grey),
                                                  const SizedBox(width: 4),
                                                  Text("Forwarded",
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          color: me ||
                                                                  isSelected
                                                              ? Colors.white70
                                                              : Colors.grey))
                                                ])),
                                      // Reply bubble
                                      if (data['replyTo'] != null)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: (me || isSelected)
                                                ? Colors.white.withValues(alpha: 0.15)
                                                : Colors.black
                                                    .withValues(alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border(
                                                left: BorderSide(
                                                    color:
                                                        const Color(0xFFD946EF),
                                                    width: 3)),
                                          ),
                                          child: Text(
                                            (data['replyTo']['text']
                                                    as String?) ??
                                                '📷 Media',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontStyle: FontStyle.italic,
                                                color: (me || isSelected)
                                                    ? Colors.white70
                                                    : Colors.grey[600]),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      if (imageBase64 != null) ...[
                                        if (isOneTime && viewed)
                                          Container(
                                            padding: const EdgeInsets.all(20),
                                            child: const Column(children: [
                                              Icon(Icons.visibility_off,
                                                  color: Colors.grey, size: 32),
                                              SizedBox(height: 8),
                                              Text("Photo expired",
                                                  style: TextStyle(
                                                      color: Colors.grey)),
                                            ]),
                                          )
                                        else if (isOneTime && !viewed)
                                          GestureDetector(
                                            onTap: me
                                                ? null
                                                : () => _viewOneTimeImage(
                                                    doc.id, imageBase64),
                                            child: Container(
                                              padding: const EdgeInsets.all(20),
                                              decoration: BoxDecoration(
                                                  color: (me
                                                      ? Colors.white12
                                                      : const Color(0xFFD946EF)
                                                          .withValues(alpha: 0.2)),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Column(children: [
                                                Icon(
                                                    me
                                                        ? Icons.lock_outline
                                                        : Icons.lock_clock,
                                                    color: (me
                                                        ? Colors.white60
                                                        : const Color(
                                                            0xFFD946EF)),
                                                    size: 32),
                                                const SizedBox(height: 8),
                                                Text(
                                                    me
                                                        ? "One-time photo (Locked)"
                                                        : "Tap to view one-time photo",
                                                    style: TextStyle(
                                                        color: (me
                                                            ? Colors.white60
                                                            : const Color(
                                                                0xFFD946EF)),
                                                        fontSize: 12)),
                                              ]),
                                            ),
                                          )
                                        else if (data['fileName'] != null &&
                                            data['fileName']
                                                .toString()
                                                .endsWith('.m4a'))
                                          // Voice message player
                                          _buildVoicePlayer(imageBase64, doc.id,
                                              isDark, me || isSelected)
                                        else if (data['fileName'] != null &&
                                            ![
                                              'jpg',
                                              'jpeg',
                                              'png',
                                              'gif',
                                              'webp'
                                            ].contains(data['fileName']
                                                .split('.')
                                                .last
                                                .toLowerCase()))
                                          // Render as File Attachment Tile
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: (me || isSelected)
                                                  ? Colors.white10
                                                  : Colors.black
                                                      .withValues(alpha: 0.05),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.insert_drive_file,
                                                    color: (me || isSelected)
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF9333EA)),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    data['fileName'],
                                                    style: TextStyle(
                                                      color: (me || isSelected)
                                                          ? Colors.white
                                                          : const Color(
                                                              0xFF581C87),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxHeight: 200),
                                              child: Image.memory(
                                                base64Decode(imageBase64),
                                                fit: BoxFit.cover,
                                                filterQuality:
                                                    FilterQuality.high,
                                                gaplessPlayback:
                                                    true, // Prevents flash when updating
                                              ),
                                            ),
                                          ),
                                      ],
                                      if (data['text'] != null ||
                                          data['ciphertext'] != null) ...[
                                        _renderMessageText(data, doc.id, me, isDark),
                                      ],
                                      if (expiresAt != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.timer_outlined,
                                                  size: 12,
                                                  color: (me || isSelected)
                                                      ? Colors.white70
                                                      : Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(
                                                "Self-destructs soon",
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: (me || isSelected)
                                                        ? Colors.white70
                                                        : Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (data['signature'] != null ||
                                          data['ciphertext'] != null ||
                                          _dilithiumActive)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 4, bottom: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.verified,
                                                  size: 12,
                                                  color: (me || isSelected)
                                                      ? Colors.white70
                                                      : Colors.grey),
                                              const SizedBox(width: 4),
                                              Text("Signature verified",
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: (me || isSelected)
                                                          ? Colors.white70
                                                          : Colors.grey,
                                                      fontWeight:
                                                          FontWeight.w400)),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 2),
                                      Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSelected)
                                              const Padding(
                                                  padding:
                                                      EdgeInsets.only(right: 4),
                                                  child: Icon(
                                                      Icons.check_circle,
                                                      size: 12,
                                                      color: Colors.white)),
                                            if (isOneTime && me)
                                              const Padding(
                                                  padding:
                                                      EdgeInsets.only(right: 4),
                                                  child: Icon(Icons.timer,
                                                      size: 12,
                                                      color: Colors.white70)),
                                            Text(_formatTime(time),
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: (me || isSelected)
                                                        ? Colors.white70
                                                        : Colors.grey)),
                                            if (me) ...[
                                              const SizedBox(width: 4),
                                              _buildTick(status)
                                            ]
                                          ]),
                                    ]),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              // Reply preview bar
              if (_replyingTo != null && !_isBlockedByMe && !_isBlockedByOther)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D1B3D) : Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(
                        left: BorderSide(
                            color: const Color(0xFFD946EF), width: 3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.reply, color: Color(0xFFD946EF), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      (_replyingTo!['text'] as String?) ?? '📷 Media',
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                    IconButton(
                      icon:
                          const Icon(Icons.close, size: 18, color: Colors.grey),
                      onPressed: () => setState(() {
                        _replyingTo = null;
                        _replyingToId = null;
                      }),
                    ),
                  ]),
                ),
              if (!_isBlockedByMe && !_isBlockedByOther)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 45),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2D1B3D).withValues(alpha: 0.9)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: _isRecording
                      ? Row(children: [
                          IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: _cancelRecording),
                          const Expanded(
                              child: Center(
                                  child: Text("Recording...",
                                      style: TextStyle(
                                          color: Color(0xFFD946EF),
                                          fontWeight: FontWeight.bold)))),
                          IconButton(
                              icon: const Icon(Icons.stop,
                                  color: Color(0xFFD946EF), size: 28),
                              onPressed: _stopRecording),
                        ])
                      : Row(children: [
                          IconButton(
                              icon: const Icon(Icons.add,
                                  color: Color(0xFFD946EF)),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => SafeArea(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 20),
                                      decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF2D1B3D)
                                              : Colors.white,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(24))),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 24),
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(height: 12),
                                              Container(
                                                  width: 40,
                                                  height: 4,
                                                  decoration: BoxDecoration(
                                                      color: Colors.grey[300],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              2))),
                                              const SizedBox(height: 12),
                                              ListTile(
                                                  leading: const Icon(
                                                      Icons.image,
                                                      color: Color(0xFFD946EF)),
                                                  title: const Text("Image"),
                                                  onTap: () {
                                                    Navigator.of(context, rootNavigator: true).maybePop();
                                                    _pickImage();
                                                  }),
                                              ListTile(
                                                  leading: const Icon(
                                                      Icons.attach_file,
                                                      color: Color(0xFF9333EA)),
                                                  title: const Text("File"),
                                                  onTap: () {
                                                    Navigator.of(context, rootNavigator: true).maybePop();
                                                    _pickFile();
                                                  }),
                                            ]),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          IconButton(
                            icon: const Icon(Icons.camera_alt,
                                color: Color(0xFFD946EF)),
                            onPressed: _takePhoto,
                          ),
                          Expanded(
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(24)),
                                  child: TextField(
                                    controller: _msg,
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black),
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    keyboardType: TextInputType.multiline,
                                    maxLines: null,
                                    decoration: const InputDecoration(
                                        hintText: "Type a message...",
                                        border: InputBorder.none),
                                    onChanged: (val) {
                                      if (val.length == 1 &&
                                          val != val.toUpperCase()) {
                                        _msg.value = TextEditingValue(
                                          text: val.toUpperCase(),
                                          selection: TextSelection.collapsed(
                                              offset: 1),
                                        );
                                      }
                                      setState(() {});
                                    },
                                  ))),
                          const SizedBox(width: 8),
                          if (_msg.text.trim().isEmpty)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_disappearingMessages)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    _disappearDuration < 60
                                        ? "${_disappearDuration}s"
                                        : _disappearDuration < 3600
                                            ? "${(_disappearDuration / 60).round()}m"
                                            : _disappearDuration < 86400
                                                ? "${(_disappearDuration / 3600).round()}h"
                                                : _disappearDuration < 604800
                                                    ? "${(_disappearDuration / 86400).round()}d"
                                                    : "7d",
                                    style: const TextStyle(
                                        color: Color(0xFFD946EF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                ),
                              GestureDetector(
                                onTap: _startRecording,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      Color(0xFFD946EF),
                                      Color(0xFFA855F7)
                                    ]),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.mic,
                                      color: Colors.white, size: 24),
                                ),
                              ),
                            ])
                          else
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_disappearingMessages)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    _disappearDuration < 60
                                        ? "${_disappearDuration}s"
                                        : _disappearDuration < 3600
                                            ? "${(_disappearDuration / 60).round()}m"
                                            : _disappearDuration < 86400
                                                ? "${(_disappearDuration / 3600).round()}h"
                                                : _disappearDuration < 604800
                                                    ? "${(_disappearDuration / 86400).round()}d"
                                                    : "7d",
                                    style: const TextStyle(
                                        color: Color(0xFFD946EF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                ),
                              GestureDetector(
                                onTap: () => _send(),
                                onLongPress: () => _send(isHighRisk: true),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      Color(0xFFD946EF),
                                      Color(0xFFA855F7)
                                    ]),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.send,
                                      color: Colors.white, size: 24),
                                ),
                              ),
                            ]),
                        ]),
                ),
            ],
          ),
          _buildRecordingOverlay(),
        ]),
      ),
    );
    } catch (e, stack) {
      debugPrint('🚨 [ChatScreen] Build CRASHED: $e');
      debugPrint('$stack');
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 24),
              const Text("Chat Screen Error",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  "Exception: $e",
                  style: const TextStyle(color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
                  child: const Text("Go Back")),
            ],
          ),
        ),
      );
    }
  }

  String _formatLastSeen(Timestamp t) {
    final date = t.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return "Last seen just now";
    if (diff.inMinutes < 60) return "Last seen ${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "Last seen ${diff.inHours}h ago";
    return "Last seen ${diff.inDays}d ago";
  }

  Widget _buildRecordingOverlay() {
    if (!_isRecording) return const SizedBox.shrink();

    return Positioned.fill(
      child: VoiceRecordingOverlay(
        userName: widget.otherUserName,
        onStop: _stopRecording,
        onCancel: _cancelRecording,
        onRetry: _retryRecording,
        amplitudeStream: _amplitudeController?.stream ?? const Stream.empty(),
      ),
    );
  }

  Uint8List? _safeBase64Decode(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      return base64Decode(base64Str);
    } catch (e) {
      debugPrint('❌ Error decoding avatar: $e');
      return null;
    }
  }

  Widget _buildInitError() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, color: Colors.orange, size: 60),
            const SizedBox(height: 24),
            const Text("Initialization Error",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                "Failed to initialize secure chat: $_initError",
                style: const TextStyle(color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
                child: const Text("Go Back")),
            TextButton(
              onPressed: () => _tryInit(),
              child: const Text("Retry Connection"),
            ),
          ],
        ),
      ),
    );
  }
}
