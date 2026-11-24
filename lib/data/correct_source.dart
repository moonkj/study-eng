import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'pack_source.dart';

/// '내 상황으로 말하기' 첨삭 결과
class Correction {
  const Correction({
    required this.ok,
    required this.corrected,
    required this.notes,
    this.errorType,
    required this.usedExpression,
  });

  /// 고칠 곳 없이 자연스러운지
  final bool ok;
  final String corrected;

  /// 한국어 설명 1~2문장
  final String notes;
  final String? errorType;
  final bool usedExpression;

  factory Correction.fromJson(Map<String, Object?> j) => Correction(
    ok: j['ok'] as bool,
    corrected: j['corrected'] as String,
    notes: j['notes'] as String,
    errorType: j['errorType'] as String?,
    usedExpression: j['usedExpression'] as bool? ?? true,
  );
}

/// 내가 만든 문장을 첨삭받는 곳 (서버의 Claude)
abstract class CorrectSource {
  Future<Correction> correct({
    required ({String pattern, String highlight, String meaning}) expression,
    String? situationKo,
    required String sentence,
    required String level,
  });
}

class RemoteCorrectSource implements CorrectSource {
  RemoteCorrectSource({required this.url, required this.token, http.Client? client})
    : _client = client ?? http.Client();
  final String url;
  final String token;
  final http.Client _client;

  @override
  Future<Correction> correct({
    required ({String pattern, String highlight, String meaning}) expression,
    String? situationKo,
    required String sentence,
    required String level,
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(url),
            headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
            body: jsonEncode({
              'expression': {
                'pattern': expression.pattern,
                'highlight': expression.highlight,
                'meaning': expression.meaning,
              },
              if (situationKo != null && situationKo.trim().isNotEmpty) 'situationKo': situationKo.trim(),
              'sentence': sentence.trim(),
              'level': level,
            }),
          )
          // 서버 함수 제한 시간(45초)보다 조금 길게
          .timeout(const Duration(seconds: 50));
    } on TimeoutException {
      throw const PackFetchException('첨삭이 너무 오래 걸려요. 잠시 뒤에 다시 시도해 주세요.');
    } catch (_) {
      throw const PackFetchException('서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode != 200) {
      throw PackFetchException(switch (res.statusCode) {
        400 => '문장을 확인해 주세요. (300자 이내)',
        429 || 503 => '요청이 많아요. 잠시 뒤에 다시 시도해 주세요.',
        _ => '첨삭을 받지 못했어요. (${res.statusCode})',
      });
    }
    return Correction.fromJson((jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, Object?>());
  }
}

/// 첨삭 서버 주소: 따로 주지 않으면 학습 팩 주소의 끝 /dailyPack 을 /correct 로 바꿔 쓴다.
const correctApiUrl = String.fromEnvironment('CORRECT_API_URL');

String? correctUrlFor(String packUrl, String explicit) {
  if (explicit.isNotEmpty) return explicit;
  if (packUrl.isEmpty) return null;
  final u = packUrl.replaceFirst(RegExp(r'/dailyPack/?$'), '/correct');
  return u == packUrl ? null : u;
}

final correctSourceProvider = Provider<CorrectSource?>((ref) {
  final url = correctUrlFor(contentApiUrl, correctApiUrl);
  if (url == null || contentApiToken.isEmpty) return null;
  return RemoteCorrectSource(url: url, token: contentApiToken);
});
