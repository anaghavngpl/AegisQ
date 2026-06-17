import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final String _baseUrl = 'ws://10.0.2.2:8000/ws'; // Use 10.0.2.2 for Android emulator

  // Connect to the chat room
  void connect(String conversationId) {
    // Dispose existing connection if any
    if (_channel != null) {
      _channel!.sink.close();
    }

    try {
      // For Android Emulator, use 10.0.2.2 instead of localhost
      // For iOS Simulator, localhost is fine
      // We'll assume Android for now given typical dev setups, or make it configurable
      final url = '$_baseUrl/$conversationId'; 
      _channel = WebSocketChannel.connect(Uri.parse(url));
      debugPrint("Connected to WebSocket: $url");
    } catch (e) {
      debugPrint("WebSocket Connection Error: $e");
    }
  }

  // Send init message (ML-KEM handshake)
  void sendInit(String clientCtHex) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'init',
      'client_ct_hex': clientCtHex,
    }));
  }

  // Send encrypted message
  void sendMessage(String text) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'text': text, // The backend handles encryption in this demo architecture
    }));
  }

  // Listen to incoming messages
  Stream<dynamic> get messages {
    if (_channel == null) return const Stream.empty();
    return _channel!.stream;
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }
}
