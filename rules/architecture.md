# Backend Architecture Rules

## Core Principles
- 비즈니스 로직은 반드시 application / domain 계층에 위치한다
- controller는 request parsing과 response mapping만 담당한다
- repository는 데이터 접근만 담당한다
- 외부 API 호출은 adapter / infrastructure 계층으로 분리한다
- 계층 간 책임 침범을 금지한다
- Prisma 자동생성 타입(`PrismaClient` 타입)은 repository 계층 밖으로 노출하지 않는다

---

## Directory Structure

**현재 존재하는 최상위 구조:**
```text
src/
  common/             ← ResponseInterceptor, AllExceptionsFilter, ApiResponse 타입
    filters/
    interceptors/
    types/
  config/             ← registerAs 네임스페이스 설정
  database/           ← PrismaService (PostgreSQL 주 DB)
    legacy/           ← 레거시 DB 풀·리포지토리 (이관 완료 시 전체 삭제 예정)
      pools/
      repositories/
      dtos/
  health/             ← 헬스체크 모듈
  modules/            ← feature 모듈 (신규 기능은 여기에 추가)
```

**신규 feature 모듈 권장 구조 (예: recordings):**
```text
src/modules/recordings/
  controllers/
  services/
  repositories/    ← Prisma 쿼리 전용, 항상 Prisma 타입 반환
  domain/          ← 순수 비즈니스 규칙, 외부 의존성 없음
  dto/
  entities/        ← 응답 직렬화 모델 (BigInt→string, @Expose 필드 제어)
  mappers/         ← Prisma 타입 ↔ Entity 변환
  validators/
```

모듈 단위로 수직 분리(vertical slice) 우선

---

## Path Aliases
`tsconfig.json` 에 정의된 절대 경로 alias:

| Alias | 실제 경로 |
|---|---|
| `@common/*` | `src/common/*` |
| `@config/*` | `src/config/*` |
| `@modules/*` | `src/modules/*` |
| `@database/*` | `src/database/*` |

---

## Prisma 환경에서 entities/ 폴더 역할

Prisma는 `schema.prisma`가 단일 진실의 원천이다. `@prisma/client`가 타입을 자동 생성하므로
`entities/`에 DB 스키마를 미러링하는 클래스를 만들지 않는다.

`entities/`는 **API 응답 직렬화 모델** 역할만 담당한다:
- `BigInt` PK를 JSON `string`으로 변환 (`@Transform`)
- `@Expose()`로 노출 필드 화이트리스트 관리
- `@ApiProperty()`로 Swagger 스펙 연결

```ts
// Good — 응답 직렬화 모델로서의 entity
export class LearningWeekEntity {
  @ApiProperty({ type: String })
  @Expose()
  @Transform(({ value }) => value?.toString())
  id: string; // BigInt → string

  @Expose()
  weekNo: number;
}
```

```ts
// Bad — Prisma 타입 re-export는 entities 폴더 목적이 아님
export type { LearningWeek } from '@prisma/client';
```

---

## Layer Responsibilities

### Controller Layer
controller는 아래만 담당

- request body parsing
- query param parsing
- auth context extraction
- DTO validation
- response serialization
- HTTP status code mapping

금지:
- 비즈니스 로직
- DB 직접 접근
- 외부 API 호출
- transaction 처리
- Prisma 타입 직접 참조

예시 (Good)
```ts
@Post()
async createUser(@Body() dto: CreateUserDto) {
  return this.userService.create(dto);
}
```

---

### Service Layer
service는 핵심 orchestration 계층

예시:
- 회원가입
- 결제 승인
- Zoom 미팅 생성
- 수강 등록
- 이메일 발송 트리거

service는 여러 repository / adapter 조합 가능.
repository에서 받은 Prisma 타입을 Mapper를 통해 Entity로 변환 후 반환한다.

```ts
async findById(id: string): Promise<LearningWeekEntity> {
  const row = await this.learningWeekRepo.findById(BigInt(id));
  if (!row) throw new NotFoundException(`LearningWeek ${id} not found`);
  return LearningWeekMapper.toEntity(row);
}
```

---

### Repository Layer
repository는 persistence 전용. 항상 Prisma 타입 반환.

허용:
- CRUD
- query builder (`include`, `select`, `where`)
- pagination
- join (Prisma `include` 또는 `$queryRaw`)
- transaction participant

금지:
- business validation
- role check
- permission logic
- Mapper 호출 (변환은 service에서)

```ts
// Good
async findById(id: bigint): Promise<LearningWeek | null> {
  return this.prisma.learningWeek.findUnique({ where: { id } });
}
```

```ts
// Bad — repository에서 mapper 호출
return LearningWeekMapper.toEntity(row);
```

---

### Domain Layer
domain은 순수 비즈니스 규칙 담당

예시:
- 상태 전이
- 할인 계산
- 수강 가능 여부
- 만료일 계산
- 강의 예약 충돌 검증

외부 의존성(Prisma 포함) 금지

```ts
class EnrollmentPolicy {
  canEnroll(course: CourseEntity, user: UserEntity): boolean { ... }
}
```

---

### Mapper Layer
Prisma 타입 → Entity 변환을 전담. 스키마 변경 시 mapper만 수정.

```ts
export class LearningWeekMapper {
  static toEntity(row: PrismaLearningWeek): LearningWeekEntity {
    return plainToInstance(LearningWeekEntity, row, {
      excludeExtraneousValues: true,
    });
  }
}
```

---

## Dependency Direction
반드시 아래 방향 유지

```text
controller -> service -> repository
controller -> service -> adapter
service -> domain
service -> mapper -> entity
repository -> prisma (database)
adapter -> external API
```

절대 금지

```text
repository -> service
domain -> controller
controller -> repository
controller -> prisma (직접 쿼리)
```

---

## External API Integration
외부 연동은 adapter 패턴 사용

```text
src/infrastructure/external-api/
  zoom/
  stripe/
  slack/
```

service에서 직접 axios/fetch 호출 금지

```ts
// Bad
await axios.post(...)

// Good
await this.zoomAdapter.createMeeting(...)
```

---

## Transaction Rules
트랜잭션 규칙은 `database.md` 를 단일 출처로 참조한다.

요약: 결제·수강 등록·포인트 차감·복수 테이블 상태 변경은 반드시 `prisma.$transaction` 사용.

---

## Event Driven Design
후처리는 event 기반 권장

예시:
- 이메일 발송
- 알림
- 로그 적재
- analytics
- webhook callback

```ts
eventBus.emit('payment.completed', payload);
```

동기 처리 최소화

---

## Shared Module Rules
common에는 아래만 허용

- auth
- logger
- exception
- middleware
- utility

비즈니스 로직 shared 분산 금지

```text
// Bad
common/course-utils
```

---

## Error Handling
예외는 명시적 custom exception 사용

```ts
NotFoundException
ForbiddenException
ConflictException
BusinessRuleException
ExternalApiException
```

generic Error throw 금지

---

## Performance Rules
반드시 아래 검토

- N+1 query (Prisma `include` 활용)
- unnecessary join
- over-fetching (`select`로 필요한 컬럼만)
- duplicate API call
- missing cache

목록 API pagination 필수

---

## Logging Rules
service 주요 액션 로그 기록

예시:
- login
- payment
- meeting create
- enrollment
- admin action

민감정보 로깅 금지

---

## Code Review Checklist
- 계층 위반 여부
- transaction 누락 여부
- repository 책임 침범 여부
- domain rule 분리 여부
- external adapter 분리 여부
- 성능 이슈 여부
- Prisma 타입이 repository 밖으로 노출되는지 여부
- BigInt 직렬화 처리 누락 여부
