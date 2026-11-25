import '../../data/grade_source.dart';
import '../../data/toeic.dart';

/// 질문 하나 (준비 → 답하기)
class ToeicTurn {
  const ToeicTurn({
    required this.number,
    this.question,
    this.showQuestion = true,
    this.speakBefore = const [],
    required this.prepSeconds,
    required this.speakSeconds,
    required this.model,
    required this.gradePrompt,
    this.reference,
  });

  /// 실제 시험 문항 번호 (1~11)
  final int number;

  /// 질문 (문장 읽기·사진 묘사는 없음)
  final String? question;

  /// 화면에 질문을 보여 주는지 (표 보고 답하기는 실제 시험처럼 듣기만 한다)
  final bool showQuestion;

  /// 준비 전에 읽어 줄 말 (질문 등)
  final List<String> speakBefore;
  final int prepSeconds;
  final int speakSeconds;

  /// 목표 단계 모범 답안
  final String model;

  /// 채점 서버에 보낼 문제 설명
  final String gradePrompt;

  /// 원문 (문장 읽기)
  final String? reference;
}

/// 토스 문항 묶음 하나 (문장 읽기 1개, 사진 1장, 질문 3개 묶음 등)
class ToeicTask {
  const ToeicTask({
    required this.id,
    required this.type,
    required this.title,
    required this.directionsKo,
    required this.turns,
    this.keyPhrases = const [],
    this.tips = const [],
    this.passage,
    this.picture,
    this.setting,
    this.info,
    this.readSeconds = 0,
    this.intro,
    this.suggestExpressions = false,
  });

  final String id;
  final ToeicTaskType type;

  /// "Q1 문장 읽기" 같은 제목
  final String title;
  final String directionsKo;
  final List<ToeicTurn> turns;
  final List<String> keyPhrases;

  /// 문장 읽기 요령 (한국어)
  final List<String> tips;

  final String? passage;
  final PictureItem? picture;
  final String? setting;
  final InfoSet? info;

  /// 질문 전에 표를 읽는 시간
  final int readSeconds;

  /// 표 읽기가 끝나면 읽어 주는 안내 (전화 건 사람의 말)
  final String? intro;

  /// 오늘의 표현을 '써 보면 좋은 표현'으로 보여 줄지
  final bool suggestExpressions;

  int get limitSeconds => turns.fold<int>(0, (s, t) => s + t.speakSeconds);

  /// 대략 걸리는 시간(초)
  int get totalSeconds => readSeconds + turns.fold<int>(0, (s, t) => s + t.prepSeconds + t.speakSeconds + 6) + 10;
}

String _q(int a, [int? b]) => b == null ? 'Q$a' : 'Q$a-$b';

ToeicTask readAloudTask(ReadAloudItem item, {int number = 1}) => ToeicTask(
  id: item.id,
  type: ToeicTaskType.readAloud,
  title: '${_q(number)} 문장 읽기',
  directionsKo: '화면의 글을 소리 내어 읽어요. 준비 45초, 읽기 45초.',
  passage: item.text,
  tips: item.tips,
  turns: [
    ToeicTurn(
      number: number,
      prepSeconds: 45,
      speakSeconds: 45,
      model: item.text,
      gradePrompt: 'Read the text aloud.',
      reference: item.text,
    ),
  ],
);

ToeicTask pictureTask(PictureItem item, ToeicTier tier, {int number = 3}) => ToeicTask(
  id: item.id,
  type: ToeicTaskType.picture,
  title: '${_q(number)} 사진 묘사',
  directionsKo: '사진을 최대한 자세히 묘사해요. 준비 45초, 답하기 30초.',
  picture: item,
  keyPhrases: item.keyPhrases.at(tier),
  suggestExpressions: true,
  turns: [
    ToeicTurn(
      number: number,
      prepSeconds: 45,
      speakSeconds: 30,
      model: item.model.at(tier),
      gradePrompt:
          'Describe the picture in as much detail as you can.${item.place.isEmpty ? '' : ' (Place: ${item.place})'}',
      reference: item.model.at(tier),
    ),
  ],
);

ToeicTask respondTask(QuestionSet set, ToeicTier tier) {
  final models = set.models.at(tier);
  const speak = [15, 15, 30];
  return ToeicTask(
    id: set.id,
    type: ToeicTaskType.respond,
    title: '${_q(5, 7)} 질문에 답하기',
    directionsKo: '상황을 읽고 질문 3개에 답해요. 질문마다 준비 3초, 답하기 15·15·30초.',
    setting: set.setting,
    keyPhrases: set.keyPhrases.at(tier),
    suggestExpressions: true,
    turns: [
      for (var i = 0; i < 3; i++)
        ToeicTurn(
          number: 5 + i,
          question: set.questions[i],
          speakBefore: [set.questions[i]],
          prepSeconds: 3,
          speakSeconds: speak[i],
          model: models[i],
          gradePrompt: '${set.setting}\nQuestion: ${set.questions[i]}',
          reference: models[i],
        ),
    ],
  );
}

ToeicTask infoTask(InfoSet set, ToeicTier tier) {
  final models = set.models.at(tier);
  const speak = [15, 15, 30];
  final table = [
    set.table.title,
    ?set.table.subtitle,
    set.table.columns.join(' | '),
    for (final r in set.table.rows) r.join(' | '),
    ...set.table.notes,
  ].join('\n');
  return ToeicTask(
    id: set.id,
    type: ToeicTaskType.info,
    title: '${_q(8, 10)} 표 보고 답하기',
    directionsKo: '표를 45초 동안 읽은 뒤, 들려주는 질문 3개에 답해요. 질문은 화면에 나오지 않아요.',
    info: set,
    readSeconds: 45,
    intro: set.intro,
    keyPhrases: set.keyPhrases.at(tier),
    turns: [
      for (var i = 0; i < 3; i++)
        ToeicTurn(
          number: 8 + i,
          question: set.questions[i],
          showQuestion: false,
          // 실제 시험처럼 마지막 질문은 두 번 읽어 준다
          speakBefore: [if (i == 0) set.intro, set.questions[i], if (i == 2) set.questions[i]],
          prepSeconds: 3,
          speakSeconds: speak[i],
          model: models[i],
          gradePrompt: 'Answer using the information in the table.\n$table\nQuestion: ${set.questions[i]}',
          reference: models[i],
        ),
    ],
  );
}

ToeicTask opinionTask(OpinionItem item, ToeicTier tier) => ToeicTask(
  id: item.id,
  type: ToeicTaskType.opinion,
  title: '${_q(11)} 의견 말하기',
  directionsKo: '질문에 내 의견과 이유를 말해요. 준비 45초, 답하기 60초.',
  keyPhrases: item.keyPhrases.at(tier),
  suggestExpressions: true,
  turns: [
    ToeicTurn(
      number: 11,
      question: item.question,
      speakBefore: [item.question],
      prepSeconds: 45,
      speakSeconds: 60,
      model: item.model.at(tier),
      gradePrompt: item.question,
      reference: item.model.at(tier),
    ),
  ],
);

/// 오늘의 토스 세트 문항들
List<ToeicTask> dailyTasks(ToeicDailySet set, ToeicTier tier) => [
  readAloudTask(set.readAloud),
  pictureTask(set.picture, tier),
  switch (set.block) {
    ToeicBlock.respond => respondTask(set.respond!, tier),
    ToeicBlock.info => infoTask(set.info!, tier),
    ToeicBlock.opinion => opinionTask(set.opinion!, tier),
  },
];

/// 토스 허브 '한 문항 연습': [type] 유형 문항 하나 (목표 단계).
/// 날짜마다 다른 자리에서 시작하고, [avoid] 에 든 문항(오늘 루틴·모의고사·이번에 연습한 문항)은 건너뛴다.
ToeicTask practiceTask(
  ToeicBank bank,
  ToeicTaskType type,
  ToeicTarget target,
  DateTime date, {
  Set<String> avoid = const {},
}) {
  final tier = target.tier;
  // 오늘의 세트(d번째 자리)와 다른 자리에서 시작한다
  final n = dayIndexOf(date) + 1;
  return switch (type) {
    ToeicTaskType.readAloud => readAloudTask(
      practicePick(bank.readAloud, (e) => e.level, (e) => e.id, tier, n, avoid: avoid),
    ),
    ToeicTaskType.picture => pictureTask(
      practicePick(bank.pictures, (e) => e.level, (e) => e.id, tier, n, avoid: avoid),
      tier,
    ),
    ToeicTaskType.respond => respondTask(
      practicePick(bank.questions, (e) => e.level, (e) => e.id, tier, n, avoid: avoid),
      tier,
    ),
    ToeicTaskType.info => infoTask(
      practicePick(bank.infoTables, (e) => e.level, (e) => e.id, tier, n, avoid: avoid),
      tier,
    ),
    ToeicTaskType.opinion => opinionTask(
      practicePick(bank.opinions, (e) => e.level, (e) => e.id, tier, n, avoid: avoid),
      tier,
    ),
  };
}

/// 모의고사 11문항 (묶음 7개)
List<ToeicTask> mockTasks(ToeicMockSet set, ToeicTier tier) => [
  readAloudTask(set.readAloud[0], number: 1),
  readAloudTask(set.readAloud[1], number: 2),
  pictureTask(set.pictures[0], tier, number: 3),
  pictureTask(set.pictures[1], tier, number: 4),
  respondTask(set.respond, tier),
  infoTask(set.info, tier),
  opinionTask(set.opinion, tier),
];
