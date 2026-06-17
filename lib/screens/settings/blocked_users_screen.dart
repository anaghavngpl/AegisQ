import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/settings_provider.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColors = isDark
        ? [const Color(0xFF1A1025), const Color(0xFF2D1B3D)]
        : [const Color(0xFFFAE8FF), const Color(0xFFF5D0FE), const Color(0xFFE9D5FF)];
    final textColor = isDark ? Colors.white : const Color(0xFF581C87);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: bgColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                IconButton(
                    icon: Icon(Icons.arrow_back, color: textColor),
                    onPressed: () => Navigator.of(context).maybePop()),
                Text("Blocked Users",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.lock, size: 14, color: textColor.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Blocked contacts are permanently restricted. Sessions and messages are disabled.",
                      style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  final blockedIds = settings.blockedUsers;

                  if (blockedIds.isEmpty) {
                    return Center(
                        child: Text("No blocked users",
                            style: TextStyle(
                                color: textColor.withOpacity(0.5))));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: blockedIds.length,
                    itemBuilder: (context, i) {
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(blockedIds[i])
                            .get(),
                        builder: (context, uSnap) {
                          if (!uSnap.hasData) return const SizedBox.shrink();
                          final uData =
                              uSnap.data!.data() as Map<String, dynamic>? ?? {};
                          final name = uData['name'] ?? "Unknown User";
                          final photo = uData['photoUrl'] ?? "";

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                                color: Colors.white
                                    .withOpacity(isDark ? 0.1 : 0.5),
                                borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFF0ABFC),
                                backgroundImage: photo.isNotEmpty
                                    ? MemoryImage(base64Decode(photo))
                                    : null,
                                child: photo.isEmpty
                                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                            color: Colors.white))
                                    : null,
                              ),
                              title: Text(name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textColor)),
                              subtitle: Text(
                                "Blocked",
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.withOpacity(0.8)),
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text("Unblock User?"),
                                      content: Text("Are you sure you want to unblock $name?"),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true), 
                                          child: const Text("Unblock", style: TextStyle(color: Color(0xFFD946EF), fontWeight: FontWeight.bold))
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await settings.toggleBlockUser(blockedIds[i]);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("$name unblocked")),
                                    );
                                  }
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFFD946EF).withOpacity(0.1),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                                child: const Text("Unblock", 
                                  style: TextStyle(color: Color(0xFFD946EF), fontWeight: FontWeight.bold, fontSize: 13)
                                ),
                              ),
                            ),
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
      ),
    );
  }
}
