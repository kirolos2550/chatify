import 'package:flutter/foundation.dart';

class BottomNavVisibilityController {
  BottomNavVisibilityController._();

  static final ValueNotifier<bool> isVisible = ValueNotifier<bool>(true);
  static int _hideCount = 0;

  static void hide() {
    _hideCount += 1;
    if (_hideCount == 1) {
      isVisible.value = false;
    }
  }

  static void show() {
    if (_hideCount == 0) {
      return;
    }
    _hideCount -= 1;
    if (_hideCount == 0) {
      isVisible.value = true;
    }
  }

  static Future<T?> runWithHidden<T>(Future<T?> Function() action) async {
    hide();
    try {
      return await action();
    } finally {
      show();
    }
  }
}
