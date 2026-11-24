/// 오프라인 팩·생성 팩이 고르게 돌도록 쓰는 주제 지도: 7개 축 × 상황.
/// 상황마다 "이걸 배우면 할 수 있는 일(can-do)"을 붙여 둔다.
class TopicSituation {
  const TopicSituation({required this.id, required this.axisId, required this.nameKo, required this.canDo});

  /// 예: 'food-cafe'
  final String id;

  /// 속한 축 id (예: 'food')
  final String axisId;

  /// 한국어 이름 (예: '카페에서 주문')
  final String nameKo;

  /// 할 수 있게 되는 일 (한국어 한 줄씩)
  final List<String> canDo;
}

class TopicAxis {
  const TopicAxis({required this.id, required this.nameKo, required this.situations});
  final String id;
  final String nameKo;
  final List<TopicSituation> situations;
}

const topicMap = <TopicAxis>[
  TopicAxis(
    id: 'home',
    nameKo: '일상 · 집',
    situations: [
      TopicSituation(
        id: 'home-morning',
        axisId: 'home',
        nameKo: '아침 준비',
        canDo: ['아침에 하는 일을 순서대로 말할 수 있어요', '늦잠·서두름을 짧게 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'home-chores',
        axisId: 'home',
        nameKo: '집안일 나누기',
        canDo: ['해야 할 집안일을 말할 수 있어요', '같이 사는 사람에게 도움을 부탁할 수 있어요'],
      ),
      TopicSituation(
        id: 'home-cooking',
        axisId: 'home',
        nameKo: '집에서 요리',
        canDo: ['간단한 요리 순서를 설명할 수 있어요', '맛과 재료에 대해 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'home-neighbors',
        axisId: 'home',
        nameKo: '이웃 · 관리실',
        canDo: ['소음·택배 같은 문제를 정중히 말할 수 있어요', '이웃과 가볍게 인사할 수 있어요'],
      ),
      TopicSituation(
        id: 'home-moving',
        axisId: 'home',
        nameKo: '이사 · 집 구하기',
        canDo: ['원하는 집 조건을 말할 수 있어요', '이사 일정과 비용을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'home-repairs',
        axisId: 'home',
        nameKo: '고장 · 수리',
        canDo: ['무엇이 고장 났는지 설명할 수 있어요', '수리 방문 시간을 잡을 수 있어요'],
      ),
      TopicSituation(
        id: 'home-evening',
        axisId: 'home',
        nameKo: '퇴근 후 저녁',
        canDo: ['저녁에 쉬는 방법을 말할 수 있어요', '하루가 어땠는지 이야기할 수 있어요'],
      ),
    ],
  ),
  TopicAxis(
    id: 'work',
    nameKo: '일 · 회사',
    situations: [
      TopicSituation(
        id: 'work-meeting',
        axisId: 'work',
        nameKo: '회의',
        canDo: ['회의에서 안건을 꺼내고 의견을 덧붙일 수 있어요', '논의를 정리하고 다음 단계를 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'work-deadline',
        axisId: 'work',
        nameKo: '마감 · 일정 조율',
        canDo: ['일정을 미루자고 정중히 부탁할 수 있어요', '언제까지 답을 줄지 약속할 수 있어요'],
      ),
      TopicSituation(
        id: 'work-email',
        axisId: 'work',
        nameKo: '업무 메일 · 메신저',
        canDo: ['짧은 업무 메시지를 정중하게 쓸 수 있어요', '파일·자료를 요청할 수 있어요'],
      ),
      TopicSituation(
        id: 'work-smalltalk',
        axisId: 'work',
        nameKo: '동료와 잡담',
        canDo: ['점심·주말 이야기로 가볍게 대화할 수 있어요', '탕비실에서 자연스럽게 말을 걸 수 있어요'],
      ),
      TopicSituation(
        id: 'work-presentation',
        axisId: 'work',
        nameKo: '발표',
        canDo: ['발표를 시작하고 순서를 안내할 수 있어요', '질문에 침착하게 답할 수 있어요'],
      ),
      TopicSituation(
        id: 'work-interview',
        axisId: 'work',
        nameKo: '면접 · 자기소개',
        canDo: ['경력과 강점을 짧게 소개할 수 있어요', '면접 질문에 예를 들어 답할 수 있어요'],
      ),
      TopicSituation(
        id: 'work-problem',
        axisId: 'work',
        nameKo: '문제 보고 · 실수 사과',
        canDo: ['생긴 문제를 차분히 보고할 수 있어요', '실수를 인정하고 해결책을 말할 수 있어요'],
      ),
    ],
  ),
  TopicAxis(
    id: 'food',
    nameKo: '카페 · 식당 · 쇼핑',
    situations: [
      TopicSituation(
        id: 'food-cafe',
        axisId: 'food',
        nameKo: '카페에서 주문',
        canDo: ['원하는 음료를 주문할 수 있어요', '포장·크기·옵션을 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'food-restaurant',
        axisId: 'food',
        nameKo: '식당 예약 · 주문',
        canDo: ['인원과 시간으로 예약할 수 있어요', '주문이 잘못됐을 때 정중히 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'food-clothes',
        axisId: 'food',
        nameKo: '옷 가게',
        canDo: ['사이즈·색을 물어볼 수 있어요', '입어 보고 가격을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'food-grocery',
        axisId: 'food',
        nameKo: '마트 장보기',
        canDo: ['물건 위치를 물어볼 수 있어요', '양과 가격을 비교해 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'food-refund',
        axisId: 'food',
        nameKo: '교환 · 환불',
        canDo: ['교환·환불 이유를 설명할 수 있어요', '영수증·규정을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'food-delivery',
        axisId: 'food',
        nameKo: '배달 · 온라인 주문',
        canDo: ['배달 시간과 주소를 확인할 수 있어요', '주문 문제를 문의할 수 있어요'],
      ),
      TopicSituation(
        id: 'food-paying',
        axisId: 'food',
        nameKo: '계산 · 더치페이',
        canDo: ['계산 방법을 말할 수 있어요', '나눠 내자고 제안할 수 있어요'],
      ),
    ],
  ),
  TopicAxis(
    id: 'travel',
    nameKo: '여행 · 교통',
    situations: [
      TopicSituation(
        id: 'travel-commute',
        axisId: 'travel',
        nameKo: '출근길 · 대중교통',
        canDo: ['늦을 것 같다고 미리 알릴 수 있어요', '교통 상황을 설명할 수 있어요'],
      ),
      TopicSituation(
        id: 'travel-directions',
        axisId: 'travel',
        nameKo: '길 묻기',
        canDo: ['가고 싶은 곳의 위치를 물어볼 수 있어요', '길 안내를 듣고 확인할 수 있어요'],
      ),
      TopicSituation(
        id: 'travel-airport',
        axisId: 'travel',
        nameKo: '공항 · 출장 문제',
        canDo: ['지연·결항 상황을 설명할 수 있어요', '대안을 요청할 수 있어요'],
      ),
      TopicSituation(
        id: 'travel-hotel',
        axisId: 'travel',
        nameKo: '호텔 체크인',
        canDo: ['예약을 확인하고 체크인할 수 있어요', '방에 문제가 있을 때 요청할 수 있어요'],
      ),
      TopicSituation(
        id: 'travel-taxi',
        axisId: 'travel',
        nameKo: '택시 · 차량 호출',
        canDo: ['목적지와 경로를 말할 수 있어요', '요금·시간을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'travel-sightseeing',
        axisId: 'travel',
        nameKo: '관광 · 추천 받기',
        canDo: ['가 볼 만한 곳을 추천받을 수 있어요', '입장권·운영 시간을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'travel-planning',
        axisId: 'travel',
        nameKo: '여행 계획',
        canDo: ['여행 일정과 예산을 이야기할 수 있어요', '가고 싶은 곳을 비교해 말할 수 있어요'],
      ),
    ],
  ),
  TopicAxis(
    id: 'people',
    nameKo: '사람 · 관계',
    situations: [
      TopicSituation(
        id: 'people-intro',
        axisId: 'people',
        nameKo: '처음 만난 사람',
        canDo: ['자기소개를 하고 상대에게 물어볼 수 있어요', '출신·직업·사는 곳을 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'people-plans',
        axisId: 'people',
        nameKo: '약속 잡기',
        canDo: ['시간과 장소를 제안할 수 있어요', '약속을 바꾸거나 거절할 수 있어요'],
      ),
      TopicSituation(
        id: 'people-catchup',
        axisId: 'people',
        nameKo: '오랜만에 만난 친구',
        canDo: ['근황을 묻고 답할 수 있어요', '다음 만남을 제안할 수 있어요'],
      ),
      TopicSituation(
        id: 'people-family',
        axisId: 'people',
        nameKo: '가족 이야기',
        canDo: ['가족을 소개할 수 있어요', '가족과 보낸 시간을 이야기할 수 있어요'],
      ),
      TopicSituation(
        id: 'people-favor',
        axisId: 'people',
        nameKo: '부탁 · 거절',
        canDo: ['부담 없이 부탁할 수 있어요', '미안함을 담아 거절할 수 있어요'],
      ),
      TopicSituation(
        id: 'people-celebrate',
        axisId: 'people',
        nameKo: '축하 · 위로',
        canDo: ['생일·승진을 축하할 수 있어요', '힘든 일을 겪은 사람을 위로할 수 있어요'],
      ),
      TopicSituation(
        id: 'people-conflict',
        axisId: 'people',
        nameKo: '오해 풀기',
        canDo: ['서운한 점을 부드럽게 말할 수 있어요', '사과하고 오해를 풀 수 있어요'],
      ),
    ],
  ),
  TopicAxis(
    id: 'health',
    nameKo: '건강 · 감정',
    situations: [
      TopicSituation(
        id: 'health-sick',
        axisId: 'health',
        nameKo: '몸이 안 좋을 때',
        canDo: ['어디가 아픈지 말할 수 있어요', '쉬라는 조언을 하고 받을 수 있어요'],
      ),
      TopicSituation(
        id: 'health-doctor',
        axisId: 'health',
        nameKo: '병원 · 약국',
        canDo: ['증상과 기간을 설명할 수 있어요', '약 먹는 방법을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'health-stress',
        axisId: 'health',
        nameKo: '스트레스 · 지침',
        canDo: ['요즘 지친 상태를 설명할 수 있어요', '줄이고 싶은 습관을 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'health-exercise',
        axisId: 'health',
        nameKo: '운동 습관',
        canDo: ['하는 운동과 횟수를 말할 수 있어요', '운동 목표를 이야기할 수 있어요'],
      ),
      TopicSituation(
        id: 'health-sleep',
        axisId: 'health',
        nameKo: '잠 · 피로',
        canDo: ['잠을 잘 못 잔 이유를 말할 수 있어요', '피곤함을 자연스럽게 표현할 수 있어요'],
      ),
      TopicSituation(
        id: 'health-feelings',
        axisId: 'health',
        nameKo: '기분 말하기',
        canDo: ['기쁨·실망·걱정을 말할 수 있어요', '상대 기분을 물어볼 수 있어요'],
      ),
      TopicSituation(
        id: 'health-diet',
        axisId: 'health',
        nameKo: '식습관',
        canDo: ['먹는 습관을 설명할 수 있어요', '줄이거나 늘리고 싶은 음식을 말할 수 있어요'],
      ),
    ],
  ),
  TopicAxis(
    id: 'hobby',
    nameKo: '취미 · 주말',
    situations: [
      TopicSituation(
        id: 'hobby-weekend',
        axisId: 'hobby',
        nameKo: '주말 계획',
        canDo: ['주말에 할 일을 말할 수 있어요', '같이 하자고 제안할 수 있어요'],
      ),
      TopicSituation(
        id: 'hobby-new',
        axisId: 'hobby',
        nameKo: '새 취미 시작',
        canDo: ['요즘 빠진 취미를 소개할 수 있어요', '취미를 시작한 계기를 말할 수 있어요'],
      ),
      TopicSituation(
        id: 'hobby-movies',
        axisId: 'hobby',
        nameKo: '영화 · 드라마',
        canDo: ['본 작품의 감상을 말할 수 있어요', '작품을 추천할 수 있어요'],
      ),
      TopicSituation(
        id: 'hobby-music',
        axisId: 'hobby',
        nameKo: '음악 · 공연',
        canDo: ['좋아하는 음악 취향을 말할 수 있어요', '공연에 같이 가자고 할 수 있어요'],
      ),
      TopicSituation(
        id: 'hobby-books',
        axisId: 'hobby',
        nameKo: '책 · 공부',
        canDo: ['읽고 있는 책을 소개할 수 있어요', '공부 습관을 이야기할 수 있어요'],
      ),
      TopicSituation(
        id: 'hobby-outdoors',
        axisId: 'hobby',
        nameKo: '산책 · 등산 · 캠핑',
        canDo: ['야외 활동 계획을 말할 수 있어요', '날씨와 준비물을 이야기할 수 있어요'],
      ),
      TopicSituation(
        id: 'hobby-games',
        axisId: 'hobby',
        nameKo: '게임 · 스포츠 보기',
        canDo: ['좋아하는 팀·게임을 말할 수 있어요', '경기 결과에 반응할 수 있어요'],
      ),
    ],
  ),
];

/// 모든 상황 (축 순서대로)
final List<TopicSituation> allTopicSituations = [for (final a in topicMap) ...a.situations];

/// id 로 축을 찾는다. 없으면 null.
TopicAxis? topicAxisById(String id) {
  for (final a in topicMap) {
    if (a.id == id) return a;
  }
  return null;
}

/// id 로 상황을 찾는다. 없으면 null.
TopicSituation? topicSituationById(String id) {
  for (final s in allTopicSituations) {
    if (s.id == id) return s;
  }
  return null;
}
