import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../../services/settings_provider.dart';
import '../chat/chat_screen.dart';
import '../chat/create_group_screen.dart';
import '../../widgets/full_screen_image_viewer.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({Key? key}) : super(key: key);

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final Set<String> _navigating = {};
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  Future<void> _startChat(BuildContext context, String otherUserId, String otherUserName) async {
    if (_navigating.contains(otherUserId)) return;
    setState(() => _navigating.add(otherUserId));
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final sortedIds = [uid, otherUserId]..sort();
      final chatId = '${sortedIds[0]}_${sortedIds[1]}';
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUserId: otherUserId, otherUserName: otherUserName)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
    } finally {
      if (mounted) setState(() => _navigating.remove(otherUserId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : const Color(0xFF581C87);
    final subColor = isDark ? const Color(0xFFA21CAF) : const Color(0xFF9333EA);
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF120C1A) : const Color(0xFFF7F0FF),
      body: SafeArea(
        child: Column(children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF120C1A) : null,
                  gradient: isDark ? null : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFCBA6F7), Color(0xFFAB77F0), Color(0xFF7C3AED)]),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  boxShadow: [if (!isDark) BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  if (!isDark) ...[
                    Positioned(top: -30, right: -30, child: _blob(100, const Color(0xFF9B5FE0).withOpacity(0.3), const Color(0xFFE2C4FF).withOpacity(0.3))),
                    Positioned(bottom: -10, left: 20, child: _glowOrb(40)),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
                    child: Row(children: [
                      IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back, color: Colors.white), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      const SizedBox(width: 8),
                      const Text("Add Contacts", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.group_add, color: Colors.white70), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()))),
                    ]),
                  ),
                ]),
              ),
              Positioned(
                bottom: -24,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F122B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                    border: Border.all(color: isDark ? Colors.white10 : Colors.deepPurple.withOpacity(0.05)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: textColor),
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    decoration: InputDecoration(icon: Icon(Icons.search, color: subColor), hintText: 'Search people...', hintStyle: TextStyle(color: subColor.withOpacity(0.4)), border: InputBorder.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: uid).snapshots(),
              builder: (context, chatSnap) {
                // Get list of users we already have initiated chats with
                final Set<String> activeChatUids = {};
                if (chatSnap.hasData) {
                  for (var doc in chatSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final lastMsg = data['lastMessage'] as String? ?? '';
                    final lastTime = data['lastMessageTime'] as Timestamp?;
                    if (lastMsg.isNotEmpty && !lastMsg.toLowerCase().startsWith('tap to start') && lastTime != null) {
                      final participants = List.from(data['participants'] ?? []);
                      final other = participants.firstWhere((p) => p != uid, orElse: () => '');
                      if (other.isNotEmpty) activeChatUids.add(other);
                    }
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD946EF)));
                    
                    final Set<String> seenNames = {};
                    final List<QueryDocumentSnapshot> users = userSnap.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = (data['name'] ?? data['displayName'])?.toString().trim() ?? '';
                      if (doc.id == uid || name.isEmpty || settings.blockedUsers.contains(doc.id)) return false;
                      
                      // 1. Search filtering
                      if (_query.isNotEmpty && !name.toLowerCase().contains(_query)) return false;
                      
                      // 2. Deduplicate by name as requested
                      if (seenNames.contains(name.toLowerCase())) return false;
                      seenNames.add(name.toLowerCase());
                      
                      return true;
                    }).toList();

                    if (users.isEmpty) return const Center(child: Text("No new contacts found", style: TextStyle(color: Colors.grey)));

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: subColor.withOpacity(0.05), indent: 70),
                      itemBuilder: (context, i) {
                        final userData = users[i].data() as Map<String, dynamic>;
                        final name = userData['name'] as String? ?? "User";
                        final photo = userData['photoUrl'] as String? ?? '';
                        final isNavigating = _navigating.contains(users[i].id);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: GestureDetector(
                            onTap: photo.isNotEmpty ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageBase64: photo, userName: name, heroTag: 'contact_${users[i].id}'))) : null,
                            child: Hero(
                              tag: 'contact_avatar_${users[i].id}',
                              child: CircleAvatar(
                                key: ValueKey('contact_avatar_key_${users[i].id}'),
                                radius: 26,
                                backgroundColor: isDark ? const Color(0xFFA21CAF).withOpacity(0.1) : Colors.deepPurple.shade50,
                                backgroundImage: photo.isNotEmpty ? MemoryImage(base64Decode(photo)) : null,
                                child: photo.isEmpty ? Text(name[0].toUpperCase(), style: TextStyle(color: isDark ? const Color(0xFFA21CAF) : subColor, fontWeight: FontWeight.bold, fontSize: 18)) : null,
                              ),
                            ),
                          ),
                          title: Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text("Hey there! I am using AegisQ", style: TextStyle(color: subColor.withOpacity(0.6), fontSize: 13)),
                          trailing: isNavigating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA21CAF))) : Icon(Icons.add_circle_outline, color: subColor, size: 26),
                          onTap: isNavigating ? null : () => _startChat(context, users[i].id, name),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _blob(double size, Color c1, Color c2) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c1, c2])));
  Widget _glowOrb(double size) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFD946EF).withOpacity(0.2), blurRadius: 30, spreadRadius: 5)]));
}
