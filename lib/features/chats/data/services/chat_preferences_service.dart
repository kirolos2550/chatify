import 'dart:convert';

import 'package:chatify/features/chats/domain/enums/chat_theme_style.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ChatPreferencesService {
  ChatPreferencesService._();

  static final ChatPreferencesService instance = ChatPreferencesService._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _storageKey = 'chat_preferences_v1';

  Future<ChatThemeStyle> loadTheme({
    required String userId,
    required String conversationId,
  }) async {
    final preferences = await _readPreferences();
    final scopedKey = _scopedConversationKey(
      userId: userId,
      conversationId: conversationId,
    );
    final entry = preferences[scopedKey];
    if (entry is! Map) {
      return ChatThemeStyle.defaultTheme;
    }
    final value = entry['theme']?.toString();
    return ChatThemeStyleX.fromStorage(value);
  }

  Future<void> saveTheme({
    required String userId,
    required String conversationId,
    required ChatThemeStyle theme,
  }) async {
    final preferences = await _readPreferences();
    final scopedKey = _scopedConversationKey(
      userId: userId,
      conversationId: conversationId,
    );

    if (theme == ChatThemeStyle.defaultTheme) {
      preferences.remove(scopedKey);
    } else {
      preferences[scopedKey] = <String, Object?>{'theme': theme.storageValue};
    }

    await _storage.write(key: _storageKey, value: jsonEncode(preferences));
  }

  Future<Map<String, dynamic>> _readPreferences() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // Ignore corrupted preferences and fall back to defaults.
    }
    return <String, dynamic>{};
  }

  String _scopedConversationKey({
    required String userId,
    required String conversationId,
  }) {
    return '${userId.trim()}::${conversationId.trim()}';
  }
}
