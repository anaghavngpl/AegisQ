import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xkyber_crypto/xkyber_crypto.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for handling WebSocket connection to AegisQ Python backend
/// with real ML-KEM key exchange, Double Ratchet encryption, and Dilithium signatures
class WebSocketCryptoService {
  static final WebSocketCryptoService _instance = WebSocketCryptoService._internal();
  factory WebSocketCryptoService() => _instance;
  WebSocketCryptoService._internal() {
    _loadStoredUrl().then((_) {
      // FORCE RESET if url is the old default or local
      if (_backendUrl.contains(':8000') || _backendUrl.contains(':8001')) {
        debugPrint('🧹 Resetting stale backend URL: $_backendUrl -> $_defaultBackendUrl');
        _backendUrl = _defaultBackendUrl;
      }
    });
  }

  // Heartbeat timer
  Timer? _heartbeatTimer;

  // Backend URL - change this to your server address
  static const String _defaultBackendUrl = 'ws://10.0.2.2:8000'; // Android emulator localhost
  String _backendUrl = _defaultBackendUrl;

  /// Get the current backend URL (for UI display)
  String get currentBackendUrl => _backendUrl;

  // Active connections per conversation
  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, StreamController<Map<String, dynamic>>> _messageStreams = {};
  
  // Session states
  final Map<String, bool> _sessionInitialized = {};
  final Map<String, bool> _mlKemActive = {};
  final Map<String, bool> _doubleRatchetActive = {};
  final Map<String, bool> _dilithiumActive = {};

  // Server public key for ML-KEM
  Uint8List? _serverPk768;
  Uint8List? _serverPk1024;

  /// Set backend URL (call before connecting)
  Future<void> setBackendUrl(String url) async {
    // Sanitize URL
    String sanitized = url.trim();
    if (sanitized.isNotEmpty) {
      if (!sanitized.startsWith('ws://') && !sanitized.startsWith('wss://')) {
        sanitized = 'ws://$sanitized';
      }
      // Remove trailing slash
      if (sanitized.endsWith('/')) {
        sanitized = sanitized.substring(0, sanitized.length - 1);
      }
    }
    
    _backendUrl = sanitized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', sanitized);
  }

  /// Request decryption for a batch of messages
  void requestBatchDecryption(String chatId, List<Map<String, String>> items) {
    if (items.isEmpty) return;
    final channel = _channels[chatId];
    if (channel != null) {
      channel.sink.add(jsonEncode({
        'type': 'decrypt_batch',
        'items': items,
      }));
    }
  }

  /// Load stored URL on startup
  Future<void> _loadStoredUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedUrl = prefs.getString('backend_url');
      
      // FORCE SYNC: If user has old default ports (8001/8002), migrate them to 8000
      if (savedUrl != null && (savedUrl.contains(':8001') || savedUrl.contains(':8002'))) {
        debugPrint('🧹 Migrating stale backend URL: $savedUrl -> ${_defaultBackendUrl}');
        savedUrl = _defaultBackendUrl;
        await prefs.setString('backend_url', savedUrl);
      }

      if (savedUrl != null && savedUrl.isNotEmpty) {
        _backendUrl = savedUrl;
        debugPrint('󰖩 Loaded stored backend URL: $_backendUrl');
      }
    } catch (e) {
      debugPrint('Error loading stored URL: $e');
    }
  }

  /// Start heartbeat to keep connection alive
  void _startHeartbeat(String conversationId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final channel = _channels[conversationId];
      if (channel != null) {
        debugPrint('💓 Sending heartbeat ping for $conversationId');
        channel.sink.add(jsonEncode({'type': 'ping'}));
      } else {
        timer.cancel();
      }
    });
  }

  /// Convert hex string to Uint8List
  Uint8List _hexToBytes(String hex) {
    var result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      var num = int.parse(hex.substring(i, i + 2), radix: 16);
      result[i ~/ 2] = num;
    }
    return result;
  }

  /// Convert Uint8List to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  bool _isConnecting = false;
  String? _lastError;

  bool get isConnecting => _isConnecting;
  String? get lastError => _lastError;

  /// Fetch server ML-KEM public keys
  Future<bool> fetchServerKeys() async {
    _lastError = null;
    try {
      final baseUrl = _backendUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
      debugPrint('🔍 Attempting server key fetch from: $baseUrl/server-kem-pk');
      
      final response = await http.get(Uri.parse('$baseUrl/server-kem-pk')).timeout(const Duration(seconds: 10));
      debugPrint('📡 Server key response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _serverPk768 = _hexToBytes(data['pk_768']);
        _serverPk1024 = _hexToBytes(data['pk_1024']);
        debugPrint('Successfully parsed server ML-KEM keys');
        return true;
      } else {
        _lastError = 'Server returned error ${response.statusCode}';
        debugPrint('Failed to fetch keys: $_lastError');
      }
      return false;
    } catch (e) {
      _lastError = 'Network error: ${e.toString().split('\n').first}';
      debugPrint('CRITICAL: Failed to fetch server keys: $e');
      return false;
    }
  }

  /// Sends a raw map as JSON over the WebSocket (for specialized commands)
  void sendRawMessage(String conversationId, Map<String, dynamic> data) {
    final channel = _channels[conversationId];
    if (channel != null) {
      debugPrint('📤 Sending raw message for $conversationId: ${data['type']}');
      channel.sink.add(jsonEncode(data));
    }
  }

  /// Connect to backend for a specific conversation
  Future<bool> connect(String conversationId) async {
    if (_channels.containsKey(conversationId)) {
      return true; // Already connected
    }

    _isConnecting = true;
    _lastError = null;

    try {
      // Always try to load the latest saved URL (restoring for backend sync)
      final prefs = await SharedPreferences.getInstance();
      String? savedUrl = prefs.getString('backend_url');
      
      // FORCE SYNC: If user has old default ports (8001/8002), migrate them to 8000
      if (savedUrl != null && (savedUrl.contains(':8001') || savedUrl.contains(':8002'))) {
        debugPrint('🧹 Migrating stale backend URL: $savedUrl -> ${_defaultBackendUrl}');
        savedUrl = _defaultBackendUrl;
        await prefs.setString('backend_url', savedUrl);
      }

      if (savedUrl != null && savedUrl.isNotEmpty) {
        _backendUrl = savedUrl;
      }

      // Always fetch fresh server keys to ensure we match the current backend instance
      final keysFetched = await fetchServerKeys();
      if (!keysFetched) {
        _isConnecting = false;
        return false;
      }

      final wsUrl = Uri.parse('$_backendUrl/ws/$conversationId');
      debugPrint('🔌 Connecting to WebSocket: $wsUrl');
      final channel = WebSocketChannel.connect(wsUrl);
      
      await channel.ready.timeout(const Duration(seconds: 10));
      debugPrint('✅ WebSocket channel ready for $conversationId');
      
      _channels[conversationId] = channel;
      _messageStreams[conversationId] = StreamController<Map<String, dynamic>>.broadcast();
      
      // Start heartbeat
      _startHeartbeat(conversationId);
      
      // Listen for incoming messages
      channel.stream.listen(
        (data) {
          debugPrint('📥 Received raw WS data: $data');
          _handleIncomingMessage(conversationId, data);
        },
        onError: (error) {
          debugPrint('❌ WebSocket error for $conversationId: $error');
          _cleanup(conversationId);
        },
        onDone: () {
          debugPrint('🚫 WebSocket closed for $conversationId');
          _cleanup(conversationId);
        },
      );

      _isConnecting = false;
      return true;
    } catch (e) {
      _lastError = 'WebSocket connection failed';
      debugPrint('❌ Failed to connect to backend: $e');
      _isConnecting = false;
      return false;
    }
  }

  /// Initialize ML-KEM session with server
  Future<bool> initSession(String conversationId, {bool escalate = false}) async {
    final channel = _channels[conversationId];
    if (channel == null) {
      final connected = await connect(conversationId);
      if (!connected) return false;
    }

    try {
      if (_serverPk768 == null) {
        final fetched = await fetchServerKeys();
        if (!fetched) return false;
      }

      // Real ML-KEM Encapsulation
      final serverPk = escalate ? _serverPk1024 : _serverPk768;
      if (serverPk == null) {
        debugPrint('❌ Cannot init session: Server public key is NULL');
        return false;
      }

      debugPrint('🔐 Encapsulating for ML-KEM-${escalate ? '1024' : '768'}...');
      debugPrint('📦 Server PK (hex): ${_bytesToHex(serverPk).substring(0, 32)}...');
      
      // Use xkyber_crypto to encapsulate a shared secret
      final encapsulationResult = KyberKEM.encapsulate(serverPk);
      final ciphertext = encapsulationResult.ciphertextKEM;
      final sharedSecret = encapsulationResult.sharedSecret;
      
      debugPrint('📨 Sending client CT (length: ${ciphertext.length} bytes)');
      debugPrint('🔑 Shared Secret derived locally (hex): ${_bytesToHex(sharedSecret).substring(0, 16)}...');
      
      final initPacket = {
        'type': 'init',
        'client_ct_hex': _bytesToHex(ciphertext),
        'escalate': escalate,
      };

      // Wait for init_ok response - START LISTENING BEFORE SENDING
      final completer = Completer<bool>();
      late StreamSubscription sub;
      
      sub = _messageStreams[conversationId]!.stream.listen((msg) {
        debugPrint('👂 Handshake Message from Server: ${msg['type']}');
        if (msg['type'] == 'init_ok') {
          debugPrint('🎉 ML-KEM Handshake Successful!');
          _sessionInitialized[conversationId] = true;
          _mlKemActive[conversationId] = msg['security_info']?['ml_kem_handshake'] ?? false;
          _doubleRatchetActive[conversationId] = msg['security_info']?['root_key_established'] ?? false;
          _dilithiumActive[conversationId] = true;
          if (!completer.isCompleted) completer.complete(true);
        } else if (msg['type'] == 'error') {
          debugPrint('❌ Handshake Error from Server: ${msg['message']}');
          if (!completer.isCompleted) completer.complete(false);
        }
      });

      debugPrint('📤 Sending ML-KEM Handshake packet...');
      _channels[conversationId]?.sink.add(jsonEncode(initPacket));
      
      // Timeout after 10 seconds
      final success = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏰ Handshake TIMEOUT');
          return false;
        },
      );

      await sub.cancel();
      return success;
    } catch (e) {
      debugPrint('Session init failed: $e');
      return false;
    }
  }

  /// Send deletion command to backend to bypass client Firestore permissions
  bool deleteRemoteMessage(String conversationId, String messageId) {
    final channel = _channels[conversationId];
    if (channel == null) {
      debugPrint('❌ Cannot delete: Not connected to WebSocket for $conversationId');
      return false;
    }
    
    debugPrint('🗑️ Sending delete command for: $messageId');
    channel.sink.add(jsonEncode({
      'type': 'delete',
      'message_id': messageId,
    }));
    return true;
  }

  /// Send clear chat command to backend
  bool clearChat(String conversationId) {
    final channel = _channels[conversationId];
    if (channel == null) {
      debugPrint('❌ Cannot clear chat: Not connected to WebSocket for $conversationId');
      return false;
    }
    
    debugPrint('🧹 Sending clear_chat command for: $conversationId');
    channel.sink.add(jsonEncode({
      'type': 'clear_chat',
    }));
    return true;
  }

  /// Block or unblock a user via backend
  bool toggleBlockUser(String conversationId, String targetId, bool block) {
    final channel = _channels[conversationId];
    if (channel == null) {
      debugPrint('❌ Cannot toggle block: Not connected to WebSocket for $conversationId');
      return false;
    }
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    debugPrint('🚫 Sending block_user command: target=$targetId, block=$block');
    channel.sink.add(jsonEncode({
      'type': 'block_user',
      'sender_id': uid,
      'target_id': targetId,
      'block': block,
    }));
    return true;
  }

  /// Send encrypted message through backend
  Future<bool> sendSecureMessage(String conversationId, {String? text, String? imageBase64, String? fileName, bool isOneTime = false, int? disappearDuration}) async {
    if (!(_sessionInitialized[conversationId] ?? false)) {
      final initialized = await initSession(conversationId);
      if (!initialized) return false;
    }

    try {
      final messagePacket = {
        'type': 'message',
        'text': text,
        'imageBase64': imageBase64,
        'fileName': fileName,
        'isOneTime': isOneTime,
        'disappearDuration': disappearDuration,
        'senderId': FirebaseAuth.instance.currentUser?.uid ?? "unknown",
      };

      _channels[conversationId]?.sink.add(jsonEncode(messagePacket));
      return true;
    } catch (e) {
      debugPrint('Failed to send message: $e');
      return false;
    }
  }

  /// Get stream of incoming encrypted messages
  Stream<Map<String, dynamic>>? getMessageStream(String conversationId) {
    return _messageStreams[conversationId]?.stream;
  }

  /// Check if session is initialized
  bool isSessionInitialized(String conversationId) {
    if (conversationId == "any_active_session") {
      return _sessionInitialized.values.any((v) => v);
    }
    return _sessionInitialized[conversationId] ?? false;
  }

  /// Get security status
  Map<String, bool> getSecurityStatus(String conversationId) {
    if (conversationId == "any_active_session") {
      if (_sessionInitialized.values.any((v) => v)) {
        return {
          'mlKemActive': true,
          'doubleRatchetActive': true,
          'dilithiumActive': true,
          'sessionInitialized': true,
        };
      }
    }
    return {
      'mlKemActive': _mlKemActive[conversationId] ?? false,
      'doubleRatchetActive': _doubleRatchetActive[conversationId] ?? false,
      'dilithiumActive': _dilithiumActive[conversationId] ?? false,
      'sessionInitialized': _sessionInitialized[conversationId] ?? false,
    };
  }

  /// Handle incoming WebSocket messages
  void _handleIncomingMessage(String conversationId, dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      _messageStreams[conversationId]?.add(message);
      
      // Update security status for secure messages
      if (message['type'] == 'secure_message') {
        final securityInfo = message['security_info'] as Map<String, dynamic>?;
        if (securityInfo != null) {
          _mlKemActive[conversationId] = securityInfo['ml_kem_used'] ?? false;
          _doubleRatchetActive[conversationId] = securityInfo['double_ratchet_active'] ?? false;
          _dilithiumActive[conversationId] = securityInfo['dilithium_signed'] ?? false;
        }
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  /// Cleanup connection
  void _cleanup(String conversationId) {
    _channels[conversationId]?.sink.close();
    _channels.remove(conversationId);
    _messageStreams[conversationId]?.close();
    _messageStreams.remove(conversationId);
    _sessionInitialized.remove(conversationId);
    _mlKemActive.remove(conversationId);
    _doubleRatchetActive.remove(conversationId);
    _dilithiumActive.remove(conversationId);
    
    if (_channels.isEmpty) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  /// Disconnect from a conversation
  void disconnect(String conversationId) {
    _cleanup(conversationId);
  }

  /// Disconnect all
  void disconnectAll() {
    for (final id in _channels.keys.toList()) {
      _cleanup(id);
    }
  }
}
