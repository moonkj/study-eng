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

  /// 다르게 들린 단어 (a/the/to 같은 약하게 발음되는 기능어는 빼고 알려 준다)
  List<String> get missed => [
    for (final w in words)
      if (!w.matched && !_functionWords.contains(_norm(w.word))) w.word.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), ''),
  ];

  String get verdict => switch (score) {
    >= 95 => '완벽해요',
    >= 80 => '거의 완벽해요',
    >= 60 => '좋아요, 한 번 더 해볼까요?',
    _ => '천천히 다시 따라 해봐요',
  };
}

String _norm(String w) {
  final n = w.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r"[^a-z0-9':]"), '');
  // 콜론은 시각(8:10)에만 남긴다 ("thing:" 같은 문장부호는 뗀다)
  return RegExp(r'^\d{1,2}:\d{2}$').hasMatch(n) ? n : n.replaceAll(':', '');
}

/// 원어민이 약하게 발음해 음성 인식이 자주 놓치는 기능어. 점수 비중을 절반으로 둔다.
/// ('s 를 풀어 쓴 is/has 도 약하게 발음되고, 소유격이면 아예 없으므로 같은 취급)
const _functionWords = {'a', 'an', 'the', 'to', 'of', 'is|has'};

/// 토큰은 '|' 로 여러 후보를 가질 수 있다 ('d = would|had). 후보가 하나라도 같으면 같은 말.
bool _same(String a, String b) => a == b || a.split('|').any(b.split('|').contains);

const _hours = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, //
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
};

/// 인식 결과의 시각 표현을 숫자 읽기로 맞춘다 (quarter past three → three fifteen, noon → twelve).
String _normalizeTimes(String heard) {
  var s = heard.toLowerCase().replaceAll('’', "'");
  s = s.replaceAll(RegExp(r"\bo'?clock\b"), ' ');
  s = s.replaceAll(RegExp(r'\b(noon|midnight)\b'), 'twelve');
  String hourWord(String h) => int.tryParse(h) == null ? h : (_numberWords(int.parse(h))?.join(' ') ?? h);
  s = s.replaceAllMapped(RegExp(r'\b(?:a )?quarter (?:past|after) (\w+)'), (m) => '${hourWord(m[1]!)} fifteen');
  s = s.replaceAllMapped(RegExp(r'\bhalf past (\w+)'), (m) => '${hourWord(m[1]!)} thirty');
  s = s.replaceAllMapped(RegExp(r'\b(?:a )?quarter (?:to|till) (\w+)'), (m) {
    final h = _hours[m[1]!] ?? int.tryParse(m[1]!);
    if (h == null || h < 1 || h > 12) return m[0]!;
    return '${_numberWords(h == 1 ? 12 : h - 1)!.join(' ')} forty five';
  });
  return s;
}

/// 구어 축약 → 풀어 쓴 말 (음성 인식이 어느 쪽으로 돌려줘도 같게 본다)
const _spoken = {
  'gonna': ['going', 'to'],
  'wanna': ['want', 'to'],
  'gotta': ['got', 'to'],
  'kinda': ['kind', 'of'],
  'sorta': ['sort', 'of'],
  'ok': ['okay'],
  'cannot': ['can', 'not'],
  "can't": ['can', 'not'],
  "won't": ['will', 'not'],
  "let's": ['let', 'us'],
  "i'm": ['i', 'am'],
};

const _numbers = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = {20: 'twenty', 30: 'thirty', 40: 'forty', 50: 'fifty'};

/// 0~59 숫자를 영어 단어로 (8:10 → eight ten 처럼 시각 읽기용)
List<String>? _numberWords(int n) {
  if (n < 0 || n > 59) return null;
  if (n < 20) return [_numbers[n]];
  final t = _tens[n - n % 10]!;
  return n % 10 == 0 ? [t] : [t, _numbers[n % 10]];
}

/// 단어 하나를 비교용 토큰들로 펼친다. 축약형(I'll, commute's, don't), 구어(gonna), 숫자(3, 8:10)를
/// 풀어 쓴 형태로 맞춰 어느 쪽으로 말하거나 인식돼도 같은 말로 본다.
List<String> _expand(String raw) {
  final w = _norm(raw);
  if (w.isEmpty) return const [];
  final spoken = _spoken[w];
  if (spoken != null) return spoken;
  final time = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(w);
  if (time != null) {
    final h = _numberWords(int.parse(time[1]!));
    final m = int.parse(time[2]!);
    if (h != null) {
      return [
        ...h,
        if (m > 0 && m < 10) ...['oh', ...?_numberWords(m)] else if (m > 0) ...?_numberWords(m),
      ];
    }
  }
  if (RegExp(r'^\d{1,2}$').hasMatch(w)) {
    final n = _numberWords(int.parse(w));
    if (n != null) return n;
  }
  if (w.endsWith("n't") && w.length > 3) return [w.substring(0, w.length - 3), 'not'];
  if (w.endsWith("'s") && w.length > 2) {
    // is / has 축약이거나 소유격. 인식기는 sister's 를 sisters 로 돌려주기도 한다.
    final stem = w.substring(0, w.length - 2);
    return ['$stem|${stem}s', 'is|has'];
  }
  if (w == 'its') return ['it|its'];
  for (final (suffix, full) in const [("'ll", 'will'), ("'ve", 'have'), ("'re", 'are'), ("'d", 'would|had')]) {
    if (w.endsWith(suffix) && w.length > suffix.length) return [w.substring(0, w.length - suffix.length), full];
  }
  return [w.replaceAll("'", '')];
}

class _Token {
  const _Token(this.text, this.word);
  final String text;

  /// 이 토큰이 나온 화면 단어 번호
  final int word;
}

List<_Token> _tokens(List<String> words) => [
  for (var i = 0; i < words.length; i++)
    for (final t in _expand(words[i])) _Token(t, i),
];

/// 채점. 어떤 입력에도 예외를 던지지 않는다 (저장된 인식 문장을 앱을 켤 때마다 다시 채점하므로).
SpeechScore scoreSpeech(String target, String heard) {
  try {
    return _scoreSpeech(target, heard);
  } catch (_) {
    return SpeechScore(
      score: 0,
      words: [for (final w in target.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) WordMatch(w, false)],
      heard: heard,
    );
  }
}

SpeechScore _scoreSpeech(String target, String heard) {
  // 하이픈은 띄어 쓴 것으로 본다 (well-known = well known)
  final targetWords = target.split(RegExp(r'\s+')).where((w) => _norm(w).isNotEmpty).toList();
  final tt = [
    for (var i = 0; i < targetWords.length; i++)
      for (final part in targetWords[i].split('-'))
        for (final t in _expand(part)) _Token(t, i),
  ];
  final t = [for (final x in tt) x.text];
  final h = [
    for (final x in _tokens(_normalizeTimes(heard).split(RegExp(r'[\s-]+')).where((w) => w.isNotEmpty).toList()))
      x.text,
  ];

  // LCS 로 순서를 지키며 일치한 단어를 찾는다.
  final dp = List.generate(t.length + 1, (_) => List.filled(h.length + 1, 0));
  for (var i = t.length - 1; i >= 0; i--) {
    for (var j = h.length - 1; j >= 0; j--) {
      dp[i][j] = _same(t[i], h[j]) ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final matched = List.filled(t.length, false);
  var i = 0, j = 0;
  while (i < t.length && j < h.length) {
    if (_same(t[i], h[j])) {
      matched[i] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  double weight(String token) => _functionWords.contains(token) ? 0.5 : 1;
  var total = 0.0, got = 0.0;
  for (var k = 0; k < t.length; k++) {
    total += weight(t[k]);
    if (matched[k]) got += weight(t[k]);
  }
  final count = matched.where((m) => m).length;
  // 덧붙인 단어(군말)는 약간만 감점
  final extra = (h.length - count).clamp(0, 99);
  final raw = total == 0 ? 0.0 : got / total * 100 - extra * 3;

  // 화면 단어는 그 단어의 토큰이 모두 맞았을 때 맞은 것으로
  final wordOk = List.filled(targetWords.length, true);
  for (var k = 0; k < tt.length; k++) {
    if (!matched[k]) wordOk[tt[k].word] = false;
  }
  return SpeechScore(
    score: raw.clamp(0, 100).round(),
    words: [for (var k = 0; k < targetWords.length; k++) WordMatch(targetWords[k], wordOk[k])],
    heard: heard,
  );
}
