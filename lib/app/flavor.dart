enum AppFlavor { dev, stage, prod }

extension AppFlavorX on AppFlavor {
  String get nameValue => switch (this) {
    AppFlavor.dev => 'dev',
    AppFlavor.stage => 'stage',
    AppFlavor.prod => 'prod',
  };

  bool get isProd => this == AppFlavor.prod;
}
