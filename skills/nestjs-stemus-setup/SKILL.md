---
name: nestjs-stemus-setup
description: Stemus NestJS 백엔드 프로젝트 초기 세팅 스킬. `nest new` 이후 표준 공통 레이어 전체를 설치하고 파일을 생성한다. 새 백엔드 레포를 시작할 때, 또는 "NestJS 프로젝트 세팅", "백엔드 초기 구성", "새 API 서버 만들어줘" 같은 요청이 오면 반드시 이 스킬을 사용한다.

포함 항목:
- 공통 응답 래퍼 (ApiResponse, ResponseInterceptor, AllExceptionsFilter)
- Winston 로거 (DailyRotateFile + KST + AsyncLocalStorage RequestContext)
- Prisma 7 + PrismaPg 어댑터
- Redis (ioredis, Global 모듈)
- JWT Auth (Redis 세션 + JTI 블록리스트 + Epoch 무효화)
- Rate Limiting (ThrottlerModule + Redis 스토리지 + 사용자 기반 트래커)
- ChannelTalk 알림 어댑터 (5xx 오류 알림)
- AWS S3 어댑터 (업로드/삭제/Presigned URL)
- Health Check (Prisma + Redis)
- 전체 설정(config), tsconfig 경로 alias, ESLint, Prettier
---

# NestJS Stemus 표준 프로젝트 세팅

## 사전 확인

시작 전 반드시 확인:
```bash
nest --version   # NestJS CLI 필수
pnpm --version   # 패키지 매니저
```

## 진행 순서

1. 프로젝트 이름을 사용자에게 확인한다.
2. `nest new` 실행
3. 기본 파일 제거
4. 의존성 설치
5. 설정·공통 파일 생성 (references/ 참조)
6. 검증

---

## Step 1: 프로젝트 생성 및 기본 파일 정리

```bash
nest new <PROJECT_NAME> --package-manager pnpm --skip-git
cd <PROJECT_NAME>

# 기본 생성 파일 제거 (덮어쓸 것들)
rm src/app.controller.ts src/app.controller.spec.ts src/app.service.ts src/app.module.ts src/main.ts
```

## Step 2: package.json 의존성 교체

`package.json`을 아래 내용으로 완전히 교체한다. `<PROJECT_NAME>`은 실제 이름으로 바꾼다.
→ references/08-root.md 의 "package.json 템플릿" 참조

## Step 3: 설정 파일 생성

아래 파일을 **모두** 생성한다. 각 파일의 내용은 해당 references 파일을 읽고 복사한다.

### tsconfig.json / ESLint / Prettier
→ references/08-root.md 의 "tsconfig.json", "eslint.config.mjs", ".prettierrc" 참조

### src/config/ (7개 파일)
→ references/03-config.md 참조
- `src/config/app.config.ts`
- `src/config/jwt.config.ts`
- `src/config/logger.config.ts`
- `src/config/redis.config.ts`
- `src/config/throttler.config.ts`
- `src/config/s3.config.ts`
- `src/config/channel-talk.config.ts`

### src/common/ (공통 레이어)
→ references/01-common.md 참조
- `src/common/types/api-response.type.ts`
- `src/common/interceptors/response.interceptor.ts`
- `src/common/filters/alert-notifier.interface.ts`
- `src/common/filters/all-exceptions.filter.ts`
- `src/common/guards/throttler.guard.ts`
- `src/common/decorators/enforce-throttle.decorator.ts`

### src/common/logger/ (로거)
→ references/02-logger.md 참조
- `src/common/logger/sanitizer.ts`
- `src/common/logger/request-context.service.ts`
- `src/common/logger/request-context.middleware.ts`
- `src/common/logger/winston.factory.ts`
- `src/common/logger/winston-logger.service.ts`
- `src/common/logger/http-logging.interceptor.ts`
- `src/common/logger/logger.module.ts`

### src/database/ (Prisma + Redis)
→ references/04-database.md 참조
- `src/database/prisma.service.ts`
- `src/database/prisma.module.ts`
- `src/database/redis/redis.constants.ts`
- `src/database/redis/redis.module.ts`

### src/infrastructure/ (ChannelTalk + S3)
→ references/05-infrastructure.md 참조
- `src/infrastructure/channel-talk/channel-talk.adapter.ts`
- `src/infrastructure/channel-talk/channel-talk.module.ts`
- `src/infrastructure/s3/s3.adapter.ts`
- `src/infrastructure/s3/s3.module.ts`

### src/modules/auth/ (JWT 인증)
→ references/06-auth.md 참조
- `src/modules/auth/types/jwt-payload.type.ts`
- `src/modules/auth/types/role.type.ts`
- `src/modules/auth/constants/auth.constants.ts`
- `src/modules/auth/decorators/public.decorator.ts`
- `src/modules/auth/decorators/current-user.decorator.ts`
- `src/modules/auth/guards/jwt-auth.guard.ts`
- `src/modules/auth/strategies/jwt.strategy.ts`
- `src/modules/auth/utils/parse-ttl.util.ts`
- `src/modules/auth/dto/login.dto.ts`
- `src/modules/auth/auth.service.ts`
- `src/modules/auth/auth.controller.ts`
- `src/modules/auth/auth.module.ts`

### src/health/ (헬스체크)
→ references/07-health.md 참조
- `src/health/indicators/prisma-health.indicator.ts`
- `src/health/indicators/redis-health.indicator.ts`
- `src/health/health.controller.ts`
- `src/health/health.module.ts`

### src/main.ts / src/app.module.ts (진입점)
→ references/08-root.md 의 "main.ts", "app.module.ts" 참조

### prisma/schema.prisma
→ references/04-database.md 의 "schema.prisma" 참조 (빈 스키마)

### .env.example / docker-compose.yml
→ references/08-root.md 의 ".env.example", "docker-compose.yml" 참조

`.env.example`을 복사해 `.env`를 만들고 값을 채운다:
```bash
cp .env.example .env
```

## Step 4: 의존성 설치

```bash
pnpm install
pnpm prisma generate
```

## Step 5: 검증

```bash
pnpm tsc --noEmit
pnpm lint
```

타입 에러나 lint 에러가 있으면 반드시 수정 후 다음 단계 진행.

## Step 6: 서버 기동 확인

```bash
# .env 파일에 DATABASE_URL, JWT_SECRET, REDIS_HOST 등 필수 환경변수를 설정한 후
pnpm start:dev
# 정상 기동 시: "Application is running on: http://localhost:3000/api/v1"
```

---

## 새 feature 모듈 추가

세팅 완료 후 새 비즈니스 모듈을 추가할 때 디렉토리 구조:
```
src/modules/<feature-name>/
  controllers/
  services/
  repositories/    ← Prisma 쿼리 전용, Prisma 타입 반환
  dto/
  entities/        ← 응답 직렬화 모델 (BigInt→string, @Expose)
  mappers/         ← Prisma 타입 ↔ Entity 변환
  <feature-name>.module.ts
```

app.module.ts imports 배열에 새 모듈을 추가한다.
