# Config 파일 템플릿

## src/config/app.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export default registerAs('app', () => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  nodeEnv: process.env.NODE_ENV ?? 'development',
  cookieDomain: process.env.COOKIE_DOMAIN || undefined,
  corsOrigins: process.env.CORS_ORIGINS ?? '',
}));
```

---

## src/config/jwt.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export interface JwtConfig {
  secret: string;
  accessTokenTtl: string;
  refreshTokenTtl: string;
}

// JWT_SECRET         - 토큰 서명 시크릿 (production 필수, 개발 기본: dev-secret)
// JWT_ACCESS_TTL     - access token TTL (기본: 1h)
// JWT_REFRESH_TTL    - refresh token TTL (기본: 14d)
export default registerAs<JwtConfig>('jwt', () => {
  const secret = process.env.JWT_SECRET || undefined;
  if (!secret && process.env.NODE_ENV === 'production') {
    throw new Error('JWT_SECRET must be set in production');
  }
  return {
    secret: secret ?? 'dev-secret',
    accessTokenTtl: process.env.JWT_ACCESS_TTL ?? '1h',
    refreshTokenTtl: process.env.JWT_REFRESH_TTL ?? '14d',
  };
});
```

---

## src/config/logger.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export interface LoggerConfig {
  level: string;
  dir: string;
  maxFiles: string;
  maxSize: string;
  logRequestBody: boolean;
}

// LOG_LEVEL       - error|warn|info|debug|verbose (기본: info)
// LOG_DIR         - 로그 파일 저장 경로 (기본: logs)
// LOG_MAX_FILES   - 보존 기간 (기본: 14d)
// LOG_MAX_SIZE    - 파일 크기 임계값 (기본: 50m)
// LOG_REQUEST_BODY - debug 레벨 요청 body 로깅 (기본: false)
export default registerAs(
  'logger',
  (): LoggerConfig => ({
    level: process.env.LOG_LEVEL ?? 'info',
    dir: process.env.LOG_DIR ?? 'logs',
    maxFiles: process.env.LOG_MAX_FILES ?? '14d',
    maxSize: process.env.LOG_MAX_SIZE ?? '50m',
    logRequestBody: process.env.LOG_REQUEST_BODY === 'true',
  }),
);
```

---

## src/config/redis.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export interface RedisConfig {
  host: string;
  port: number;
  password: string | undefined;
  db: number;
  tls: boolean;
}

// REDIS_HOST      - Redis 호스트 (기본: localhost)
// REDIS_PORT      - Redis 포트 (기본: 6379)
// REDIS_PASSWORD  - Redis 인증 비밀번호 (기본: undefined)
// REDIS_DB        - Redis DB 번호 (기본: 0)
// REDIS_TLS       - TLS 연결 활성화 (기본: false)
export default registerAs<RedisConfig>('redis', () => {
  const port = parseInt(process.env.REDIS_PORT ?? '6379', 10);
  if (Number.isNaN(port)) throw new Error('REDIS_PORT must be a valid integer');
  const db = parseInt(process.env.REDIS_DB ?? '0', 10);
  if (Number.isNaN(db)) throw new Error('REDIS_DB must be a valid integer');
  return {
    host: process.env.REDIS_HOST ?? 'localhost',
    port,
    password: process.env.REDIS_PASSWORD || undefined,
    db,
    tls: process.env.REDIS_TLS === 'true',
  };
});
```

---

## src/config/throttler.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export interface ThrottlerConfig {
  ttl: number;
  limit: number;
  loginLimit: number;
  loginBlockDuration: number;
}

// THROTTLE_TTL                  - rate limit 시간 윈도우(ms) (기본: 60000)
// THROTTLE_LIMIT                - 시간 윈도우 내 최대 요청 수 (기본: 100)
// THROTTLE_LOGIN_LIMIT          - 로그인 엔드포인트 전용 최대 요청 수 (기본: 5)
// THROTTLE_LOGIN_BLOCK_DURATION - 로그인 limit 초과 시 차단 구간(ms) (기본: 70000)
//   반드시 로그인 TTL(60000ms)보다 커야 한다. 그렇지 않으면 블록 만료 직후 누적 hits로 즉시 재차단.
export default registerAs<ThrottlerConfig>('throttler', () => {
  const ttl = parseInt(process.env.THROTTLE_TTL ?? '60000', 10);
  if (Number.isNaN(ttl)) throw new Error('THROTTLE_TTL must be a valid integer');
  const limit = parseInt(process.env.THROTTLE_LIMIT ?? '100', 10);
  if (Number.isNaN(limit)) throw new Error('THROTTLE_LIMIT must be a valid integer');
  const loginLimit = parseInt(process.env.THROTTLE_LOGIN_LIMIT ?? '5', 10);
  if (Number.isNaN(loginLimit)) throw new Error('THROTTLE_LOGIN_LIMIT must be a valid integer');
  const loginBlockDuration = parseInt(process.env.THROTTLE_LOGIN_BLOCK_DURATION ?? '70000', 10);
  if (Number.isNaN(loginBlockDuration)) {
    throw new Error('THROTTLE_LOGIN_BLOCK_DURATION must be a valid integer');
  }
  if (loginBlockDuration <= 60_000) {
    throw new Error('THROTTLE_LOGIN_BLOCK_DURATION must be greater than 60000 (login TTL)');
  }
  return { ttl, limit, loginLimit, loginBlockDuration };
});
```

---

## src/config/s3.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export interface S3Config {
  region: string;
  bucket: string;
  endpoint?: string;
  publicBaseUrl: string;
  presignedUrlDefaultTtlSec: number;
  uploadTimeoutMs: number;
}

const DEFAULT_PRESIGNED_URL_TTL_SEC = 300;
const DEFAULT_UPLOAD_TIMEOUT_MS = 10_000;

// AWS_REGION                    - AWS 리전 (production 필수)
// AWS_S3_BUCKET                 - S3 버킷 이름 (production 필수)
// AWS_S3_ENDPOINT               - 커스텀 endpoint URL (LocalStack/MinIO 등, 선택)
// AWS_S3_PUBLIC_BASE_URL        - CDN base URL (선택, 미지정 시 S3 직접 URL 폴백)
// AWS_S3_PRESIGNED_URL_TTL_SEC  - Presigned URL 유효 시간 초 (기본: 300)
// AWS_S3_UPLOAD_TIMEOUT_MS      - 업로드 요청 타임아웃 ms (기본: 10000)
// AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY — ECS Task Role 자동 주입, 코드에 넣지 않는다
export default registerAs<S3Config>('s3', () => {
  const isProd = process.env.NODE_ENV === 'production';
  const region = process.env.AWS_REGION ?? '';
  const bucket = process.env.AWS_S3_BUCKET ?? '';

  if (isProd && !region) throw new Error('AWS_REGION must be set in production');
  if (isProd && !bucket) throw new Error('AWS_S3_BUCKET must be set in production');

  const uploadTimeoutMs = process.env.AWS_S3_UPLOAD_TIMEOUT_MS
    ? parseInt(process.env.AWS_S3_UPLOAD_TIMEOUT_MS, 10)
    : DEFAULT_UPLOAD_TIMEOUT_MS;
  if (isNaN(uploadTimeoutMs)) throw new Error('AWS_S3_UPLOAD_TIMEOUT_MS must be a valid number');

  const presignedUrlDefaultTtlSec = process.env.AWS_S3_PRESIGNED_URL_TTL_SEC
    ? parseInt(process.env.AWS_S3_PRESIGNED_URL_TTL_SEC, 10)
    : DEFAULT_PRESIGNED_URL_TTL_SEC;
  if (isNaN(presignedUrlDefaultTtlSec)) {
    throw new Error('AWS_S3_PRESIGNED_URL_TTL_SEC must be a valid number');
  }

  const publicBaseUrl =
    process.env.AWS_S3_PUBLIC_BASE_URL ?? `https://${bucket}.s3.${region}.amazonaws.com`;

  return {
    region,
    bucket,
    endpoint: process.env.AWS_S3_ENDPOINT,
    publicBaseUrl,
    presignedUrlDefaultTtlSec,
    uploadTimeoutMs,
  };
});
```

---

## src/config/channel-talk.config.ts

```typescript
import { registerAs } from '@nestjs/config';

export interface ChannelTalkConfig {
  accessKey: string;
  accessSecret: string;
  groupId: string;
  notifyEnabled: boolean;
}

// CHANNEL_TALK_ACCESS_KEY      - 채널톡 Open API access key (notifyEnabled=true 시 필수)
// CHANNEL_TALK_ACCESS_SECRET   - 채널톡 Open API access secret (notifyEnabled=true 시 필수)
// CHANNEL_TALK_GROUP_ID        - 알림 대상 그룹 채팅방 ID (notifyEnabled=true 시 필수)
// CHANNEL_TALK_NOTIFY_ENABLED  - 알림 발송 여부 (기본: false)
export default registerAs<ChannelTalkConfig>('channelTalk', () => {
  const notifyEnabled = process.env.CHANNEL_TALK_NOTIFY_ENABLED === 'true';
  const isProd = process.env.NODE_ENV === 'production';
  const accessKey = process.env.CHANNEL_TALK_ACCESS_KEY ?? '';
  const accessSecret = process.env.CHANNEL_TALK_ACCESS_SECRET ?? '';
  const groupId = process.env.CHANNEL_TALK_GROUP_ID ?? '';

  if (isProd && notifyEnabled) {
    if (!accessKey) throw new Error('CHANNEL_TALK_ACCESS_KEY must be set in production');
    if (!accessSecret) throw new Error('CHANNEL_TALK_ACCESS_SECRET must be set in production');
    if (!groupId) throw new Error('CHANNEL_TALK_GROUP_ID must be set in production');
  }

  return { accessKey, accessSecret, groupId, notifyEnabled };
});
```
