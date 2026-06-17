import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/settings_provider.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../../services/biometric_service.dart';
import '../../services/theme_service.dart';
import '../../services/websocket_crypto_service.dart';
import '../../services/chat_cache_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? chatId;
  
  const UserProfileScreen({
    Key? key, 
    required this.userId, 
    required this.userName,
    this.chatId,
  }) : super(key: key);
  
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _chatLocked = false;
  bool _isBlocked = false;
  Map<String, dynamic>? _userData;
  bool _editingName = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userName);
    _loadUserData();
    _loadChatLockStatus();
    _enforceScreenProtection();
  }

  Future<void> _enforceScreenProtection() async {
    // Screenshot blocking is always mandatory — no toggle.
    if (Platform.isAndroid) {
      await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
    }
  }



  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Shows camera/gallery picker for own profile photo update.
  Future<void> _pickOrTakePhoto() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D1B3D) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text("Profile Photo",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF581C87))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Color(0xFFD946EF)),
            title: Text("Choose from Gallery",
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Color(0xFFA855F7)),
            title: Text("Take a Photo",
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.grey),
            title: Text("Cancel",
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF581C87))),
            onTap: () => Navigator.pop(context, null),
          ),
        ]),
      ),
    );

    if (choice == null || !mounted) return;
    final picker = ImagePicker();
    final XFile? img = choice == 'camera'
        ? await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 512,
            maxHeight: 512,
            imageQuality: 85,
          )
        : await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 512,
            maxHeight: 512,
            imageQuality: 85,
          );
    if (img == null || !mounted) return;

    final bytes = await File(img.path).readAsBytes();
    final base64Str = base64Encode(bytes);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    // Update both Firestore and SettingsProvider so the photo persists everywhere
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.updateProfile(null, null, base64Str);

    if (!mounted) return;
    setState(() {
      if (_userData != null) _userData!['photoUrl'] = base64Str;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile photo updated!"), backgroundColor: Colors.green),
    );
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (doc.exists && mounted) {
      setState(() => _userData = doc.data());
    }
    
    // Also check if I have blocked this user
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) {
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final List blockedList = List.from(myDoc.data()?['blockedUsers'] ?? []);
      if (mounted) setState(() => _isBlocked = blockedList.contains(widget.userId));
    }
  }

  Future<void> _loadChatLockStatus() async {
    if (widget.chatId != null) {
      final locked = await BiometricService().isChatLockedForUser(widget.chatId!);
      if (mounted) setState(() => _chatLocked = locked);
    }
  }

  Future<void> _toggleChatLock(bool value) async {
    if (widget.chatId == null) return;
    
    if (value) {
      // Authenticate before enabling
      final success = await BiometricService().authenticate(reason: 'Authenticate to lock this chat');
      if (success) {
        await BiometricService().setChatLockedForUser(widget.chatId!, true);
        setState(() => _chatLocked = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chat locked!"), backgroundColor: Colors.green),
        );
      }
    } else {
      // Authenticate before disabling
      final success = await BiometricService().authenticate(reason: 'Authenticate to unlock this chat');
      if (success) {
        await BiometricService().setChatLockedForUser(widget.chatId!, false);
        setState(() => _chatLocked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chat unlocked!"), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isBlockedByMe = settings.blockedUsers.contains(widget.userId);
    _isBlocked = isBlockedByMe; // Update local state if needed elsewhere

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark
        ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)]
        : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final subColor = isDark ? Colors.white70 : const Color(0xFF9333EA);
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.5);
    final glassBorder = Border.all(
      color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.4),
      width: 1.5);

    final photo = _userData?['photoUrl'] ?? '';
    final email = _userData?['email'] ?? '';
    final status = _userData?['status'] ?? 'Hey there! I am using AegisQ';
    final isOnline = _userData?['isOnline'] ?? false;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: textColor),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
                Text("Contact Info", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                const Spacer(),
                if (widget.userId == FirebaseAuth.instance.currentUser?.uid)
                  TextButton.icon(
                    onPressed: () => setState(() => _editingName = true),
                    icon: const Icon(Icons.edit, color: Color(0xFFD946EF), size: 18),
                    label: const Text("Edit", style: TextStyle(color: Color(0xFFD946EF))),
                  ),
              ]),
            ),
            
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Profile Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: glassBorder),
                  child: Column(children: [
                    Stack(children: [
                      GestureDetector(
                        onTap: () {
                          final myUid = FirebaseAuth.instance.currentUser?.uid;
                          if (widget.userId == myUid) {
                            // Own profile: short tap opens picker
                            _pickOrTakePhoto();
                          } else if (photo.isNotEmpty && !isBlockedByMe) {
                            // Other user: view full-screen
                            _openFullScreenPhoto(photo, isOnline);
                          }
                        },
                        onLongPress: () {
                          // Long-press on own photo to view it full-screen
                          final myUid = FirebaseAuth.instance.currentUser?.uid;
                          if (widget.userId == myUid && photo.isNotEmpty) {
                            _openFullScreenPhoto(photo, isOnline);
                          }
                        },
                        child: Stack(
                          children: [
                            Hero(
                              tag: "profile_photo_${widget.userId}",
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFF0ABFC),
                                  image: (photo.isNotEmpty && !isBlockedByMe)
                                      ? DecorationImage(
                                          image: MemoryImage(_safeBase64Decode(photo)!),
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.high,
                                        )
                                      : null,
                                ),
                                child: (photo.isEmpty || isBlockedByMe)
                                    ? Center(
                                        child: Text(widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 40,
                                                fontWeight: FontWeight.bold)))
                                    : null,
                              ),
                            ),
                            // Camera badge for own profile
                            if (widget.userId == FirebaseAuth.instance.currentUser?.uid)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD946EF),
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                                  ),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: (isOnline && !(_userData?['onlineHidden'] ?? false)) ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: isDark ? const Color(0xFF2D1B3D) : Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    if (widget.userId == FirebaseAuth.instance.currentUser?.uid && _editingName)
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Expanded(child: TextField(
                          controller: _nameController,
                          textAlign: TextAlign.center,
                          autofocus: true,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: "Enter name",
                            hintStyle: TextStyle(color: subColor.withOpacity(0.5)),
                            border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD946EF))),
                          ),
                        )),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green, size: 32),
                          onPressed: () async {
                            final newName = _nameController.text.trim();
                            if (newName.isNotEmpty) {
                              await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({'name': newName});
                              await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
                              if (mounted) {
                                setState(() {
                                  _editingName = false;
                                  if (_userData != null) _userData!['name'] = newName;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name updated!"), backgroundColor: Colors.green));
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red, size: 32),
                          onPressed: () => setState(() => _editingName = false),
                        ),
                      ])
                    else
                      GestureDetector(
                        onTap: widget.userId == FirebaseAuth.instance.currentUser?.uid ? () => setState(() => _editingName = true) : null,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(_userData?['name'] ?? widget.userName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                          if (widget.userId == FirebaseAuth.instance.currentUser?.uid) const SizedBox(width: 8),
                          if (widget.userId == FirebaseAuth.instance.currentUser?.uid) const Icon(Icons.edit, size: 20, color: Color(0xFFD946EF)),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final bool showOnline = isOnline && !(_userData?['onlineHidden'] ?? false);
                      return Text(showOnline ? "Online" : "Offline", style: TextStyle(color: showOnline ? Colors.green : Colors.grey, fontWeight: FontWeight.w500));
                    }),
                  ]),
                ),
                
                const SizedBox(height: 24),
                
                // Status/About
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: glassBorder),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("About", style: TextStyle(color: isDark ? const Color(0xFFC084FC) : subColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(_userData?['bio'] ?? 'Hey there! I am using AegisQ', style: TextStyle(color: textColor, fontSize: 16)),
                  ]),
                ),
                
                const SizedBox(height: 24),
                
                // Chat Lock Option (if chatId provided)
                if (widget.chatId != null) ...[
                  Text("CHAT SETTINGS", style: TextStyle(color: isDark ? const Color(0xFFC084FC) : subColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: glassBorder),
                    child: SwitchListTile(
                      secondary: Icon(Icons.fingerprint, color: _chatLocked ? const Color(0xFFD946EF) : subColor),
                      title: Text("Biometric Chat Lock", style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _chatLocked ? "Fingerprint/Face ID active" : "Protect with biometrics",
                        style: TextStyle(color: subColor, fontSize: 12),
                      ),
                      value: _chatLocked,
                      onChanged: _toggleChatLock,
                      activeColor: const Color(0xFFD946EF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "When enabled, you'll need to authenticate with biometrics to view messages in this chat.",
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
                
                const SizedBox(height: 24),

                const SizedBox(height: 24),
                
                // SECURITY PROTOCOL
                Text("SECURITY PROTOCOL", style: TextStyle(color: const Color(0xFFD946EF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: glassBorder),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.sync_alt, color: Color(0xFFD946EF)),
                      title: Text("Rotate Session Keys", style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                      subtitle: Text("Force immediate re-keying (ML-KEM)", style: TextStyle(fontSize: 12, color: subColor)),
                      onTap: () {
                        if (widget.chatId != null) {
                           WebSocketCryptoService().sendRawMessage(widget.chatId!, {"type": "request_handshake"});
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text("Initiating quantum handshake..."), backgroundColor: Color(0xFFD946EF)),
                           );
                        }
                      },
                    ),
                  ]),
                ),

                const SizedBox(height: 24),
                Text("DANGER ZONE", style: TextStyle(color: Colors.red[400], fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: glassBorder),
                  child: Column(children: [
                    if (widget.chatId != null)
                      ListTile(
                        leading: const Icon(Icons.delete_sweep, color: Colors.orange),
                        title: Text("Clear Chat", style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                        subtitle: Text("Permanently delete all messages", style: TextStyle(fontSize: 12, color: subColor)),
                        onTap: () => _showClearChatDialog(),
                      ),
                    if (widget.chatId != null) Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]),
                    if (!isBlockedByMe)
                      ListTile(
                        leading: const Icon(Icons.block, color: Colors.red),
                        title: const Text("Block Contact", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          "Permanently prevent this user from messaging you",
                          style: TextStyle(fontSize: 12, color: subColor),
                        ),
                        onTap: () => _blockPermanently(),
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.lock, color: Colors.red),
                        title: const Text("Permanently Blocked", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        subtitle: Text("This contact is blocked and cannot message you", style: TextStyle(fontSize: 12, color: subColor)),
                      ),
                  ]),
                ),
                
                const SizedBox(height: 24),
                
                // Security Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: glassBorder),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.verified_user, color: Colors.green),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Quantum Encrypted", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      Text("Messages are protected with ML-KEM", style: TextStyle(color: subColor, fontSize: 12, height: 1.4)),
                    ])),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // Supporting Methods
  void _openFullScreenPhoto(String photo, bool isOnline) {
    final bool showOnline = isOnline && !(_userData?['onlineHidden'] ?? false);
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: FullScreenImageViewer(
            imageBase64: photo,
            heroTag: "profile_photo_${widget.userId}",
            userName: _userData?['name'] ?? widget.userName,
            statusText: showOnline ? 'Online' : null,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  Future<void> _showClearChatDialog() async {
    if (widget.chatId == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D1B3D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Clear all messages?", style: TextStyle(color: Colors.red)),
        content: const Text("This will clear all messages in this conversation for you. The other participant will still be able to see them."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Clear for me", style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );

    if (confirm == true) {
      try {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance.collection('chats').doc(widget.chatId!).update({
          'clearedAt.$uid': FieldValue.serverTimestamp(),
        });

        // Clear local message cache so old messages don't reappear via contacts
        clearChatMessageCache(widget.chatId!);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('msg_cache_${widget.chatId}');
        await prefs.remove('hidden_msgs_${widget.chatId}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Chat cleared"), backgroundColor: Colors.orange),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _blockPermanently() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Block Contact?"),
        content: const Text(
            "This will permanently block this contact. This action cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text("Block", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await settings.blockUserPermanently(widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Contact blocked permanently"),
              backgroundColor: Colors.red),
        );
      }
    }
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
}

