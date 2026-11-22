/// 목표 문장과 음성 인식 결과를 단어 단위로 비교해 점수를 낸다.
library;

class WordMatch {
  const WordMatch(this.word, this.matched);

  /// 화면에 보여줄 원래 단어 (구두점 포함)
  final String word;
  final bool matched;
}

class SpeechScore {
  const SpeechScore({required this.score, required this.words, required this.heard});

  /// 0~100
  final int score;
  final List<WordMatch> words;
  final String heard;

  List<String> get missed => [
    for (final w in words)
      if (!w.matched) w.word,
  ];

  String get verdict => switch (score) {
    >= 95 => '완벽해요',
    >= 80 => '거의 완벽해요',
    >= 60 => '좋아요, 한 번 더 해볼까요?',
    _ => '천천히 다시 따라 해봐요',
  };
}

String _norm(String w) => w.toLowerCase().replaceAll(RegExp(r"[^a-z0-9']"), '');

SpeechScore scoreSpeech(String target, String heard) {
  final targetWords = target.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final t = targetWords.map(_norm).toList();
  final h = heard.split(RegExp(r'\s+')).map(_norm).where((w) => w.isNotEmpty).toList();

  // LCS 로 순서를 지키며 일치한 단어를 찾는다.
  final dp = List.generate(t.length + 1, (_) => List.filled(h.length + 1, 0));
  for (var i = t.length - 1; i >= 0; i--) {
    for (var j = h.length - 1; j >= 0; j--) {
      dp[i][j] = t[i] == h[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final matched = List.filled(t.length, false);
  var i = 0, j = 0;
  while (i < t.length && j < h.length) {
    if (t[i] == h[j]) {
      matched[i] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  final count = matched.where((m) => m).length;
  // 단어 일치율에 덧붙인 단어(군말)는 약간만 감점
  final extra = (h.length - count).clamp(0, 99);
  final raw = t.isEmpty ? 0.0 : count / t.length * 100 - extra * 3;
  return SpeechScore(
    score: raw.clamp(0, 100).round(),
    words: [for (var k = 0; k < targetWords.length; k++) WordMatch(targetWords[k], matched[k])],
    heard: heard,
  );
}
