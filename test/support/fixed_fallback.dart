import 'package:todaye/data/models.dart';
import 'package:todaye/data/sample_content.dart';

/// 날짜와 상관없이 원래 기본 팩 하나(A2 이하 samplePackA2, B1 이상 samplePack)만 돌려주는 대체 팩.
/// 기본 팩은 이제 날짜마다 돌아가므로, 특정 팩 내용(actually 등)에 기대는 화면·저장 테스트는 이걸로 고정한다.
DailyPack fixedSamplePackFor(DateTime date, int contentStep) =>
    contentStep <= 5 ? samplePackA2(date) : samplePack(date);
