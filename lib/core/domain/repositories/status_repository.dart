import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/status_item.dart';

abstract interface class StatusRepository {
  Stream<List<StatusItem>> watchStatusFeed();

  Future<Result<void>> createStatus(StatusItem item);

  Future<Result<void>> deleteExpiredStatuses();
}
