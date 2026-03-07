class OutboxRetryPolicy {
  static Duration nextDelay({
    required int retryCount,
    Duration base = const Duration(seconds: 2),
    Duration max = const Duration(minutes: 15),
  }) {
    final rawSeconds = base.inSeconds * (1 << retryCount.clamp(0, 10));
    final bounded = rawSeconds.clamp(base.inSeconds, max.inSeconds);
    return Duration(seconds: bounded);
  }
}
