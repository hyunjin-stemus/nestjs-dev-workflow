# 루트 파일 템플릿

## src/main.ts

`<PROJECT_TITLE>`, `<PROJECT_VERSION>`을 프로젝트에 맞게 교체한다.

```typescript
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import cookieParser from 'cookie-parser';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { HttpLoggingInterceptor } from './common/logger/http-logging.interceptor';
import { WinstonLoggerService } from './common/logger/winston-logger.service';
import { ChannelTalkAdapter } from './infrastructure/channel-talk/channel-talk.adapter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  const logger = app.get(WinstonLoggerService);
  app.useLogger(logger);

  const configService = app.get(ConfigService);
  const port = configService.get<number>('app.port', 3000);

  app.setGlobalPrefix('api/v1');
  app.use(cookieParser());

  const isProduction = configService.get<string>('app.nodeEnv') === 'production';
  const corsOrigins = configService
    .get<string>('app.corsOrigins', '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

  if (isProduction && corsOrigins.length === 0) {
    throw new Error('CORS_ORIGINS 환경변수가 운영 환경에서 설정되지 않았습니다.');
  }

  app.enableCors({
    origin: corsOrigins.length > 0 ? corsOrigins : ['http://localhost:3001'],
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: {
        enableImplicitConversion: true,
      },
    }),
  );

  const logRequestBody = configService.get<boolean>('logger.logRequestBody', false);
  app.useGlobalInterceptors(
    new HttpLoggingInterceptor(logger, logRequestBody),
    new ResponseInterceptor(),
  );

  const httpAdapterHost = app.get(HttpAdapterHost);
  const channelTalk = app.get(ChannelTalkAdapter);
  app.useGlobalFilters(new AllExceptionsFilter(httpAdapterHost, logger, channelTalk));

  app.enableShutdownHooks();

  const swaggerConfig = new DocumentBuilder()
    .setTitle('<PROJECT_TITLE>')
    .setVersion('<PROJECT_VERSION>')
    .addBearerAuth()
    .addCookieAuth('refreshToken')
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);

  await app.listen(port);
  logger.log(`Application is running on: http://localhost:${port}/api/v1`, 'Bootstrap');
  logger.log(`Swagger UI: http://localhost:${port}/docs`, 'Bootstrap');
}

void bootstrap();
```

---

## src/app.module.ts

BullMQ 없이 기본 세팅. BullMQ 추가 방법은 `references/09-bullmq-optional.md` 참조.

```typescript
import { Module, NestModule, MiddlewareConsumer } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { ThrottlerStorageRedisService } from '@nest-lab/throttler-storage-redis';
import { HttpThrottlerGuard } from './common/guards/throttler.guard';
import { LoggerModule } from './common/logger/logger.module';
import { RequestContextMiddleware } from './common/logger/request-context.middleware';
import { PrismaModule } from './database/prisma.module';
import { RedisModule } from './database/redis/redis.module';
import { ChannelTalkModule } from './infrastructure/channel-talk/channel-talk.module';
import { S3Module } from './infrastructure/s3/s3.module';
import { AuthModule } from '@modules/auth/auth.module';
import { HealthModule } from './health/health.module';
import appConfig from './config/app.config';
import loggerConfig from './config/logger.config';
import jwtConfig from './config/jwt.config';
import redisConfig from './config/redis.config';
import throttlerConfig from './config/throttler.config';
import channelTalkConfig from './config/channel-talk.config';
import s3Config from './config/s3.config';
import type { ThrottlerConfig } from './config/throttler.config';
import type { RedisConfig } from './config/redis.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [
        appConfig,
        loggerConfig,
        jwtConfig,
        redisConfig,
        throttlerConfig,
        channelTalkConfig,
        s3Config,
      ],
      envFilePath: ['.env'],
      cache: true,
    }),
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const { ttl, limit } = config.getOrThrow<ThrottlerConfig>('throttler');
        const { host, port, password, db, tls } = config.getOrThrow<RedisConfig>('redis');
        return {
          throttlers: [{ ttl, limit }],
          storage: new ThrottlerStorageRedisService({
            host,
            port,
            password,
            db,
            tls: tls ? {} : undefined,
          }),
        };
      },
    }),
    LoggerModule,
    PrismaModule,
    RedisModule,
    AuthModule,
    ChannelTalkModule,
    S3Module,
    HealthModule,
    // TODO: 프로젝트 feature 모듈 추가
  ],
  providers: [{ provide: APP_GUARD, useClass: HttpThrottlerGuard }],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(RequestContextMiddleware).forRoutes('*path');
  }
}
```

---

## tsconfig.json

`@avatarshop-client` 항목은 아바타샵 전용이므로 제거한다.

```json
{
  "exclude": ["node_modules", "dist"],
  "compilerOptions": {
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "resolvePackageJsonExports": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "declaration": true,
    "removeComments": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "allowSyntheticDefaultImports": true,
    "target": "ES2023",
    "sourceMap": true,
    "outDir": "./dist",
    "baseUrl": "./",
    "incremental": true,
    "skipLibCheck": true,
    "strictNullChecks": true,
    "forceConsistentCasingInFileNames": true,
    "noImplicitAny": false,
    "strictBindCallApply": false,
    "noFallthroughCasesInSwitch": false,
    "paths": {
      "@common/*": ["src/common/*"],
      "@config/*": ["src/config/*"],
      "@modules/*": ["src/modules/*"],
      "@database/*": ["src/database/*"],
      "@infrastructure/*": ["src/infrastructure/*"]
    }
  }
}
```

---

## eslint.config.mjs

```javascript
// @ts-check
import eslint from '@eslint/js';
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['eslint.config.mjs'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  eslintPluginPrettierRecommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.jest,
      },
      sourceType: 'commonjs',
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-floating-promises': 'warn',
      '@typescript-eslint/no-unsafe-argument': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { varsIgnorePattern: '^_', argsIgnorePattern: '^_', destructuredArrayIgnorePattern: '^_' },
      ],
      'prettier/prettier': ['error', { endOfLine: 'auto' }],
    },
  },
  {
    // scripts/ 는 일회성 스크립트로, any 기반 코드가 많다.
    files: ['scripts/**/*.ts'],
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-return': 'off',
      '@typescript-eslint/no-unsafe-argument': 'off',
      '@typescript-eslint/no-redundant-type-constituents': 'off',
      '@typescript-eslint/unbound-method': 'off',
    },
  },
);
```

---

## .prettierrc

```json
{
  "singleQuote": true,
  "trailingComma": "all",
  "tabWidth": 2,
  "printWidth": 100
}
```

---

## package.json

버전은 최신 LTS 기준. `nest new` 실행 후 아래 값을 덮어쓴다.

```json
{
  "name": "<project-name>",
  "version": "0.0.1",
  "description": "",
  "author": "",
  "private": true,
  "license": "UNLICENSED",
  "packageManager": "pnpm@10.33.2",
  "engines": {
    "node": ">=22.0.0",
    "pnpm": ">=9.0.0"
  },
  "scripts": {
    "build": "nest build",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\" \"scripts/**/*.ts\"",
    "start": "nest start",
    "start:dev": "nest start --watch",
    "start:debug": "nest start --debug --watch",
    "start:prod": "node dist/main",
    "lint": "eslint \"{src,apps,libs,scripts,test}/**/*.ts\" --fix",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:debug": "node --inspect-brk -r tsconfig-paths/register -r ts-node/register node_modules/.bin/jest --runInBand",
    "test:e2e": "jest --config ./test/jest-e2e.json",
    "prisma:generate": "prisma generate",
    "prisma:migrate:dev": "prisma migrate dev",
    "prisma:studio": "prisma studio"
  },
  "dependencies": {
    "@aws-sdk/client-s3": "^3.1048.0",
    "@aws-sdk/s3-request-presigner": "^3.1048.0",
    "@nest-lab/throttler-storage-redis": "^1.2.0",
    "@nestjs/common": "^11.1.0",
    "@nestjs/config": "^4.0.4",
    "@nestjs/core": "^11.1.0",
    "@nestjs/jwt": "^11.0.2",
    "@nestjs/passport": "^11.0.5",
    "@nestjs/platform-express": "^11.1.0",
    "@nestjs/swagger": "^11.4.2",
    "@nestjs/terminus": "^11.1.1",
    "@nestjs/throttler": "^6.5.0",
    "@prisma/adapter-pg": "^7.0.0",
    "@prisma/client": "^7.0.0",
    "bcrypt": "^6.0.0",
    "class-transformer": "^0.5.1",
    "class-validator": "^0.15.1",
    "cookie-parser": "^1.4.7",
    "ioredis": "^5.10.1",
    "passport": "^0.7.0",
    "passport-jwt": "^4.0.1",
    "pg": "^8.20.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1",
    "uuid": "^14.0.0",
    "winston": "^3.19.0",
    "winston-daily-rotate-file": "^5.0.0"
  },
  "devDependencies": {
    "@eslint/eslintrc": "^3.2.0",
    "@eslint/js": "^9.18.0",
    "@nestjs/cli": "^11.0.0",
    "@nestjs/schematics": "^11.0.0",
    "@nestjs/testing": "^11.0.1",
    "@types/bcrypt": "^6.0.0",
    "@types/cookie-parser": "^1.4.10",
    "@types/express": "^5.0.0",
    "@types/jest": "^30.0.0",
    "@types/node": "^24.0.0",
    "@types/passport-jwt": "^4.0.1",
    "@types/pg": "^8.20.0",
    "@types/supertest": "^7.0.0",
    "@types/uuid": "^11.0.0",
    "dotenv": "^17.0.0",
    "eslint": "^9.18.0",
    "eslint-config-prettier": "^10.0.1",
    "eslint-plugin-prettier": "^5.2.2",
    "globals": "^17.0.0",
    "jest": "^30.0.0",
    "prettier": "^3.4.2",
    "prisma": "^7.0.0",
    "source-map-support": "^0.5.21",
    "supertest": "^7.0.0",
    "ts-jest": "^29.2.5",
    "ts-loader": "^9.5.2",
    "ts-node": "^10.9.2",
    "tsconfig-paths": "^4.2.0",
    "typescript": "^5.7.3",
    "typescript-eslint": "^8.20.0"
  },
  "jest": {
    "moduleFileExtensions": ["js", "json", "ts"],
    "rootDir": ".",
    "roots": ["<rootDir>/src", "<rootDir>/test/integration"],
    "testRegex": ".*\\.spec\\.ts$",
    "transform": {
      "^.+\\.(t|j)s$": "ts-jest"
    },
    "moduleNameMapper": {
      "^@common/(.*)$": "<rootDir>/src/common/$1",
      "^@config/(.*)$": "<rootDir>/src/config/$1",
      "^@modules/(.*)$": "<rootDir>/src/modules/$1",
      "^@database/(.*)$": "<rootDir>/src/database/$1",
      "^@infrastructure/(.*)$": "<rootDir>/src/infrastructure/$1"
    },
    "collectCoverageFrom": [
      "src/**/*.(t|j)s",
      "scripts/**/*.(t|j)s"
    ],
    "coverageDirectory": "./coverage",
    "testEnvironment": "node"
  }
}
```

---

## .env.example

```env
# ─── App ───────────────────────────────────────────────
PORT=3000
NODE_ENV=development
CORS_ORIGINS=http://localhost:3001,http://localhost:8080
COOKIE_DOMAIN=

# ─── Database ──────────────────────────────────────────
DATABASE_URL="postgresql://myuser:mypassword@localhost:5432/mydb_dev"

# ─── Redis ─────────────────────────────────────────────
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
REDIS_TLS=false

# ─── JWT ───────────────────────────────────────────────
JWT_SECRET=dev-secret-change-in-production
JWT_ACCESS_TTL=1h
JWT_REFRESH_TTL=14d

# ─── Throttler ─────────────────────────────────────────
THROTTLE_TTL=60000
THROTTLE_LIMIT=100
THROTTLE_LOGIN_LIMIT=5
THROTTLE_LOGIN_BLOCK_DURATION=70000

# ─── Logger ────────────────────────────────────────────
LOG_LEVEL=info
LOG_DIR=logs
LOG_MAX_FILES=14d
LOG_MAX_SIZE=50m
LOG_REQUEST_BODY=false

# ─── AWS S3 ────────────────────────────────────────────
AWS_REGION=ap-northeast-2
AWS_S3_BUCKET=my-bucket-dev
# AWS_S3_ENDPOINT=http://localhost:4566  # LocalStack
AWS_S3_PUBLIC_BASE_URL=
AWS_S3_PRESIGNED_URL_TTL_SEC=300
AWS_S3_UPLOAD_TIMEOUT_MS=10000
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY — ECS Task Role 자동 주입, 코드에 넣지 않는다
# 로컬 개발 시 ~/.aws/credentials 또는 AWS_PROFILE 환경변수 사용

# ─── Channel Talk ──────────────────────────────────────
CHANNEL_TALK_ACCESS_KEY=
CHANNEL_TALK_ACCESS_SECRET=
CHANNEL_TALK_GROUP_ID=
CHANNEL_TALK_NOTIFY_ENABLED=false
```

---

## docker-compose.yml

로컬 개발 환경용 PostgreSQL + Redis.

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: <project-name>-postgres
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb_dev
    ports:
      - '5432:5432'
    volumes:
      - postgres_data:/var/lib/postgresql/data

  postgres-shadow:
    image: postgres:16-alpine
    container_name: <project-name>-postgres-shadow
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb_shadow
    ports:
      - '5433:5432'

  redis:
    image: redis:7-alpine
    container_name: <project-name>-redis
    ports:
      - '6379:6379'

volumes:
  postgres_data:
```

`DATABASE_URL`은 `postgres` 컨테이너를, Prisma shadow DB는 `postgres-shadow`(포트 5433)를 사용한다.

Shadow DB URL 예시:
```
SHADOW_DATABASE_URL="postgresql://myuser:mypassword@localhost:5433/mydb_shadow"
```
