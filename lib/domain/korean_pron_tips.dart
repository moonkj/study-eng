/// 다르게 들린 단어의 철자를 보고, 한국인이 자주 틀리는 발음 요령을 골라 준다.
library;

/// [word] 에 해당하는 발음 요령 (없으면 null). 한 단어에 여러 개면 가장 흔한 실수 하나.
String? koreanPronTip(String word) {
  final w = word.toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
  if (w.isEmpty) return null;
  if (w.contains('th')) return "'th'는 혀끝을 윗니에 살짝 대고 바람을 내보내요 (ㄷ·ㅆ 아님).";
  if (w.contains('v')) return "'v'는 윗니를 아랫입술에 대고 떨어 주세요 (ㅂ 아님).";
  if (w.contains('f')) return "'f'는 윗니를 아랫입술에 대고 바람만 내요 (ㅍ 아님).";
  if (w.contains('r') && !w.endsWith('r')) return "'r'은 혀끝이 입천장에 닿지 않게 둥글게 말아요 (ㄹ과 달라요).";
  if (w.contains('l')) return "'l'은 혀끝을 윗잇몸에 꼭 붙였다 떼요. 끝에 오면 '을'처럼 살짝 남겨요.";
  if (w.contains('z')) return "'z'는 'ㅈ'이 아니라 벌이 윙 하는 소리처럼 떨며 내요.";
  if (RegExp(r'[^aeiou]s$').hasMatch(w) || w.endsWith('es')) return "끝의 -s 를 빠뜨리지 말고 짧게 '스'를 붙여요 (모음 없이).";
  if (RegExp(r'(d|t|ed)$').hasMatch(w)) return "끝의 -t/-d 는 '으'를 붙이지 말고 혀만 대고 멈춰요.";
  return null;
}

/// 여러 단어 중 서로 다른 요령을 최대 [max]개
List<String> koreanPronTips(Iterable<String> words, {int max = 2}) {
  final tips = <String>[];
  for (final w in words) {
    final t = koreanPronTip(w);
    if (t != null && !tips.contains(t)) tips.add(t);
    if (tips.length >= max) break;
  }
  return tips;
}
