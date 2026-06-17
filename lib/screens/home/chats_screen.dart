import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/settings_provider.dart';
import '../../services/biometric_service.dart';
import '../../services/chat_cache_service.dart';
import '../chat/chat_screen.dart';
import 'archived_chats_screen.dart';
import 'contacts_screen.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../profile/user_profile_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({Key? key}) : super(key: key);

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Uint8List?> _photoByteCache = {};
  final Map<String, bool> _lockCache = {};
  final Set<String> _fetchingLocks = {};
  final Map<String, StreamSubscription> _userSubscriptions = {};

  @override
  void dispose() {
    _search.dispose();
    for (var sub in _userSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  void _prefetchUser(String userId) {
    if (_userSubscriptions.containsKey(userId)) return;
    final sub = FirebaseFirestore.instance.collection('users').doc(userId).snapshots().listen((doc) {
      if (doc.exists) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        final newPhoto = data['photoUrl'] as String? ?? '';
        if (newPhoto.isNotEmpty && newPhoto != (_userCache[userId]?['photoUrl'] ?? '')) {
          _photoByteCache[userId] = base64Decode(newPhoto);
        } else if (newPhoto.isEmpty) {
          _photoByteCache[userId] = null;
        }
        if (mounted) setState(() => _userCache[userId] = data);
      }
    });
    _userSubscriptions[userId] = sub;
  }

  Future<void> _prefetchLock(String chatId) async {
    if (_lockCache.containsKey(chatId) || _fetchingLocks.contains(chatId)) return;
    _fetchingLocks.add(chatId);
    try {
      final locked = await BiometricService().isChatLockedForUser(chatId);
      if (mounted) setState(() => _lockCache[chatId] = locked);
    } catch (_) {
      if (mounted) setState(() => _lockCache[chatId] = false);
    } finally {
      _fetchingLocks.remove(chatId);
    }
  }

  Widget _buildChatTile(DocumentSnapshot chat, Map<String, dynamic> chatData, SettingsProvider settings, String uid, bool isDark, Color textColor, Color subColor) {
    final isGroup = chatData['isGroup'] as bool? ?? false;
    final participants = List.from(chatData['participants'] ?? []);
    final other = participants.firstWhere((p) => p != uid, orElse: () => '');
    
    if (!isGroup && other.isNotEmpty) {
      _prefetchUser(other);
      _prefetchLock(chat.id);
    }

    final Map<String, dynamic> u = isGroup ? {} : (_userCache[other] ?? {});
    String name = isGroup ? (chatData['groupName'] ?? 'Group') : (u['name'] ?? '');
    String photo = isGroup ? '' : (u['photoUrl'] ?? '');
    
    final lastMsg = chatData['lastMessage'] as String? ?? '';
    final lastTime = chatData['lastMessageTime'] as Timestamp?;
    final lastSenderId = chatData['lastMessageSenderId'] as String? ?? '';
    final isLastFromMe = lastSenderId == uid;
    
    int unreadCount = 0;
    final dynamic unreadVal = chatData['unreadCount'];
    if (unreadVal is Map) {
      unreadCount = (double.tryParse((unreadVal[uid] ?? unreadVal['$uid'] ?? 0).toString()) ?? 0).toInt();
    } else {
      unreadCount = (double.tryParse((chatData['unreadCount.$uid'] ?? chatData['unreadCount_$uid'] ?? 0).toString()) ?? 0).toInt();
    }
    
    final lastMsgStatus = chatData['lastMessageStatus'] as String? ?? 'sent';
    final clearedAtMap = chatData['clearedAt'] as Map<String, dynamic>?;
    final clearedAt = clearedAtMap != null ? clearedAtMap[uid] as Timestamp? : null;
    bool shouldShowLastMsg = lastMsg.trim().isNotEmpty && !lastMsg.toLowerCase().startsWith('tap to start');
    if (clearedAt != null && lastTime != null && lastTime.millisecondsSinceEpoch <= clearedAt.millisecondsSinceEpoch) {
      shouldShowLastMsg = false;
    }

    final lastMsgCiphertext = chatData['lastMessageCiphertext'] as String? ?? '';
    String displayLastMsg = lastMsg;
    if (lastMsgCiphertext.isNotEmpty) {
      final hash = sha256.convert(utf8.encode(lastMsgCiphertext)).toString();
      final scopedKey = "${chat.id}_$hash";
      final cached = globalChatMessageCache[scopedKey];
      if (cached != null) displayLastMsg = cached;
    }
    if (settings.stealthMode) displayLastMsg = '••••••••';

    final finalDisplayName = settings.stealthMode ? 'Secure User' : (name.isEmpty ? 'Unknown User' : name);
    final finalInitials = (name.isNotEmpty) ? name[0].toUpperCase() : '?';
    bool isOnline = isGroup ? false : (u['isOnline'] ?? false);
    final photoBytes = isGroup ? null : _photoByteCache[other];

    return Dismissible(
      key: ValueKey('archive_${chat.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await settings.toggleArchiveChat(chat.id);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: settings.archivedChats.contains(chat.id) ? Colors.green : Colors.orange,
        child: Icon(settings.archivedChats.contains(chat.id) ? Icons.unarchive : Icons.archive, color: Colors.white),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: (photoBytes != null && !isGroup)
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageBytes: photoBytes, userName: finalDisplayName, heroTag: 'avatar_${chat.id}')))
                  : null,
              child: Hero(
                tag: 'chat_avatar_${chat.id}',
                child: CircleAvatar(
                  key: ValueKey('chat_avatar_key_${chat.id}'),
                  radius: 28,
                  backgroundColor: isGroup ? const Color(0xFF9333EA) : const Color(0xFFF0ABFC),
                  backgroundImage: (photoBytes != null) ? MemoryImage(photoBytes) : null,
                  child: (photoBytes != null) ? null : (isGroup ? const Icon(Icons.group, color: Colors.white, size: 28) : Text(finalInitials, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                ),
              ),
            ),
            if (isOnline && !isGroup)
              Positioned(
                right: 0, bottom: 0,
                child: Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: isDark ? const Color(0xFF1A1025) : Colors.white, width: 2))),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(child: Text(finalDisplayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600, color: textColor, fontSize: 16))),
            if (_lockCache[chat.id] == true) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.lock, size: 14, color: subColor.withOpacity(0.5))),
          ],
        ),
        subtitle: Row(
          children: [
            if (isLastFromMe) Padding(padding: const EdgeInsets.only(right: 4), child: _buildTick(lastMsgStatus)),
            Expanded(child: Text(shouldShowLastMsg ? displayLastMsg : (isGroup ? 'Tap to start group chat' : 'Tap to start chatting'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unreadCount > 0 ? textColor : subColor, fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal))),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTime(lastTime),
              style: TextStyle(
                color: (unreadCount > 0 || (!isLastFromMe && lastMsgStatus != 'read' && lastMsg.isNotEmpty)) ? const Color(0xFFD946EF) : subColor,
                fontSize: 11,
                fontWeight: (unreadCount > 0 || (!isLastFromMe && lastMsgStatus != 'read' && lastMsg.isNotEmpty)) ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (unreadCount > 0 || (!isLastFromMe && lastMsgStatus != 'read' && lastMsg.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD946EF),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFD946EF).withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))
                  ],
                ),
                child: Text(
                  (unreadCount > 0) ? (unreadCount > 99 ? '99+' : unreadCount.toString()) : "1",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        onTap: () async {
          final otherName = isGroup ? (chatData['groupName'] ?? 'Group') : finalDisplayName;
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id, otherUserId: other, otherUserName: otherName, isGroup: isGroup)));
          if (mounted) setState(() {});
        },
        onLongPress: () => _showChatOptions(context, chat.id, other, finalDisplayName, isDark, textColor, subColor),
      ),
    );
  }

  void _showChatOptions(BuildContext context, String chatId, String otherId, String name, bool isDark, Color textColor, Color subColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16, left: 12, right: 12),
        child: Container(
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2D1B3D) : Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, -5))]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: subColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              ListTile(leading: Icon(Icons.person_outline, color: subColor), title: Text('View Profile', style: TextStyle(color: textColor)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: otherId, userName: name, chatId: chatId))); }),
              ListTile(leading: const Icon(Icons.clear_all, color: Colors.orange), title: Text('Clear Chat', style: TextStyle(color: textColor)), onTap: () async { Navigator.pop(context); _confirmClearChat(chatId, otherId); }),
              ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: Text('Delete Contact', style: TextStyle(color: textColor.withOpacity(0.8))), onTap: () async { Navigator.pop(context); _confirmDeleteChat(chatId, otherId); }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteChat(String chatId, String otherId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: const Text('This will permanently delete this contact and conversation for you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat deleted'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmClearChat(String chatId, String otherId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(title: const Text('Clear Chat?'), content: const Text('This will clear messages for you.'), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
      ]),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({'clearedAt.${FirebaseAuth.instance.currentUser!.uid}': FieldValue.serverTimestamp()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared'), backgroundColor: Colors.orange));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final uid = FirebaseAuth.instance.currentUser!.uid;
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
                  color: isDark ? const Color(0xFF1A1025) : null,
                  gradient: isDark ? null : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFCBA6F7), Color(0xFFAB77F0), Color(0xFF7C3AED)]),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  boxShadow: [if (!isDark) BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  if (!isDark) ...[
                    Positioned(top: -40, left: -40, child: _blob(120, const Color(0xFF9B5FE0).withOpacity(0.3), const Color(0xFFE2C4FF).withOpacity(0.3))),
                    Positioned(top: -20, right: -20, child: _blob(100, const Color(0xFF9B5FE0).withOpacity(0.3), const Color(0xFFE2C4FF).withOpacity(0.3))),
                    Positioned(bottom: -30, right: -10, child: _blob(80, const Color(0xFF9B5FE0).withOpacity(0.2), const Color(0xFFE2C4FF).withOpacity(0.2))),
                    Positioned(bottom: -10, left: 20, child: _glowOrb(40)),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
                    child: Row(children: [
                      Text('Chats', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? const Color(0xFFA21CAF) : Colors.white, letterSpacing: -1.5)),
                      const Spacer(),
                      IconButton(icon: Icon(Icons.archive_outlined, color: Colors.white, size: 28), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()))),
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
                    color: isDark ? const Color(0xFF2D1B3D) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                    border: Border.all(color: isDark ? Colors.white10 : Colors.deepPurple.withOpacity(0.05)),
                  ),
                  child: TextField(
                    controller: _search,
                    style: TextStyle(color: textColor),
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    decoration: InputDecoration(icon: Icon(Icons.search, color: subColor), hintText: 'Search conversations...', hintStyle: TextStyle(color: subColor.withOpacity(0.4)), border: InputBorder.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: uid).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD946EF)));
                
                final allDocs = snap.data!.docs.toList();
                allDocs.sort((a, b) {
                  final at = (a.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                  final bt = (b.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                  return (bt ?? Timestamp(0, 0)).compareTo(at ?? Timestamp(0, 0));
                });

                final seenOthers = <String>{};
                final filteredChats = <DocumentSnapshot>[];
                
                for (var doc in allDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (settings.archivedChats.contains(doc.id)) continue;
                  
                  // 1. Only show initiated chats (must have actual time/content) or unread messages
                  final lastMsg = data['lastMessage'] as String? ?? '';
                  final lastTime = data['lastMessageTime'] as Timestamp?;
                  final unreadCount = _getUnreadCount(data, uid);
                  
                  // HARD FILTER: Never show placeholder-only chats regardless of unread count
                  final lastMsgLower = lastMsg.toLowerCase().trim();
                  if (lastMsgLower.contains('tap to start') ||
                      lastMsgLower.contains('start chatting')) continue;

                  // A chat is "initiated" if it has actual message content OR had messages deleted
                  bool hasHistory = lastTime != null && lastMsg.trim().isNotEmpty;
                  bool hadPriorMessages = lastTime != null && lastMsg.trim().isEmpty;
                  
                  // ALWAYS show if there are unread messages or valid history
                  if (unreadCount == 0 && !hasHistory && !hadPriorMessages) continue;

                  final isGroup = data['isGroup'] as bool? ?? false;
                  final participants = List.from(data['participants'] ?? []);
                  final otherId = participants.firstWhere((p) => p != uid, orElse: () => '');
                  
                  // 2. Eliminate self-chats/saved messages as requested
                  if (otherId == uid || otherId.isEmpty) continue;

                  // 3. Deduplicate 1-on-1 chats
                  if (!isGroup) {
                    if (seenOthers.contains(otherId)) continue;
                    seenOthers.add(otherId);
                    
                    // 4. Eliminate Unknown Users with no real messages
                    final u = _userCache[otherId] ?? {};
                    final name = u['name'] as String? ?? '';
                    if (name.isEmpty && lastMsg.trim().isEmpty) continue;
                  }
                  
                  if (_query.isNotEmpty) {
                    final gName = (data['groupName'] ?? '').toString().toLowerCase();
                    final otherName = (_userCache[otherId]?['name'] ?? '').toString().toLowerCase();
                    if (!gName.contains(_query) && !otherName.contains(_query)) continue;
                  }
                  
                  // 5. Hide if cleared recently
                  final clearedAtMap = data['clearedAt'] as Map<String, dynamic>?;
                  final clearedAt = clearedAtMap != null ? clearedAtMap[uid] as Timestamp? : null;
                  if (clearedAt != null && lastTime != null && lastTime.millisecondsSinceEpoch <= clearedAt.millisecondsSinceEpoch) {
                    if (unreadCount == 0) continue; // Only hide if no new messages since clear
                  }
                  
                  filteredChats.add(doc);
                }

                if (filteredChats.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_bubble_outline, size: 80, color: subColor.withOpacity(0.1)), const SizedBox(height: 16), Text('No active conversations', style: TextStyle(color: subColor.withOpacity(0.5), fontSize: 16))]));
                
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: filteredChats.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: subColor.withOpacity(0.05), indent: 88),
                  itemBuilder: (context, i) => _buildChatTile(filteredChats[i], filteredChats[i].data() as Map<String, dynamic>, settings, uid, isDark, textColor, subColor),
                );
              },
            ),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen())),
        backgroundColor: const Color(0xFFD946EF),
        elevation: 4,
        child: const Icon(Icons.add_comment_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  String _formatTime(Timestamp? t) {
    if (t == null) return '';
    final d = t.toDate();
    final now = DateTime.now();
    if (now.difference(d).inDays == 0) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day}/${d.month}';
  }

  Widget _buildTick(String status) {
    if (status == 'read') return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    if (status == 'delivered') return const Icon(Icons.done_all, size: 16, color: Colors.grey);
    return const Icon(Icons.done, size: 16, color: Colors.grey);
  }

  int _getUnreadCount(Map<String, dynamic> data, String uid) {
    try {
      final unread = data['unreadCount'];
      if (unread == null) {
         // Deep check for flat keys if map is missing
         for (var key in data.keys) {
           if (key.contains('unreadCount') && key.contains(uid)) {
             return int.tryParse(data[key].toString()) ?? 0;
           }
         }
         return 0;
      }
      if (unread is Map) {
        final val = unread[uid] ?? unread['$uid'];
        if (val != null) return int.tryParse(val.toString()) ?? 0;
        
        // Final desperate search in the map
        for (var k in unread.keys) {
          if (k.toString().contains(uid)) return int.tryParse(unread[k].toString()) ?? 0;
        }
      }
      return int.tryParse(unread.toString()) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Widget _blob(double size, Color c1, Color c2) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [c1, c2])));
  Widget _glowOrb(double size) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFD946EF).withOpacity(0.2), blurRadius: 30, spreadRadius: 5)]));
}
