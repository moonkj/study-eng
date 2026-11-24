/// 목표 문장과 인식 결과를 맞대어 "think → sink 로 들렸어요" 같은 단어 대치 쌍을 찾고,
/// 한국인이 자주 헷갈리는 소리 쌍이면 맞춤 요령을 붙인다.
library;

class Substitution {
  const Substitution(this.said, this.heard, this.tip);

  /// 말하려던 단어 (목표 문장)
  final String said;

  /// 그렇게 들린 단어 (인식 결과)
  final String heard;

  /// 소리 쌍 요령 (알려진 쌍이 아니면 null)
  final String? tip;
}

String _n(String w) => w.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r"[^a-z']"), '');

/// 한국인이 자주 바꿔 내는 소리 쌍: (목표 철자, 들린 철자, 요령)
const _pairs = [
  ('th', 's', "'th'를 'ㅆ'처럼 냈어요. 혀끝을 윗니 사이에 살짝 내밀고 바람을 내보내요."),
  ('th', 't', "'th'를 'ㅌ'처럼 냈어요. 혀끝을 윗니에 대고 막지 말고 바람을 흘려요."),
  ('th', 'd', "'th'를 'ㄷ'처럼 냈어요. 혀끝을 윗니 사이에 두고 목을 울리며 바람을 내요."),
  ('th', 'f', "'th'가 'f'로 들렸어요. 입술이 아니라 혀끝을 윗니에 대요."),
  ('r', 'l', "'r'이 'l'로 들렸어요. 혀끝이 입천장에 닿지 않게 뒤로 둥글게 말아요."),
  ('l', 'r', "'l'이 'r'로 들렸어요. 혀끝을 윗잇몸에 꼭 붙였다 떼요."),
  ('v', 'b', "'v'가 'b'로 들렸어요. 두 입술을 붙이지 말고 윗니를 아랫입술에 대고 떨어요."),
  ('f', 'p', "'f'가 'p'로 들렸어요. 입술을 붙이지 말고 윗니를 아랫입술에 대고 바람만 내요."),
  ('z', 'j', "'z'가 'ㅈ'처럼 들렸어요. 혀를 윗잇몸 가까이 두고 벌처럼 '즈-' 떨어요."),
  ('ee', 'i', "긴 '이-'가 짧게 들렸어요. 입꼬리를 옆으로 당기고 길게 '이-' 해요."),
  ('i', 'ee', "짧은 'i'가 길게 들렸어요. 힘을 빼고 짧게 '이'와 '에' 사이로 내요."),
];

/// [said] 를 [heard] 로 바꿔 낸 소리 쌍 요령 (끝소리 빠뜨림 포함). 없으면 null.
String? pairTip(String said, String heard) {
  final a = _n(said), b = _n(heard);
  if (a.isEmpty || b.isEmpty || a == b) return null;
  for (final (from, to, tip) in _pairs) {
    var i = a.indexOf(from);
    while (i >= 0) {
      if (a.replaceRange(i, i + from.length, to) == b) return tip;
      i = a.indexOf(from, i + 1);
    }
  }
  // 끝소리를 빠뜨림: works → work, walked → walk
  for (final end in ['s', 'es', 'd', 'ed', 't']) {
    if (a.endsWith(end) && a.substring(0, a.length - end.length) == b) {
      return "끝의 '$end' 소리가 빠졌어요. 단어 끝까지 짧게 붙여 말해요.";
    }
  }
  return null;
}

/// 목표 문장과 인식 문장에서 단어 대치 쌍을 찾는다 (최대 [max]개).
/// 순서를 지키며 같은 단어를 기준점으로 맞추고, 기준점 사이에 남은 단어끼리 1:1 로 짝짓는다.
List<Substitution> findSubstitutions(String target, String heard, {int max = 2}) {
  final t = target.split(RegExp(r'\s+')).where((w) => _n(w).isNotEmpty).toList();
  final h = heard.split(RegExp(r'\s+')).where((w) => _n(w).isNotEmpty).toList();
  if (t.isEmpty || h.isEmpty) return const [];
  final dp = List.generate(t.length + 1, (_) => List.filled(h.length + 1, 0));
  for (var i = t.length - 1; i >= 0; i--) {
    for (var j = h.length - 1; j >= 0; j--) {
      dp[i][j] = _n(t[i]) == _n(h[j])
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <Substitution>[];
  var i = 0, j = 0;
  final gapT = <String>[], gapH = <String>[];
  void flush() {
    // 빠진 단어 수와 들린 단어 수가 같을 때만 짝짓는다 (억지로 짝지은 엉뚱한 쌍을 보여 주지 않게)
    if (gapT.length == gapH.length) {
      for (var k = 0; k < gapT.length; k++) {
        final said = gapT[k].replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
        final tip = pairTip(said, gapH[k]);
        if (tip != null || _close(_n(said), _n(gapH[k]))) out.add(Substitution(said, _n(gapH[k]), tip));
      }
    }
    gapT.clear();
    gapH.clear();
  }

  while (i < t.length || j < h.length) {
    if (i < t.length && j < h.length && _n(t[i]) == _n(h[j])) {
      flush();
      i++;
      j++;
    } else if (j >= h.length || (i < t.length && dp[i + 1][j] >= dp[i][j + 1])) {
      gapT.add(t[i++]);
    } else {
      gapH.add(h[j++]);
    }
  }
  flush();
  // 요령이 있는 쌍을 먼저
  out.sort((a, b) => (a.tip == null ? 1 : 0) - (b.tip == null ? 1 : 0));
  return out.take(max).toList();
}

/// 철자가 비슷한 단어인지 (편집 거리 2 이하, 너무 짧은 단어는 1 이하)
bool _close(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  final limit = a.length <= 3 ? 1 : 2;
  if ((a.length - b.length).abs() > limit) return false;
  var prev = List.generate(b.length + 1, (k) => k);
  for (var x = 1; x <= a.length; x++) {
    final cur = [x, ...List.filled(b.length, 0)];
    for (var y = 1; y <= b.length; y++) {
      final cost = a[x - 1] == b[y - 1] ? 0 : 1;
      cur[y] = [prev[y] + 1, cur[y - 1] + 1, prev[y - 1] + cost].reduce((p, q) => p < q ? p : q);
    }
    prev = cur;
  }
  return prev[b.length] <= limit;
}
