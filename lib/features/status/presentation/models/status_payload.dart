import 'dart:convert';

import 'package:flutter/material.dart';

class StatusPayload {
  const StatusPayload({
    required this.type,
    this.text = '',
    this.backgroundColor,
    this.textColor,
    this.mediaUrl,
    this.caption,
    this.musicUrl,
    this.musicDurationSeconds,
  });

  final StatusPayloadType type;
  final String text;
  final Color? backgroundColor;
  final Color? textColor;
  final String? mediaUrl;
  final String? caption;
  final String? musicUrl;
  final int? musicDurationSeconds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'text': text,
      'backgroundColor': backgroundColor?.toARGB32(),
      'textColor': textColor?.toARGB32(),
      'mediaUrl': mediaUrl,
      'caption': caption,
      'musicUrl': musicUrl,
      'musicDurationSeconds': musicDurationSeconds,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static StatusPayload fromRaw(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const StatusPayload(type: StatusPayloadType.text, text: '');
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final map = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return fromJson(map);
      }
    } catch (_) {
      // Fallback to plain text payload below.
    }
    return StatusPayload(
      type: StatusPayloadType.text,
      text: trimmed,
      backgroundColor: StatusPayloadDefaults.backgroundColor,
      textColor: StatusPayloadDefaults.textColor,
    );
  }

  static StatusPayload fromJson(Map<String, Object?> json) {
    final rawType = json['type']?.toString().trim().toLowerCase();
    final type = StatusPayloadType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => StatusPayloadType.text,
    );
    final backgroundColor = _toColor(json['backgroundColor']);
    final textColor = _toColor(json['textColor']);
    final text = json['text']?.toString() ?? '';
    final mediaUrl = json['mediaUrl']?.toString().trim();
    final caption = json['caption']?.toString().trim();
    final musicUrl = json['musicUrl']?.toString().trim();
    final musicDurationSeconds = _toInt(json['musicDurationSeconds']);
    return StatusPayload(
      type: type,
      text: text,
      backgroundColor: backgroundColor,
      textColor: textColor,
      mediaUrl: mediaUrl?.isEmpty == true ? null : mediaUrl,
      caption: caption?.isEmpty == true ? null : caption,
      musicUrl: musicUrl?.isEmpty == true ? null : musicUrl,
      musicDurationSeconds: musicDurationSeconds,
    );
  }

  static Color? _toColor(Object? value) {
    if (value is int) {
      return Color(value);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return Color(parsed);
      }
    }
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

enum StatusPayloadType { text, image, video }

abstract final class StatusPayloadDefaults {
  static const Color backgroundColor = Color(0xFFEEF2FA);
  static const Color textColor = Color(0xFF1B2D41);
  static const int musicDurationSeconds = 30;
}
