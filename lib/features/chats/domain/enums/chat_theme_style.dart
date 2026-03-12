enum ChatThemeStyle { defaultTheme, graphite, sage, sunset }

extension ChatThemeStyleX on ChatThemeStyle {
  static ChatThemeStyle fromStorage(String? value) {
    return ChatThemeStyle.values.firstWhere(
      (theme) => theme.name == value,
      orElse: () => ChatThemeStyle.defaultTheme,
    );
  }

  String get storageValue => name;

  String localizedLabel({required bool isArabic}) {
    return switch (this) {
      ChatThemeStyle.defaultTheme => isArabic ? 'الافتراضي' : 'Default',
      ChatThemeStyle.graphite => isArabic ? 'جرافيت' : 'Graphite',
      ChatThemeStyle.sage => isArabic ? 'سيج' : 'Sage',
      ChatThemeStyle.sunset => isArabic ? 'غروب' : 'Sunset',
    };
  }
}
