class StatusExpiry {
  static DateTime buildExpiry(DateTime createdAt) {
    return createdAt.add(const Duration(hours: 24));
  }
}
