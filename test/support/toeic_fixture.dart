import 'package:todaye/data/toeic.dart';

/// 테스트용 작은 문항 모음 (content.json 형식). 사진 파일은 없다 (자리 표시로 그려져야 한다).
final Map<String, Object?> toeicFixtureJson = {
  'readAloud': [
    {
      'id': 'ra-1',
      'level': 'basic',
      'text': 'Welcome to City Library. We are open from nine to six.',
      'tips': ['쉼표에서 잠깐 쉬어요.'],
    },
    {'id': 'ra-2', 'level': 'basic', 'text': 'Thank you for calling Green Bank. Please hold the line.'},
    {'id': 'ra-ih', 'level': 'IH', 'text': 'Attention, passengers. The train to Boston has been delayed.'},
  ],
  'pictures': [
    {
      'id': 'pic-1',
      'level': 'basic',
      'file': 'assets/toeic/photos/pic01.jpg',
      'credit': 'Photo: test',
      'place': 'a cafe',
      'model': 'This picture was taken in a cafe. A woman is drinking coffee.',
      'modelIH': 'This photo was taken at a busy cafe. In the foreground, a woman is sipping coffee.',
      'keyPhrases': ['This picture was taken', 'in the foreground'],
      'keyPhrasesIH': ['This photo was taken at', 'sipping'],
      'vocab': [
        {'en': 'sip', 'ko': '홀짝이다'},
      ],
    },
    {
      'id': 'pic-2',
      'level': 'basic',
      'file': 'assets/toeic/photos/pic02.jpg',
      'place': 'a park',
      'model': 'This picture was taken in a park. Two men are walking.',
      'keyPhrases': ['This picture was taken'],
    },
    {
      'id': 'pic-ih',
      'level': 'IH',
      'file': 'assets/toeic/photos/pic03.jpg',
      'place': 'an office',
      'model': 'This is an office.',
      'modelIH': 'This photo shows an open-plan office.',
      'keyPhrases': ['office'],
    },
  ],
  'questions': [
    {
      'id': 'q-1',
      'level': 'basic',
      'setting':
          'Imagine that a marketing firm is doing research in your country. You have agreed to a telephone interview about movies.',
      'questions': [
        'How often do you watch movies?',
        'Who do you usually watch movies with?',
        'Do you prefer watching movies at home or in a theater? Why?',
      ],
      'models': [
        'I watch movies about twice a month.',
        'I usually watch movies with my wife.',
        'I prefer watching movies at home because it is comfortable.',
      ],
      'keyPhrases': ['I usually', 'because'],
    },
  ],
  'infoTables': [
    {
      'id': 'info-1',
      'level': 'basic',
      'table': {
        'title': 'Sales Workshop',
        'subtitle': 'Grand Hotel, May 3',
        'columns': ['Time', 'Session'],
        'rows': [
          ['9:00', 'Welcome speech'],
          ['10:00', 'Customer service'],
        ],
        'notes': ['Lunch provided'],
      },
      'intro': 'Hi, I am attending the workshop. I have some questions.',
      'questions': ['Where is the workshop?', 'What time does it start?', 'What sessions are in the morning?'],
      'models': ['It will be held at the Grand Hotel.', 'It starts at nine.', 'There are two sessions in the morning.'],
    },
  ],
  'opinions': [
    {
      'id': 'op-1',
      'level': 'basic',
      'question': 'Do you agree or disagree: it is better to work from home?',
      'model': 'I agree that it is better to work from home. First, I can save time.',
      'modelIH': 'I strongly agree. Working from home saves commuting time.',
      'modelAL': 'I wholeheartedly agree, mainly because remote work eliminates the commute.',
      'keyPhrases': ['I agree', 'First'],
    },
    // 깨진 문항 (질문 없음): 이것만 버리고 나머지는 읽어야 한다
    {'id': 'op-bad', 'model': 'no question'},
  ],
};

final toeicFixture = ToeicBank.fromJson(toeicFixtureJson);
