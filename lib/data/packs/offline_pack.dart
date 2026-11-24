import '../models.dart';

/// 서버 없이 쓰는 기본 팩 하나: 주제 지도의 상황 id 와 날짜를 받아 팩을 만드는 함수.
/// (모델을 바꾸지 않으려고 주제 id 는 팩 바깥에 둔다)
class OfflinePack {
  const OfflinePack({required this.topicId, required this.build});

  /// topic_map.dart 의 상황 id (예: 'food-cafe')
  final String topicId;
  final DailyPack Function(DateTime date) build;
}
