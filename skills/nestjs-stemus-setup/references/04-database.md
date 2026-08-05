# 데이터베이스 파일 템플릿

## prisma/schema.prisma

```prisma
// This is your Prisma schema file,
// learn more about it in the docs: https://pris.ly/d/prisma-schema

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
```

> 주의: 이 레포의 prisma/schema.prisma는 infra 레포의 `pnpm prisma:sync` 명령으로 동기화되는
> 읽기 전용 파일일 수 있다. 스키마 변경은 infra 레포에서만 수행한다.
> 독립 레포라면 직접 수정해도 된다.

---

## src/database/prisma.service.ts

```typescript
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import { Pool } from 'pg';

// BigInt JSON 직렬화 패치 (JSON.stringify 시 BigInt → string 변환)
(BigInt.prototype as unknown as { toJSON: () => string }).toJSON = function (this: bigint): string {
  return this.toString();
};

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly pool: Pool;

  constructor() {
    const pool = new Pool({ connectionString: process.env.DATABASE_URL });
    super({ adapter: new PrismaPg(pool) });
    this.pool = pool;
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
    await this.pool.end();
  }
}
```

---

## src/database/prisma.module.ts

```typescript
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

---

## src/database/redis/redis.constants.ts

```typescript
export const REDIS_CLIENT = 'REDIS_CLIENT';
```

---

## src/database/redis/redis.module.ts

```typescript
import {
  Global,
  Inject,
  InternalServerErrorException,
  Module,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import type { RedisConfig } from '@config/redis.config';
import { WinstonLoggerService } from '@common/logger/winston-logger.service';
import { REDIS_CLIENT } from './redis.constants';

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      useFactory: (config: ConfigService, logger: WinstonLoggerService): Redis => {
        const cfg = config.getOrThrow<RedisConfig>('redis');
        const client = new Redis({
          host: cfg.host,
          port: cfg.port,
          password: cfg.password,
          db: cfg.db,
          tls: cfg.tls ? {} : undefined,
          lazyConnect: true,
          connectTimeout: 5000,
          maxRetriesPerRequest: 1,
          enableOfflineQueue: false,
        });
        client.on('error', (err: Error) => {
          logger.error({ action: 'redis.error', error: err.message }, err.stack, RedisModule.name);
        });
        return client;
      },
      inject: [ConfigService, WinstonLoggerService],
    },
  ],
  exports: [REDIS_CLIENT],
})
export class RedisModule implements OnModuleInit, OnModuleDestroy {
  constructor(
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
    private readonly logger: WinstonLoggerService,
  ) {}

  async onModuleInit(): Promise<void> {
    const { host, port, db } = this.redis.options;
    try {
      await this.redis.connect();
      await this.redis.ping();
      this.logger.log({ action: 'redis.connect.done', host, port, db: db ?? 0 }, RedisModule.name);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(
        { action: 'redis.connect.failed', host, port, db: db ?? 0, error: message },
        err instanceof Error ? err.stack : undefined,
        RedisModule.name,
      );
      throw new InternalServerErrorException(
        `Redis connection failed: ${message}. Ensure Redis is running and REDIS_HOST/PORT are correct.`,
      );
    }
  }

  async onModuleDestroy(): Promise<void> {
    try {
      await Promise.race([
        this.redis.quit(),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Redis quit timeout')), 3000),
        ),
      ]);
      this.logger.log({ action: 'redis.disconnect.done' }, RedisModule.name);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.logger.error(
        { action: 'redis.disconnect.failed', error: message },
        err instanceof Error ? err.stack : undefined,
        RedisModule.name,
      );
      this.redis.disconnect();
    }
  }
}
```
