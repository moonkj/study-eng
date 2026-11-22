/// 다르게 들린 단어의 철자를 보고, 한국인이 자주 틀리는 발음 요령을 골라 준다.
library;

/// [word] 에 해당하는 발음 요령 (없으면 null). 한 단어에 여러 개면 가장 흔한 실수 하나.
/// l 이 소리 나지 않는 단어
const _silentL = {
  'half',
  'calf',
  'walk',
  'talk',
  'chalk',
  'could',
  'would',
  'should',
  'calm',
  'palm',
  'folk',
  'salmon',
};

/// t 가 소리 나지 않는 단어
const _silentT = {'listen', 'often', 'castle', 'whistle', 'fasten', 'soften', 'christmas'};

String? koreanPronTip(String word) {
  var w = word.toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
  if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
  w = w.replaceAll("'", '');
  if (w.isEmpty) return null;
  if (_silentT.contains(w)) return "이 단어의 't'는 소리 내지 않아요.";
  if (w.contains('th')) return "'th'는 혀끝을 윗니에 살짝 대고 바람을 내보내요 (ㄷ·ㅆ 아님).";
  if (w.contains('v')) return "'v'는 윗니를 아랫입술에 대고 떨어 주세요 (ㅂ 아님).";
  if (w.contains('f') || w.contains('ph') || RegExp(r'(augh|ough)$').hasMatch(w)) {
    return "'f' 소리는 윗니를 아랫입술에 대고 바람만 내요 (ㅍ 아님).";
  }
  if (RegExp(r'(r|er|or|ar|ir|ur)$').hasMatch(w)) return "끝의 'r'은 혀를 뒤로 말아 끝까지 소리 내요 (미국식은 빼먹지 않아요).";
  if (w.contains('r')) return "'r'은 혀끝이 입천장에 닿지 않게 둥글게 말아요 (ㄹ과 달라요).";
  if (w.contains('l') && !_silentL.contains(w)) {
    return w.endsWith('l') || w.endsWith('le')
        ? "끝의 'l'은 혀끝만 윗잇몸에 대고 소리를 삼켜요 ('을'처럼 모음을 붙이지 않아요)."
        : "'l'은 혀끝을 윗잇몸에 꼭 붙였다 떼요 (ㄹ보다 또렷하게).";
  }
  if (w.contains('z')) return "'z'는 'ㅈ'이 아니라 벌이 윙 하는 소리처럼 떨며 내요.";
  if (RegExp(r'[^aeious]s$').hasMatch(w) || w.endsWith('es')) {
    // 앞이 유성음(모음, b d g l m n r v)이면 끝 s 는 /z/
    final voiced = RegExp(r'([bdglmnrv]|[aeiou]e?)s$').hasMatch(w);
    return voiced ? "끝의 -s 는 여기선 '즈'에 가까워요. 빠뜨리지 말고 짧게 붙여요." : "끝의 -s 를 빠뜨리지 말고 짧게 '스'를 붙여요 (모음 없이).";
  }
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
