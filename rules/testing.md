# Testing Rules

## Core Principles
- 모든 신규 기능은 반드시 테스트 코드를 포함한다.
- 버그 수정은 반드시 재현 테스트를 먼저 작성한다.
- 테스트 없는 코드 변경은 원칙적으로 금지한다.
- 테스트는 구현이 아닌 동작(behavior)을 검증한다.

---

## Test Pyramid
우선순위는 아래 순서를 따른다.

1. Unit Test
2. Integration Test
3. E2E Test

E2E 테스트 남용 금지.
가능하면 service / domain layer 단위에서 검증한다.

---

## Unit Test Rules
- 외부 의존성(DB, API, Queue)은 mock 처리한다.
- 순수 함수는 반드시 unit test 작성
- edge case 포함
- null / undefined / empty input 검증 필수
- exception case 필수

예시:
- 빈 배열
- 잘못된 enum 값
- 권한 없음
- 존재하지 않는 ID

---

## Integration Test Rules
아래는 반드시 integration test 작성

- DB transaction
- repository layer
- service orchestration
- external API adapter
- cache layer
- queue producer/consumer

실제 테스트 DB 사용
mock DB 금지

---

## Test Data Cleanup Rules
실제 DB에 접근하는 CRUD 테스트는 반드시 테스트 후 생성된 목 데이터를 삭제한다.

- `afterEach` 또는 `afterAll`에서 테스트 중 생성한 레코드를 반드시 삭제한다.
- 삭제 순서는 FK 제약 위반이 없도록 자식 테이블부터 삭제한다.
- 테스트 실패 시에도 정리 로직이 실행되도록 `try/finally` 패턴을 사용한다.

```ts
// Good
describe('LearningWeekRepository', () => {
  let createdId: bigint;

  afterEach(async () => {
    if (createdId) {
      await prisma.learningWeek.deleteMany({ where: { id: createdId } });
    }
  });

  it('should create a learning week', async () => {
    const row = await repo.create({ weekNo: 1, gradeCode: 'A' });
    createdId = row.id;
    expect(row.weekNo).toBe(1);
  });
});

// Good — 복수 레코드, try/finally 보장
afterAll(async () => {
  try {
    await prisma.learningContent.deleteMany({ where: { sessionId: { in: sessionIds } } });
    await prisma.learningSession.deleteMany({ where: { id: { in: sessionIds } } });
  } finally {
    await prisma.$disconnect();
  }
});
```

```ts
// Bad — 정리 없이 테스트 종료
it('should create a record', async () => {
  await repo.create(data); // 데이터가 DB에 잔류함
});
```

---

## API Test Rules
모든 API는 아래 검증 필수

- status code
- response schema
- validation error
- auth error
- permission error
- business failure case

예시:
- 200
- 201
- 400
- 401
- 403
- 404
- 409
- 500

---

## Coverage
최소 기준

- service layer: 80% 이상
- critical domain: 90% 이상
- utility: 95% 이상

coverage 숫자보다 핵심 비즈니스 로직 검증 우선

---

## Naming
테스트명은 반드시 동작 기반 자연어로 작성

Good:
```ts
describe('UserService', () => {
  it('should create user when valid input is given', () => { ... });
  it('should throw NotFoundException when user does not exist', () => { ... });
});
```

Bad:
```ts
test('test1', ...);
it('userTest', ...);
```

---

## Anti-patterns
금지 사항

- sleep 기반 테스트
- 랜덤 데이터 의존
- 테스트 간 상태 공유
- 실제 운영 API 호출
- 실제 secret 사용