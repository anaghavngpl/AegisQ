import 'package:provider/provider.dart';
import '../../services/settings_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../chat/chat_screen.dart';
import '../../services/biometric_service.dart';

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({Key? key}) : super(key: key);

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  String _formatTime(Timestamp? t) {
    if (t == null) return "";
    final d = t.toDate();
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return "$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}";
  }

  Widget _buildChatTile(QueryDocumentSnapshot chat, String uid, bool isDark,
      Color textColor, Color subColor, SettingsProvider settings) {
    final chatData = chat.data() as Map<String, dynamic>? ?? {};
    final parts = List<String>.from(chatData['participants'] ?? []);
    final other = parts.firstWhere((x) => x != uid, orElse: () => "");
    if (other.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(other).get(),
      builder: (context, usnap) {
        if (!usnap.hasData) return const SizedBox();
        final u = usnap.data!.data() as Map<String, dynamic>? ?? {};
        final isGroup = chatData['isGroup'] == true;
        final name =
            isGroup ? (chatData['groupName'] ?? "Group") : (u['name'] ?? "User");
        final photo = u['photoUrl'] as String? ?? "";
        final displayName = settings.stealthMode ? "Secure User" : name;
        final initials =
            displayName.isNotEmpty ? displayName[0].toUpperCase() : "?";

        final lastMsg = chatData['lastMessage'] ?? "";
        final lastTime = chatData['lastMessageTime'] as Timestamp?;
        final lastSenderId = chatData['lastMessageSenderId'] as String? ?? "";
        String displayLastMsg = settings.stealthMode ? "••••••••" : lastMsg;
        final bool hasContent = lastMsg.trim().isNotEmpty;

        return Dismissible(
          key: ValueKey('unarchive_${chat.id}'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            await settings.toggleArchiveChat(chat.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Chat unarchived"),
                backgroundColor: Color(0xFFD946EF),
                duration: Duration(seconds: 2),
              ));
            }
            return true;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: Colors.green, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.unarchive, color: Colors.white),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.white60,
                borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: isGroup
                      ? const Color(0xFF9333EA)
                      : const Color(0xFFF0ABFC),
                  backgroundImage: (!isGroup && photo.isNotEmpty)
                      ? MemoryImage(base64Decode(photo))
                      : null,
                  child: (!isGroup && photo.isNotEmpty)
                      ? null
                      : (isGroup
                          ? const Icon(Icons.group,
                              color: Colors.white, size: 24)
                          : Text(initials,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 20)))),
              title: Row(
                children: [
                  Expanded(
                      child: Text(displayName,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: textColor))),
                  if (!isGroup)
                    FutureBuilder<bool>(
                      future: BiometricService().isChatLockedForUser(chat.id),
                      builder: (context, snapshot) {
                        if (snapshot.data == true)
                          return const Icon(Icons.lock,
                              size: 14, color: Color(0xFFD946EF));
                        return const SizedBox.shrink();
                      },
                    ),
                ],
              ),
              subtitle: Row(children: [
                Builder(builder: (context) {
                  final isLastFromMe = lastSenderId == uid;
                  final hasRealMessage = lastMsg.trim().isNotEmpty && !lastMsg.toLowerCase().startsWith('start chatting');
                  if (!hasRealMessage || !isLastFromMe) return const SizedBox.shrink();
                  final status = chatData['lastMessageStatus'] as String? ?? 'sent';
                  if (status == 'read') return Row(children: [const Icon(Icons.done_all, size: 16, color: Colors.blue), const SizedBox(width: 4)]);
                  if (status == 'delivered') return Row(children: [const Icon(Icons.done_all, size: 16, color: Colors.grey), const SizedBox(width: 4)]);
                  return Row(children: [const Icon(Icons.done, size: 16, color: Colors.grey), const SizedBox(width: 4)]);
                }),
                Expanded(
                  child: Text(
                    !hasContent ? "" : displayLastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subColor),
                  ),
                )
              ]),
              trailing: Text(_formatTime(lastTime),
                  style: TextStyle(color: subColor, fontSize: 12)),
              onTap: () {
                final data = chat.data() as Map<String, dynamic>? ?? {};
                final isGroup = data['isGroup'] == true;
                final otherName = isGroup ? (data['groupName'] ?? "Group") : name;
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            chatId: chat.id,
                            otherUserId: other,
                            otherUserName: otherName,
                            isGroup: isGroup)));
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark
        ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)]
        : [
            const Color(0xFFFAE8FF),
            const Color(0xFFF5D0FE),
            const Color(0xFFE9D5FF)
          ];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);
    final subColor = isDark ? Colors.white70 : const Color(0xFF9333EA);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Archived Chats",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors)),
        ),
        iconTheme: IconThemeData(color: textColor),
        titleTextStyle: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: bgColors)),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chats')
              .where('participants', arrayContains: uid)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD946EF)));
            
            final allChats = snap.data?.docs ?? [];
            final activeDocs = allChats.where((doc) {
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final lm = data['lastMessage'] as String? ?? "";
              final isGroup = data['isGroup'] == true;
              
              bool hasContent = lm.trim().isNotEmpty && !lm.toLowerCase().contains('start chatting');
              if (!isGroup) {
                final sender = data['lastMessageSenderId'] as String? ?? "";
                if (sender.isEmpty) hasContent = false;
              }
              
              return settings.archivedChats.contains(doc.id) && hasContent;
            }).toList();

            // 2. DEDUPLICATE (Favor null/pending timestamps as newest)
            final Map<String, QueryDocumentSnapshot> uniqueChats = {};
            for (var chat in activeDocs) {
              final data = chat.data() as Map<String, dynamic>? ?? {};
              final isGroup = data['isGroup'] == true;
              final parts = List<String>.from(data['participants'] ?? []);
              
              String key;
              if (isGroup) {
                key = chat.id;
              } else {
                final other = parts.firstWhere((x) => x != uid, orElse: () => "");
                if (other.isEmpty) continue;
                final sortedIds = [uid, other]..sort();
                key = '${sortedIds[0]}_${sortedIds[1]}';
              }

              if (!uniqueChats.containsKey(key)) {
                uniqueChats[key] = chat;
              } else {
                final existingData = uniqueChats[key]!.data() as Map<String, dynamic>? ?? {};
                final existingTime = existingData['lastMessageTime'] as Timestamp?;
                final currentTime = data['lastMessageTime'] as Timestamp?;

                bool isNewer = false;
                if (currentTime == null) {
                  isNewer = true; // Pending is newest
                } else if (existingTime != null && currentTime.compareTo(existingTime) > 0) {
                  isNewer = true;
                }

                if (isNewer) {
                  uniqueChats[key] = chat;
                }
              }
            }
            
            final archivedChats = uniqueChats.values.toList();
            
            // 3. SORT
            archivedChats.sort((a, b) {
              final at = (a.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
              final bt = (b.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
              if (at == null) return -1; // Newest
              if (bt == null) return 1;
              return bt.compareTo(at);
            });

            if (archivedChats.isEmpty) {
              return Center(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_outlined, size: 80, color: subColor),
                  const SizedBox(height: 16),
                  Text("No archived chats",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                ],
              ));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: archivedChats.length,
              itemBuilder: (context, index) => _buildChatTile(
                  archivedChats[index],
                  uid,
                  isDark,
                  textColor,
                  subColor,
                  settings),
            );
          },
        ),
      ),
    );
  }
}
