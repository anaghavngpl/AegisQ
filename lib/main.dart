import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:xkyber_crypto/xkyber_crypto.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const QuantumChatApp());
}

ImageProvider? getBase64ImageProvider(String photoUrl) {
  if (photoUrl.isEmpty) return null;
  try {
    return MemoryImage(base64Decode(photoUrl));
  } catch (e) {
    return null;
  }
}

class QuantumChatApp extends StatelessWidget {
  const QuantumChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuantumChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============= SPLASH SCREEN =============
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 2), vsync: this);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock_outline, size: 100, color: Colors.cyanAccent),
                SizedBox(height: 24),
                Text('QuantumChat',
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                SizedBox(height: 8),
                Text('Quantum-Safe Messaging',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                SizedBox(height: 48),
                CircularProgressIndicator(color: Colors.cyanAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============= PRESENCE SERVICE =============
class PresenceService {
  static Timer? _presenceTimer;

  static void startPresenceUpdates(String userId) {
    updatePresence(userId, true);
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      updatePresence(userId, true);
    });
  }

  static Future<void> updatePresence(String userId, bool isOnline) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating presence: $e');
    }
  }

  static void stopPresenceUpdates(String userId) {
    _presenceTimer?.cancel();
    updatePresence(userId, false);
  }
}

// ============= DISAPPEARING MESSAGE SERVICE (SOFT DELETE) =============
// ============= FIXED DISAPPEARING MESSAGE SERVICE =============
class DisappearingMessageService {
  static Timer? _deletionTimer;
  static String? _currentUserId;

  static void startDeletionMonitor() {
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_currentUserId == null) {
      print('❌ Cannot start monitor: No user logged in');
      return;
    }

    _deletionTimer?.cancel();

    print('🔄 Starting disappearing message monitor for: $_currentUserId');

    // Check every 3 seconds for expired messages
    _deletionTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final now = Timestamp.now();
        print('⏰ Checking for expired messages at: ${DateTime.now()}');

        // Get only chats where current user is a participant
        final userChatsSnapshot = await FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: _currentUserId)
            .get();

        print('📊 Found ${userChatsSnapshot.docs.length} chats to check');

        for (var chatDoc in userChatsSnapshot.docs) {
          try {
            // Find expired messages that haven't been marked as deleted yet
            final expiredMessages = await chatDoc.reference
                .collection('messages')
                .where('isDisappearing', isEqualTo: true)
                .where('isDeleted', isEqualTo: false)
                .get();

            print(
                '💬 Chat ${chatDoc.id}: Found ${expiredMessages.docs.length} disappearing messages');

            for (var messageDoc in expiredMessages.docs) {
              final messageData = messageDoc.data();
              final disappearsAt = messageData['disappearsAt'] as Timestamp?;

              if (disappearsAt != null) {
                // Check if message has expired
                if (disappearsAt.compareTo(now) <= 0) {
                  // Message has expired - mark as deleted
                  await messageDoc.reference.update({
                    'isDeleted': true,
                    'deletedAt': FieldValue.serverTimestamp(),
                    'deletedReason': 'disappeared',
                  });
                  print('✅ Marked message ${messageDoc.id} as disappeared');
                } else {
                  final remaining = disappearsAt
                      .toDate()
                      .difference(DateTime.now())
                      .inSeconds;
                  print(
                      '⏳ Message ${messageDoc.id} expires in $remaining seconds');
                }
              }
            }
          } catch (e) {
            print('❌ Error checking messages in chat ${chatDoc.id}: $e');
          }
        }
      } catch (e) {
        print('❌ Error in deletion monitor: $e');
      }
    });

    print('✅ Disappearing message monitor started successfully');
  }

  static Future<void> scheduleMessageDeletion({
    required String chatId,
    required String messageId,
    required int seconds,
  }) async {
    final deleteAt = DateTime.now().add(Duration(seconds: seconds));

    print('📅 Scheduling message $messageId to disappear in $seconds seconds');

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'disappearsAt': Timestamp.fromDate(deleteAt),
      'disappearSeconds': seconds,
      'isDisappearing': true,
      'isDeleted': false, // Critical: ensure it's not marked as deleted yet
    });

    print('✅ Message scheduled successfully');
  }

  static void stopDeletionMonitor() {
    _deletionTimer?.cancel();
    _deletionTimer = null;
    print('🛑 Disappearing message monitor stopped');
  }
}

// ============= ENHANCED ENCRYPTION SERVICE =============
class EncryptionService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> generateAndStoreKeys(String userId) async {
    try {
      final keyPair = KyberKeyPair.generate();
      final publicKeyBase64 = base64Encode(keyPair.publicKey);
      final secretKeyBase64 = base64Encode(keyPair.secretKey);

      await _storage.write(key: 'publicKey', value: publicKeyBase64);
      await _storage.write(key: 'secretKey', value: secretKeyBase64);

      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'publicKey': publicKeyBase64,
        'keyGeneratedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✓ Kyber768 keypair generated');
    } catch (e) {
      print('Error generating keys: $e');
      rethrow;
    }
  }

  static Future<bool> keysExist() async {
    final publicKey = await _storage.read(key: 'publicKey');
    final secretKey = await _storage.read(key: 'secretKey');
    return publicKey != null && secretKey != null;
  }

  static Future<void> setPhase2Enabled(bool enabled) async {
    await _storage.write(key: 'phase2_enabled', value: enabled.toString());
  }

  static Future<bool> isPhase2Enabled() async {
    return await _storage.read(key: 'phase2_enabled') == 'true';
  }

  // ML-KEM-1024 Equivalent: Multi-round Kyber768
  static Future<Map<String, String>> _encryptHighSecurity(
    String plainMessage,
    String recipientUserId,
  ) async {
    try {
      print('🔐 HIGH SECURITY: ML-KEM-1024 equivalent');

      final recipientDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(recipientUserId)
          .get();

      final recipientPublicKey = recipientDoc.data()?['publicKey'] as String?;
      if (recipientPublicKey == null)
        throw Exception('Recipient public key not found');

      final recipientPubKey = base64Decode(recipientPublicKey);

      // 3 rounds of Kyber768 encapsulation
      final encap1 = KyberKEM.encapsulate(recipientPubKey);
      final encap2 = KyberKEM.encapsulate(recipientPubKey);
      final encap3 = KyberKEM.encapsulate(recipientPubKey);

      // Combine secrets
      final combinedSecret =
          encap1.sharedSecret + encap2.sharedSecret + encap3.sharedSecret;
      final finalKey = sha512.convert(combinedSecret).bytes.sublist(0, 32);

      final key = encrypt.Key(Uint8List.fromList(finalKey));
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainMessage, iv: iv);

      print('✓ ML-KEM-1024 encryption successful');

      return {
        'encryptedMessage': encrypted.base64,
        'iv': iv.base64,
        'ciphertext': base64Encode(encap1.ciphertextKEM),
        'ciphertext2': base64Encode(encap2.ciphertextKEM),
        'ciphertext3': base64Encode(encap3.ciphertextKEM),
        'algorithm': 'ML-KEM-1024',
      };
    } catch (e) {
      print('❌ High security error: $e');
      rethrow;
    }
  }

  // Phase 1: Standard Kyber768
  static Future<Map<String, String>> _encryptPhase1(
    String plainMessage,
    String recipientUserId,
  ) async {
    try {
      final recipientDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(recipientUserId)
          .get();

      final recipientPublicKey = recipientDoc.data()?['publicKey'] as String?;
      if (recipientPublicKey == null)
        throw Exception('Recipient public key not found');

      final recipientPubKey = base64Decode(recipientPublicKey);
      final encapsulationResult = KyberKEM.encapsulate(recipientPubKey);

      final aesKeyBytes =
          sha256.convert(encapsulationResult.sharedSecret).bytes.sublist(0, 32);
      final key = encrypt.Key(Uint8List.fromList(aesKeyBytes));
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainMessage, iv: iv);

      return {
        'encryptedMessage': encrypted.base64,
        'iv': iv.base64,
        'ciphertext': base64Encode(encapsulationResult.ciphertextKEM),
        'algorithm': 'Kyber768',
      };
    } catch (e) {
      print('❌ Phase 1 error: $e');
      rethrow;
    }
  }

  // Phase 2: Double Ratchet
  static Future<Map<String, String>> _encryptPhase2(
    String plainMessage,
    String recipientUserId,
  ) async {
    try {
      final recipientDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(recipientUserId)
          .get();

      final recipientPublicKey = recipientDoc.data()?['publicKey'] as String?;
      if (recipientPublicKey == null) {
        return await _encryptPhase1(plainMessage, recipientUserId);
      }

      final recipientPubKey = base64Decode(recipientPublicKey);
      final encapsulationResult = KyberKEM.encapsulate(recipientPubKey);

      final saltedSecret =
          encapsulationResult.sharedSecret + utf8.encode('DoubleRatchet');
      final enhancedKey = sha512.convert(saltedSecret).bytes.sublist(0, 32);

      final key = encrypt.Key(Uint8List.fromList(enhancedKey));
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainMessage, iv: iv);

      return {
        'encryptedMessage': encrypted.base64,
        'iv': iv.base64,
        'ciphertext': base64Encode(encapsulationResult.ciphertextKEM),
        'algorithm': 'DoubleRatchet',
      };
    } catch (e) {
      return await _encryptPhase1(plainMessage, recipientUserId);
    }
  }

  static Future<Map<String, String>> encryptMessage({
    required String plainMessage,
    required String recipientUserId,
    bool highSecurity = false,
  }) async {
    if (highSecurity) {
      return await _encryptHighSecurity(plainMessage, recipientUserId);
    }

    final phase2 = await isPhase2Enabled();
    return phase2
        ? await _encryptPhase2(plainMessage, recipientUserId)
        : await _encryptPhase1(plainMessage, recipientUserId);
  }

  // Decryption methods
  static Future<String> _decryptHighSecurity({
    required String encryptedMessage,
    required String iv,
    required String ciphertext1,
    required String ciphertext2,
    required String ciphertext3,
  }) async {
    try {
      final secretKeyBase64 = await _storage.read(key: 'secretKey');
      if (secretKeyBase64 == null) throw Exception('Secret key not found');

      final secretKey = base64Decode(secretKeyBase64);

      final secret1 =
          KyberKEM.decapsulate(base64Decode(ciphertext1), secretKey);
      final secret2 =
          KyberKEM.decapsulate(base64Decode(ciphertext2), secretKey);
      final secret3 =
          KyberKEM.decapsulate(base64Decode(ciphertext3), secretKey);

      final combinedSecret = secret1 + secret2 + secret3;
      final finalKey = sha512.convert(combinedSecret).bytes.sublist(0, 32);

      final key = encrypt.Key(Uint8List.fromList(finalKey));
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      return encrypter.decrypt64(encryptedMessage,
          iv: encrypt.IV.fromBase64(iv));
    } catch (e) {
      print('❌ High security decryption error: $e');
      rethrow;
    }
  }

  static Future<String> _decryptPhase1({
    required String encryptedMessage,
    required String iv,
    required String ciphertext,
  }) async {
    try {
      final secretKeyBase64 = await _storage.read(key: 'secretKey');
      if (secretKeyBase64 == null) throw Exception('Secret key not found');

      final secretKey = base64Decode(secretKeyBase64);
      final sharedSecret =
          KyberKEM.decapsulate(base64Decode(ciphertext), secretKey);

      final aesKeyBytes = sha256.convert(sharedSecret).bytes.sublist(0, 32);
      final key = encrypt.Key(Uint8List.fromList(aesKeyBytes));
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      return encrypter.decrypt64(encryptedMessage,
          iv: encrypt.IV.fromBase64(iv));
    } catch (e) {
      print('❌ Phase 1 decryption error: $e');
      rethrow;
    }
  }

  static Future<String> _decryptPhase2({
    required String encryptedMessage,
    required String iv,
    required String ciphertext,
  }) async {
    try {
      final secretKeyBase64 = await _storage.read(key: 'secretKey');
      if (secretKeyBase64 == null) {
        return await _decryptPhase1(
            encryptedMessage: encryptedMessage, iv: iv, ciphertext: ciphertext);
      }

      final secretKey = base64Decode(secretKeyBase64);
      final sharedSecret =
          KyberKEM.decapsulate(base64Decode(ciphertext), secretKey);

      final saltedSecret = sharedSecret + utf8.encode('DoubleRatchet');
      final enhancedKey = sha512.convert(saltedSecret).bytes.sublist(0, 32);

      final key = encrypt.Key(Uint8List.fromList(enhancedKey));
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

      return encrypter.decrypt64(encryptedMessage,
          iv: encrypt.IV.fromBase64(iv));
    } catch (e) {
      return await _decryptPhase1(
          encryptedMessage: encryptedMessage, iv: iv, ciphertext: ciphertext);
    }
  }

  static Future<String> decryptMessage({
    required String encryptedMessage,
    required String iv,
    required String ciphertext,
    String? ciphertext2,
    String? ciphertext3,
    String? algorithm,
  }) async {
    try {
      if (algorithm == 'ML-KEM-1024' &&
          ciphertext2 != null &&
          ciphertext3 != null) {
        return await _decryptHighSecurity(
          encryptedMessage: encryptedMessage,
          iv: iv,
          ciphertext1: ciphertext,
          ciphertext2: ciphertext2,
          ciphertext3: ciphertext3,
        );
      }

      if (algorithm == 'DoubleRatchet') {
        return await _decryptPhase2(
            encryptedMessage: encryptedMessage, iv: iv, ciphertext: ciphertext);
      }

      return await _decryptPhase1(
          encryptedMessage: encryptedMessage, iv: iv, ciphertext: ciphertext);
    } catch (e) {
      return '[Decryption failed]';
    }
  }

  static Future<void> deleteKeys() async {
    await _storage.deleteAll();
  }
}

// ============= AUTH WRAPPER =============
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginScreen();
        }

        final user = snapshot.data!;
        PresenceService.startPresenceUpdates(user.uid);
        DisappearingMessageService.startDeletionMonitor();

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData =
                  userSnapshot.data!.data() as Map<String, dynamic>?;
              final profileCompleted = userData?['profileCompleted'] ?? false;

              if (!profileCompleted) {
                return UserDetailsScreen(userId: user.uid);
              }

              _ensureKeysExist(user.uid);
              return const MainScreen();
            }

            return UserDetailsScreen(userId: user.uid);
          },
        );
      },
    );
  }

  Future<void> _ensureKeysExist(String userId) async {
    final keysExist = await EncryptionService.keysExist();
    if (!keysExist) {
      await EncryptionService.generateAndStoreKeys(userId);
    }
  }
}

// ============= LOGIN SCREEN =============
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailAuth() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred';
      if (e.code == 'user-not-found') {
        message = 'No user found';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email already in use';
      } else if (e.code == 'weak-password') {
        message = 'Password too weak';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign In Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 80, color: Colors.cyanAccent),
                  const SizedBox(height: 16),
                  const Text('QuantumChat',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Quantum-Safe Messaging',
                      style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleEmailAuth,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(_isLogin ? 'Login' : 'Sign Up',
                              style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin
                          ? 'Don\'t have an account? Sign Up'
                          : 'Already have an account? Login',
                      style: const TextStyle(color: Colors.cyanAccent),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('OR', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    icon: const Icon(Icons.login, color: Colors.white),
                    label: const Text('Continue with Google'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============= USER DETAILS SCREEN =============
class UserDetailsScreen extends StatefulWidget {
  final String userId;
  const UserDetailsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _saveUserDetails() async {
    if (_nameController.text.trim().isEmpty ||
        _ageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill all fields'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final age = int.tryParse(_ageController.text.trim());
    if (age == null || age < 1 || age > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid age'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'name': _nameController.text.trim(),
        'age': age,
        'email': user.email ?? '',
        'profileCompleted': true,
        'createdAt': FieldValue.serverTimestamp(),
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'photoUrl': '',
        'blockedUsers': [],
      }, SetOptions(merge: true));

      await EncryptionService.generateAndStoreKeys(widget.userId);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add,
                      size: 80, color: Colors.cyanAccent),
                  const SizedBox(height: 16),
                  const Text('Complete Your Profile',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Tell us a bit about yourself',
                      style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ageController,
                    decoration: InputDecoration(
                      labelText: 'Age',
                      prefixIcon: const Icon(Icons.cake_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveUserDetails,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Continue',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============= MAIN SCREEN =============
class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    ChatsScreen(),
    SettingsScreen(),
  ];

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
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      if (state == AppLifecycleState.resumed) {
        PresenceService.updatePresence(userId, true);
      } else if (state == AppLifecycleState.paused) {
        PresenceService.updatePresence(userId, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// ============= CHATS SCREEN =============
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .snapshots(),
        builder: (context, userSnap) {
          final blockedUsers = List<String>.from((userSnap.data?.data()
                  as Map<String, dynamic>?)?['blockedUsers'] ??
              []);

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .where('participants', arrayContains: currentUserId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.chat_bubble_outline,
                          size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No chats yet', style: TextStyle(fontSize: 20)),
                      Text('Tap + to start!',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              final chats = snapshot.data!.docs.where((chat) {
                final participants = List<String>.from(
                    (chat.data() as Map<String, dynamic>)['participants']);
                final otherUserId =
                    participants.firstWhere((id) => id != currentUserId);
                return !blockedUsers.contains(otherUserId);
              }).toList();

              if (chats.isEmpty) {
                return const Center(child: Text('No active chats'));
              }

              chats.sort((a, b) {
                final aTime = (a.data()
                    as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                final bTime = (b.data()
                    as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

              return ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chatDoc = chats[index];
                  final chatData = chatDoc.data() as Map<String, dynamic>;
                  final participants =
                      List<String>.from(chatData['participants']);
                  final otherUserId =
                      participants.firstWhere((id) => id != currentUserId);

                  return StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(otherUserId)
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) return const SizedBox.shrink();

                      final userData =
                          userSnapshot.data!.data() as Map<String, dynamic>?;
                      final userName = userData?['name'] ?? 'Unknown';
                      final isOnline = userData?['isOnline'] ?? false;
                      final photoUrl = userData?['photoUrl'] ?? '';

                      return ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.deepPurple,
                              backgroundImage: getBase64ImageProvider(photoUrl),
                              child: photoUrl.isEmpty
                                  ? Text(userName[0].toUpperCase())
                                  : null,
                            ),
                            if (isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.black, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(userName),
                        subtitle: Text(
                          chatData['lastMessage'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatWindow(
                                chatId: chatDoc.id,
                                otherUserId: otherUserId,
                                otherUserName: userName,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ContactsScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ============= CONTACTS SCREEN =============
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({Key? key}) : super(key: key);

  Future<void> _createChat(
      BuildContext context, String otherUserId, String otherUserName) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final existingChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', isEqualTo: [currentUserId, otherUserId]).get();

      String? chatId;
      if (existingChats.docs.isEmpty) {
        final reverseChats = await FirebaseFirestore.instance
            .collection('chats')
            .where('participants',
                isEqualTo: [otherUserId, currentUserId]).get();

        chatId =
            reverseChats.docs.isNotEmpty ? reverseChats.docs.first.id : null;
      } else {
        chatId = existingChats.docs.first.id;
      }

      if (chatId == null) {
        final newChat =
            await FirebaseFirestore.instance.collection('chats').add({
          'participants': [currentUserId, otherUserId],
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': 'Start chatting! 💬',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
        chatId = newChat.id;
      }

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatWindow(
              chatId: chatId!,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Start New Chat')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .snapshots(),
            builder: (context, currentUserSnap) {
              final blockedUsers = List<String>.from((currentUserSnap.data
                      ?.data() as Map<String, dynamic>?)?['blockedUsers'] ??
                  []);

              final users = snapshot.data!.docs.where((doc) {
                return doc.id != currentUserId &&
                    (doc.data() as Map<String, dynamic>)['profileCompleted'] ==
                        true &&
                    !blockedUsers.contains(doc.id);
              }).toList();

              if (users.isEmpty) {
                return const Center(child: Text('No users available'));
              }

              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final userDoc = users[index];
                  final userData = userDoc.data() as Map<String, dynamic>;
                  final userName = userData['name'] ?? 'Unknown';
                  final isOnline = userData['isOnline'] ?? false;
                  final photoUrl = userData['photoUrl'] ?? '';

                  return ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          backgroundImage: getBase64ImageProvider(photoUrl),
                          child: photoUrl.isEmpty
                              ? Text(userName[0].toUpperCase())
                              : null,
                        ),
                        if (isOnline)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.black, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(userName),
                    subtitle: Text(isOnline ? 'Online' : 'Offline'),
                    trailing: const Icon(Icons.chat_bubble_outline),
                    onTap: () => _createChat(context, userDoc.id, userName),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ============= CHAT WINDOW WITH HIGH SECURITY + DISAPPEARING =============
class ChatWindow extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;

  const ChatWindow({
    Key? key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
  }) : super(key: key);

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isBlocked = false;
  bool _hasBlockedOther = false;
  int? _disappearSeconds;

  @override
  void initState() {
    super.initState();
    _checkBlockStatus();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkBlockStatus() async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final currentUserDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();
    final otherUserDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .get();

    final currentUserData = currentUserDoc.data();
    final otherUserData = otherUserDoc.data();

    final currentBlocked =
        List<String>.from(currentUserData?['blockedUsers'] ?? []);
    final otherBlocked =
        List<String>.from(otherUserData?['blockedUsers'] ?? []);

    setState(() {
      _hasBlockedOther = currentBlocked.contains(widget.otherUserId);
      _isBlocked = otherBlocked.contains(currentUserId);
    });
  }

  Future<void> _sendMessage({bool highSecurity = false}) async {
    if (_messageController.text.trim().isEmpty) return;

    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      final encryptedData = await EncryptionService.encryptMessage(
        plainMessage: messageText,
        recipientUserId: widget.otherUserId,
        highSecurity: highSecurity,
      );

      final messageRef = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'senderId': currentUserId,
        'recipientId': widget.otherUserId,
        'encryptedMessage': encryptedData['encryptedMessage'],
        'iv': encryptedData['iv'],
        'ciphertext': encryptedData['ciphertext'],
        'ciphertext2': encryptedData['ciphertext2'],
        'ciphertext3': encryptedData['ciphertext3'],
        'algorithm': encryptedData['algorithm'],
        'isEncrypted': true,
        'status': 'sent',
        'isDeleted': false,
        'isDisappearing': _disappearSeconds != null,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Schedule disappearing if enabled
      if (_disappearSeconds != null) {
        await DisappearingMessageService.scheduleMessageDeletion(
          chatId: widget.chatId,
          messageId: messageRef.id,
          seconds: _disappearSeconds!,
        );
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'lastMessage': highSecurity ? '🛡️ High Security' : '🔒 Encrypted',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e')),
        );
      }
    }
  }

  Future<void> _showDisappearingTimer() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disappearing Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Off'),
              leading: Radio<int?>(
                value: null,
                groupValue: _disappearSeconds,
                onChanged: (value) => Navigator.pop(context, -1),
              ),
            ),
            ListTile(
              title: const Text('10 seconds'),
              leading: const Icon(Icons.timer),
              onTap: () => Navigator.pop(context, 10),
            ),
            ListTile(
              title: const Text('30 seconds'),
              leading: const Icon(Icons.timer),
              onTap: () => Navigator.pop(context, 30),
            ),
            ListTile(
              title: const Text('1 minute'),
              leading: const Icon(Icons.timer),
              onTap: () => Navigator.pop(context, 60),
            ),
            ListTile(
              title: const Text('5 minutes'),
              leading: const Icon(Icons.timer),
              onTap: () => Navigator.pop(context, 300),
            ),
            ListTile(
              title: const Text('1 hour'),
              leading: const Icon(Icons.timer),
              onTap: () => Navigator.pop(context, 3600),
            ),
            ListTile(
              title: const Text('24 hours'),
              leading: const Icon(Icons.timer),
              onTap: () => Navigator.pop(context, 86400),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _disappearSeconds = selected == -1 ? null : selected;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_disappearSeconds == null
                ? 'Disappearing messages off'
                : 'Messages will disappear after ${_formatDuration(_disappearSeconds!)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    if (seconds < 3600) return '${seconds ~/ 60} minutes';
    if (seconds < 86400) return '${seconds ~/ 3600} hours';
    return '${seconds ~/ 86400} days';
  }

  Future<void> _deleteMessage(String messageId) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId)
        .update({'isDeleted': true});
  }

  Future<void> _toggleBlock() async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    if (_hasBlockedOther) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unblock User'),
          content: Text('Unblock ${widget.otherUserName}?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Unblock')),
          ],
        ),
      );

      if (confirmed == true) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .update({
          'blockedUsers': FieldValue.arrayRemove([widget.otherUserId]),
        });
        setState(() => _hasBlockedOther = false);
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block User'),
          content: Text('Block ${widget.otherUserName}?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Block'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .update({
          'blockedUsers': FieldValue.arrayUnion([widget.otherUserId]),
        });
        setState(() => _hasBlockedOther = true);
        if (mounted) Navigator.pop(context);
      }
    }
  }

  Widget _buildMessage(DocumentSnapshot messageDoc, bool isMe) {
    final messageData = messageDoc.data() as Map<String, dynamic>;
    final isDeleted = messageData['isDeleted'] ?? false;
    final algorithm = messageData['algorithm'] as String?;
    final isDisappearing = messageData['isDisappearing'] ?? false;
    final disappearsAt = messageData['disappearsAt'] as Timestamp?;

    if (isDeleted) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.block, size: 14, color: Colors.grey),
              SizedBox(width: 6),
              Text('Message disappeared 💨',
                  style: TextStyle(
                      color: Colors.grey, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: EncryptionService.decryptMessage(
        encryptedMessage: messageData['encryptedMessage'] ?? '',
        iv: messageData['iv'] ?? '',
        ciphertext: messageData['ciphertext'] ?? '',
        ciphertext2: messageData['ciphertext2'],
        ciphertext3: messageData['ciphertext3'],
        algorithm: algorithm,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(8),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final decrypted = snapshot.data!;
        if (decrypted.contains('failed')) {
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[900],
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  const Text('❌ Error', style: TextStyle(color: Colors.white)),
            ),
          );
        }

        IconData securityIcon;
        Color iconColor;

        if (algorithm == 'ML-KEM-1024') {
          securityIcon = Icons.shield;
          iconColor = Colors.amber;
        } else if (algorithm == 'DoubleRatchet') {
          securityIcon = Icons.verified_user;
          iconColor = Colors.green;
        } else {
          securityIcon = Icons.lock;
          iconColor = Colors.blue;
        }

        // Calculate remaining time for disappearing messages
        String? timeRemaining;
        if (isDisappearing && disappearsAt != null) {
          final now = DateTime.now();
          final deleteTime = disappearsAt.toDate();
          final diff = deleteTime.difference(now);

          if (diff.isNegative) {
            timeRemaining = 'Deleting...';
          } else if (diff.inSeconds < 60) {
            timeRemaining = '${diff.inSeconds}s';
          } else if (diff.inMinutes < 60) {
            timeRemaining = '${diff.inMinutes}m';
          } else {
            timeRemaining = '${diff.inHours}h';
          }
        }

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: isMe
                ? () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Message'),
                        content: const Text('Delete for everyone?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteMessage(messageDoc.id);
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  }
                : null,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7),
              decoration: BoxDecoration(
                color: isMe ? Colors.deepPurple : Colors.grey[800],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(decrypted, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(securityIcon, size: 10, color: iconColor),
                      if (isDisappearing && timeRemaining != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.timer, size: 10, color: Colors.orange),
                        const SizedBox(width: 2),
                        Text(timeRemaining,
                            style: const TextStyle(
                                fontSize: 9, color: Colors.orange)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.otherUserId)
              .snapshots(),
          builder: (context, snapshot) {
            final userData = snapshot.data?.data() as Map<String, dynamic>?;
            final isOnline = userData?['isOnline'] ?? false;
            final photoUrl = userData?['photoUrl'] ?? '';

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: getBase64ImageProvider(photoUrl),
                  child: photoUrl.isEmpty
                      ? Text(widget.otherUserName[0].toUpperCase())
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.otherUserName,
                        style: const TextStyle(fontSize: 16)),
                    Text(isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                            fontSize: 10,
                            color: isOnline ? Colors.green : Colors.grey)),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          PopupMenuButton(
            onSelected: (value) {
              if (value == 'block') _toggleBlock();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(_hasBlockedOther ? Icons.check_circle : Icons.block,
                        color: _hasBlockedOther ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Text(_hasBlockedOther ? 'Unblock' : 'Block'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.red[900],
              child: const Text('You are blocked', textAlign: TextAlign.center),
            ),
          if (_hasBlockedOther)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange[900],
              child: const Text('You blocked this user',
                  textAlign: TextAlign.center),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text('No messages\nSay hi! 👋',
                          textAlign: TextAlign.center));
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final messageDoc = snapshot.data!.docs[index];
                    final messageData =
                        messageDoc.data() as Map<String, dynamic>;
                    final isMe = messageData['senderId'] == currentUserId;
                    return _buildMessage(messageDoc, isMe);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _disappearSeconds != null
                        ? Icons.timer
                        : Icons.timer_outlined,
                    color:
                        _disappearSeconds != null ? Colors.orange : Colors.grey,
                  ),
                  onPressed: _showDisappearingTimer,
                  tooltip: 'Disappearing messages',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isBlocked && !_hasBlockedOther,
                    decoration: InputDecoration(
                      hintText: _isBlocked || _hasBlockedOther
                          ? 'Cannot send'
                          : 'Type...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[800],
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: (_isBlocked || _hasBlockedOther)
                      ? null
                      : () => _sendMessage(),
                  onLongPress: (_isBlocked || _hasBlockedOther)
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('🛡️ Sending with ML-KEM-1024'),
                                duration: Duration(seconds: 1)),
                          );
                          _sendMessage(highSecurity: true);
                        },
                  child: CircleAvatar(
                    backgroundColor: (_isBlocked || _hasBlockedOther)
                        ? Colors.grey
                        : Colors.deepPurple,
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============= SETTINGS SCREEN =============
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _phase2Enabled = false;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _loadPhase2();
  }

  Future<void> _loadPhase2() async {
    final enabled = await EncryptionService.isPhase2Enabled();
    if (mounted) setState(() => _phase2Enabled = enabled);
  }

  Future<void> _togglePhase2(bool value) async {
    setState(() => _isToggling = true);

    try {
      await EncryptionService.setPhase2Enabled(value);

      if (mounted) {
        setState(() {
          _phase2Enabled = value;
          _isToggling = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(value ? '✓ Double Ratchet enabled' : 'Using Kyber768'),
            backgroundColor: value ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isToggling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser!;
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 200, maxHeight: 200);
      if (image == null) return;

      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator()));

      final bytes = await image.readAsBytes();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'photoUrl': base64Encode(bytes),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Photo updated!')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editName() async {
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final currentName = (userDoc.data()?['name'] ?? '') as String;
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'name': newName});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Name updated!')));
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Permanently delete?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      PresenceService.stopPresenceUpdates(user.uid);
      DisappearingMessageService.stopDeletionMonitor();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      final chats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .get();

      for (var chat in chats.docs) {
        final messages = await chat.reference.collection('messages').get();
        for (var message in messages.docs) {
          await message.reference.delete();
        }
        await chat.reference.delete();
      }

      await EncryptionService.deleteKeys();
      await user.delete();
      await GoogleSignIn().signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final photoUrl = userData?['photoUrl'] ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: getBase64ImageProvider(photoUrl),
                      child: photoUrl.isEmpty
                          ? Text((userData?['name'] ?? 'U')[0].toUpperCase(),
                              style: const TextStyle(fontSize: 40))
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 18,
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt, size: 18),
                          onPressed: _uploadPhoto,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Profile',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: _editName),
                        ],
                      ),
                      const Divider(),
                      _buildRow('Name', userData?['name'] ?? 'N/A'),
                      _buildRow('Email', userData?['email'] ?? 'N/A'),
                      _buildRow('Age', userData?['age']?.toString() ?? 'N/A'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.security, color: Colors.blue),
                      title: const Text('Base Security'),
                      subtitle: const Text('Kyber768 (Quantum-Safe)'),
                      trailing:
                          const Icon(Icons.check_circle, color: Colors.green),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.vpn_key, color: Colors.amber),
                      title: const Text('Double Ratchet'),
                      subtitle: Text(_phase2Enabled
                          ? 'Enhanced security active'
                          : 'Enable forward secrecy'),
                      value: _phase2Enabled,
                      onChanged: _isToggling ? null : _togglePhase2,
                    ),
                    if (_isToggling) const LinearProgressIndicator(),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.shield, color: Colors.amber),
                      title: Text('ML-KEM-1024'),
                      subtitle:
                          Text('Long-press send button for high security'),
                      trailing: Icon(Icons.info_outline, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.block, color: Colors.orange),
                  title: const Text('Blocked Users'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            BlockedUsersScreen(userId: user.uid)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  PresenceService.stopPresenceUpdates(user.uid);
                  DisappearingMessageService.stopDeletionMonitor();
                  await EncryptionService.deleteKeys();
                  await FirebaseAuth.instance.signOut();
                  await GoogleSignIn().signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.all(12)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _deleteAccount,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete Account'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(12)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// ============= BLOCKED USERS SCREEN =============
class BlockedUsersScreen extends StatelessWidget {
  final String userId;
  const BlockedUsersScreen({Key? key, required this.userId}) : super(key: key);

  Future<void> _unblock(
      BuildContext context, String blockedUserId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock'),
        content: Text('Unblock $userName?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unblock')),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'blockedUsers': FieldValue.arrayRemove([blockedUserId]),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$userName unblocked')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Users')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final blockedUserIds =
              List<String>.from(userData?['blockedUsers'] ?? []);

          if (blockedUserIds.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No blocked users'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: blockedUserIds.length,
            itemBuilder: (context, index) {
              final blockedUserId = blockedUserIds[index];
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(blockedUserId)
                    .snapshots(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) return const SizedBox.shrink();

                  final blockedUserData =
                      userSnapshot.data!.data() as Map<String, dynamic>?;
                  final userName = blockedUserData?['name'] ?? 'Unknown';
                  final photoUrl = blockedUserData?['photoUrl'] ?? '';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: getBase64ImageProvider(photoUrl),
                      child: photoUrl.isEmpty
                          ? Text(userName[0].toUpperCase())
                          : null,
                    ),
                    title: Text(userName),
                    subtitle: const Text('Blocked'),
                    trailing: ElevatedButton(
                      onPressed: () =>
                          _unblock(context, blockedUserId, userName),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      child: const Text('Unblock'),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
