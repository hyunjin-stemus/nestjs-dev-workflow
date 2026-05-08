# Database Engineering Rules

## Core Principles
- 데이터 정합성을 최우선으로 한다
- persistence logic과 business logic을 분리한다
- 성능보다 정확성을 우선하되 확장성을 고려한다
- Prisma ORM과 raw query 사용 기준을 명확히 구분한다
- 모든 PK는 `BigInt` (`autoincrement`) — JSON 직렬화 시 반드시 `string` 변환

---

## ORM vs Raw Query Policy

### Prefer Prisma ORM
아래는 Prisma ORM 우선

- 단순 CRUD
- 단건 조회 (`findUnique`, `findFirst`)
- 관계 조회 (`include`, nested `select`)
- pagination (`skip`, `take`)
- create / update / delete
- basic aggregation (`count`, `sum`, `avg`)
- upsert

```ts
await this.prisma.learningWeek.findUnique({
  where: { id },
  select: { id: true, weekNo: true, gradeCode: true },
});
```

---

### Prefer Raw Query
아래는 `$queryRaw` 또는 `$executeRaw` 우선

- 복잡 join 3개 이상
- window function
- recursive query (CTE)
- batch update (단일 쿼리로 처리)
- bulk insert
- analytics / ranking query
- performance critical endpoint

```ts
const rows = await this.prisma.$queryRaw<Row[]>`
  WITH ranked AS (
    SELECT id, week_no, RANK() OVER (ORDER BY week_no) AS rn
    FROM learning_weeks
    WHERE grade_code = ${gradeCode}
  )
  SELECT * FROM ranked WHERE rn <= 10
`;
```

---

## Query Rules
절대 금지: `SELECT *`

반드시 explicit column (`select` 명시)

```ts
// Bad
await this.prisma.user.findMany();

// Good
await this.prisma.user.findMany({
  select: { id: true, email: true, createdAt: true },
});
```

---

## Parameterization
문자열 interpolation 금지. `$queryRaw`는 반드시 tagged template literal 사용.

```ts
// Bad — SQL injection 위험
await this.prisma.$queryRawUnsafe(`SELECT * FROM users WHERE id = ${id}`);

// Good
await this.prisma.$queryRaw`SELECT id, email FROM users WHERE id = ${id}`;
```

---

## BigInt Handling

모든 PK는 `BigInt`. 다음 두 규칙을 반드시 준수.

**1. repository 입력: string → BigInt 변환은 service에서**
```ts
// service
const row = await this.repo.findById(BigInt(id));
```

**2. 응답 직렬화: BigInt → string 변환은 entity mapper에서**
```ts
// entity
@Transform(({ value }) => value?.toString())
id: string;
```

`PrismaService` 생성자에서 `BigInt.prototype.toJSON` 패치가 전역 처리되지만,
응답 모델에서 명시적으로 `@Transform`을 선언해 타입 안전성을 보장한다.

---

## Repository Responsibility
repository는 아래만 담당

- persistence (Prisma 쿼리)
- join (`include`, `$queryRaw`)
- transaction participant
- query 최적화 (`select` 필드 제한)
- **Prisma 타입 그대로 반환** (Mapper 호출 금지)

금지
- 권한 검증
- 할인 정책
- business state transition
- Mapper / Entity 변환

```ts
// Good
async findById(id: bigint): Promise<LearningWeek | null> {
  return this.prisma.learningWeek.findUnique({ where: { id } });
}

// Bad — repository에서 mapper 호출
return LearningWeekMapper.toEntity(row);
```

---

## Mapping Rules
Prisma 타입 → Entity 변환은 Mapper에서. service가 mapper를 호출.
repository 밖으로 Prisma 타입 원본이 controller까지 전파되어서는 안 된다.

```ts
// service (Good)
const row = await this.repo.findById(BigInt(id));
return LearningWeekMapper.toEntity(row);

// service (Bad) — Prisma 타입 그대로 반환
return await this.repo.findById(BigInt(id));
```

---

## Transaction Rules
반드시 `prisma.$transaction` 사용

- 결제
- 수강 등록
- 포인트 차감
- 상태 변경 (복수 테이블)

```ts
await this.prisma.$transaction(async (tx) => {
  await tx.user.update({ where: { id }, data: { status: 'ACTIVE' } });
  await tx.payment.create({ data: { userId: id, amount } });
});
```

interactive transaction (콜백 형태)를 기본으로 사용한다.
sequential transaction (`$transaction([p1, p2])`) 은 독립 쿼리 배열에만 사용.

---

## Locking Strategy
동시성 이슈 가능 시 반드시 검토

예시:
- duplicate payment
- double enrollment
- concurrent point update

Prisma에서 row lock이 필요하면 `$queryRaw`로 `SELECT ... FOR UPDATE` 사용:
```ts
await this.prisma.$queryRaw`
  SELECT id FROM point_wallets WHERE user_id = ${userId} FOR UPDATE
`;
```

---

## Pagination Rules
목록 API는 반드시 pagination

offset pagination (소규모):
```ts
await this.prisma.learningWeek.findMany({
  skip: (page - 1) * size,
  take: size,
  orderBy: { createdAt: 'desc' },
});
```

cursor pagination (대용량 목록 우선):
```ts
await this.prisma.learningContent.findMany({
  take: size,
  cursor: cursor ? { id: BigInt(cursor) } : undefined,
  skip: cursor ? 1 : 0,
  orderBy: { id: 'asc' },
});
```

---

## N+1 Prevention
반드시 아래 확인

```ts
// Bad — N+1
for (const week of weeks) {
  await this.repo.findSessions(week.id);
}

// Good — Prisma include로 한 번에 조회
await this.prisma.learningWeek.findMany({
  include: { sessions: true },
});

// Good — 대량 데이터는 IN 조회
await this.prisma.learningSession.findMany({
  where: { weekId: { in: weekIds } },
});
```

---

## Bulk Operation Rules
반복 insert/update 금지. Prisma bulk API 사용.

```ts
// Bad
for (const item of items) {
  await this.prisma.learningContent.create({ data: item });
}

// Good
await this.prisma.learningContent.createMany({ data: items });

// Good — update는 $transaction + updateMany 조합
await this.prisma.$transaction(
  items.map((item) =>
    this.prisma.learningContent.update({
      where: { id: item.id },
      data: { status: item.status },
    })
  )
);
```

---

## Index Rules
아래는 반드시 index 검토 후 `schema.prisma`에 반영

- foreign key (`@@index`)
- unique key (`@@unique`)
- sorting column
- filtering column (`gradeCode`, `subjectCode`, `status`)
- `createdAt`
- `userId`

```prisma
model LearningSession {
  id      BigInt @id @default(autoincrement())
  weekId  BigInt
  userId  BigInt

  @@index([weekId])
  @@index([userId, weekId])
}
```

---

## Performance Checklist
모든 query 작성 시 반드시 검토

- 예상 row count
- join cost (`include` depth)
- index usage
- sort cost
- scan type
- lock risk
- over-fetching (`select` 필드 제한 여부)

필요 시 `EXPLAIN ANALYZE` 기반으로 최적화:
```ts
await this.prisma.$queryRaw`EXPLAIN ANALYZE SELECT ...`;
```

---

## Migration Rules
DDL 직접 운영 반영 금지. 반드시 Prisma Migrate 사용.

```bash
# 개발 환경
pnpm prisma:migrate:dev

# 마이그레이션 파일 생성 후 schema 적용 확인
pnpm prisma:generate
```

migration 파일 생성 후 **반드시** `database-reviewer` 서브에이전트 호출 (CLAUDE.md 규칙).

---

## Soft Delete Policy
운영 데이터는 soft delete 우선

```prisma
model User {
  deletedAt DateTime?
}
```

Prisma 조회 시 반드시 조건 포함:
```ts
await this.prisma.user.findMany({
  where: { deletedAt: null },
});
```

soft delete가 빈번한 모델은 Prisma middleware로 전역 필터 적용 검토.
