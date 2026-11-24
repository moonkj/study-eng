import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'pack_source.dart';

/// 토스 문항 유형 (서버에 보내는 이름)
enum ToeicTaskType {
  readAloud('read_aloud'),
  picture('picture'),
  respond('respond'),
  info('info'),
  opinion('opinion');

  const ToeicTaskType(this.wire);
  final String wire;

  static ToeicTaskType? fromWire(Object? v) {
    for (final t in values) {
      if (t.wire == v || t.name == v) return t;
    }
    return null;
  }
}

/// 고칠 문장 하나
class GradeFix {
  const GradeFix({required this.from, required this.to, required this.whyKo});
  final String from;
  final String to;
  final String whyKo;
}

/// 서버(Claude) 채점 결과
class GradeResult {
  const GradeResult({
    required this.score,
    required this.maxScore,
    required this.level,
    required this.summaryKo,
    this.goodKo = const [],
    this.fixes = const [],
    this.improved = '',
    this.nextTipKo = '',
    this.targetMet,
  });

  final int score;
  final int maxScore;
  final String level;
  final String summaryKo;
  final List<String> goodKo;
  final List<GradeFix> fixes;

  /// 같은 내용을 목표 수준으로 다듬은 답
  final String improved;
  final String nextTipKo;

  /// 목표 등급 수준에 닿았는지 (서버가 주면)
  final bool? targetMet;

  /// 0~100 으로 맞춘 점수
  int get percent => maxScore <= 0 ? 0 : (score * 100 / maxScore).round().clamp(0, 100);

  factory GradeResult.fromJson(Map<String, Object?> j) {
    List<String> strings(Object? v) => [for (final s in (v is List ? v : const [])) ?(s is String ? s : null)];
    final max = (j['maxScore'] as num).toInt();
    return GradeResult(
      score: (j['score'] as num).toInt().clamp(0, max),
      maxScore: max,
      level: j['level'] as String? ?? '',
      summaryKo: j['summaryKo'] as String? ?? '',
      goodKo: strings(j['goodKo']),
      fixes: [
        for (final f in (j['fixes'] is List ? j['fixes'] as List : const []))
          if (f is Map && f['from'] is String && f['to'] is String)
            GradeFix(from: f['from'] as String, to: f['to'] as String, whyKo: f['whyKo'] as String? ?? ''),
      ],
      improved: j['improved'] as String? ?? '',
      nextTipKo: j['nextTipKo'] as String? ?? '',
      targetMet: j['targetMet'] as bool?,
    );
  }
}

/// 말한 답을 채점받는 곳 (서버의 Claude)
abstract class GradeSource {
  Future<GradeResult> grade({
    required ToeicTaskType task,
    required String target,
    required String prompt,
    String? reference,
    required String transcript,
    required int seconds,
    required int limitSeconds,
  });
}

class RemoteGradeSource implements GradeSource {
  RemoteGradeSource({required this.url, required this.token, http.Client? client}) : _client = client ?? http.Client();
  final String url;
  final String token;
  final http.Client _client;

  @override
  Future<GradeResult> grade({
    required ToeicTaskType task,
    required String target,
    required String prompt,
    String? reference,
    required String transcript,
    required int seconds,
    required int limitSeconds,
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(url),
            headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
            body: jsonEncode({
              'task': task.wire,
              'target': target,
              'prompt': prompt,
              'reference': ?reference,
              'transcript': transcript.trim(),
              'seconds': seconds,
              'limitSeconds': limitSeconds,
            }),
          )
          .timeout(const Duration(seconds: 50));
    } on TimeoutException {
      throw const PackFetchException('채점이 너무 오래 걸려요. 잠시 뒤에 다시 시도해 주세요.');
    } catch (_) {
      throw const PackFetchException('서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode != 200) {
      throw PackFetchException(switch (res.statusCode) {
        429 || 503 => '요청이 많아요. 잠시 뒤에 다시 시도해 주세요.',
        _ => '채점을 받지 못했어요. (${res.statusCode})',
      });
    }
    try {
      return GradeResult.fromJson((jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, Object?>());
    } catch (_) {
      throw const PackFetchException('채점 결과를 읽지 못했어요.');
    }
  }
}

/// 채점 서버 주소: 따로 주지 않으면 학습 팩 주소의 끝 /dailyPack 을 /grade 로 바꿔 쓴다.
const gradeApiUrl = String.fromEnvironment('GRADE_API_URL');

String? gradeUrlFor(String packUrl, String explicit) {
  if (explicit.isNotEmpty) return explicit;
  if (packUrl.isEmpty) return null;
  final u = packUrl.replaceFirst(RegExp(r'/dailyPack/?$'), '/grade');
  return u == packUrl ? null : u;
}

/// 서버가 없으면 null (화면은 기기 안에서 계산한 피드백만 보여 준다)
final gradeSourceProvider = Provider<GradeSource?>((ref) {
  final url = gradeUrlFor(contentApiUrl, gradeApiUrl);
  if (url == null || contentApiToken.isEmpty) return null;
  return RemoteGradeSource(url: url, token: contentApiToken);
});
