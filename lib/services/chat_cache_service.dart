/// Shared in-memory message cache used by ChatScreen.
/// Centralised here to avoid circular imports between
/// chat_screen.dart and user_profile_screen.dart.
library chat_cache;

/// Keys are scoped as "<chatId>_<msgKey>".
final Map<String, String> globalChatMessageCache = {};

/// Removes all cached entries for [chatId].
void clearChatMessageCache(String chatId) {
  globalChatMessageCache.removeWhere((k, _) => k.startsWith('${chatId}_'));
}
