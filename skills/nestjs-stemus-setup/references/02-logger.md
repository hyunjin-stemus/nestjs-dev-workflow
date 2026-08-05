# 로거 파일 템플릿

## src/common/logger/sanitizer.ts

```typescript
const SENSITIVE_KEYS: readonly string[] = [
  'password', 'strpassword', 'struspwd', 'passwd',
  'token', 'accesstoken', 'refreshtoken',
  'apikey', 'secret', 'accesskeyid', 'secretaccesskey',
];

const REMOVE_HEADERS: readonly string[] = ['authorization', 'cookie', 'set-cookie'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_DEPTH = 5;
const MAX_ARRAY_LENGTH = 100;

export function maskEmail(email: string): string {
  const atIdx = email.indexOf('@');
  if (atIdx < 0) return email;
  const visible = email.slice(0, Math.min(2, atIdx));
  return `${visible}***${email.slice(atIdx)}`;
}

function isSensitiveKey(key: string): boolean {
  return SENSITIVE_KEYS.includes(key.toLowerCase());
}

function maskScalar(key: string, value: unknown): unknown {
  if (isSensitiveKey(key)) return '***';
  if (typeof value === 'string' && EMAIL_RE.test(value)) return maskEmail(value);
  return value;
}

export function maskObject<T>(input: T, depth = 0, seen = new Set<unknown>()): T {
  if (depth >= MAX_DEPTH) return '[Truncated]' as unknown as T;
  if (input === null || input === undefined) return input;
  if (typeof input === 'bigint') return input.toString() as unknown as T;
  if (typeof input !== 'object') return input;

  if (seen.has(input)) return '[Circular]' as unknown as T;
  seen.add(input);

  if (Array.isArray(input)) {
    const sliced = (input as unknown[]).slice(0, MAX_ARRAY_LENGTH);
    const result = sliced.map((item: unknown) => maskObject(item, depth + 1, seen));
    if (input.length > MAX_ARRAY_LENGTH) result.push(`…${input.length - MAX_ARRAY_LENGTH} more`);
    return result as unknown as T;
  }

  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input as Record<string, unknown>)) {
    const masked = maskScalar(key, value);
    if (masked !== value) {
      result[key] = masked;
    } else if (typeof value === 'object' && value !== null) {
      result[key] = maskObject(value, depth + 1, seen);
    } else {
      result[key] = value;
    }
  }
  return result as unknown as T;
}

export function maskHeaders(
  headers: Record<string, string | string[] | undefined>,
): Record<string, string | string[] | undefined> {
  const result: Record<string, string | string[] | undefined> = {};
  for (const [key, value] of Object.entries(headers)) {
    if (REMOVE_HEADERS.includes(key.toLowerCase())) continue;
    result[key] = value;
  }
  return result;
}
```

---

## src/common/logger/request-context.service.ts

```typescript
import { AsyncLocalStorage } from 'async_hooks';

interface RequestContext {
  requestId: string;
  memberId?: string;
}

const als = new AsyncLocalStorage<RequestContext>();

export class RequestContextService {
  static run<T>(context: RequestContext, fn: () => T): T {
    return als.run(context, fn);
  }

  static getRequestId(): string | undefined {
    return als.getStore()?.requestId;
  }

  static setMemberId(id: string): void {
    const store = als.getStore();
    if (store) store.memberId = id;
  }

  static getMemberId(): string | undefined {
    return als.getStore()?.memberId;
  }
}
```

---

## src/common/logger/request-context.middleware.ts

```typescript
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { RequestContextService } from './request-context.service';

@Injectable()
export class RequestContextMiddleware implements NestMiddleware {
  private static readonly UUID_RE = /^[0-9a-f-]{36}$/i;

  use(req: Request, res: Response, next: NextFunction): void {
    const inbound = req.headers['x-request-id'] as string | undefined;
    const requestId =
      inbound && RequestContextMiddleware.UUID_RE.test(inbound) ? inbound : uuidv4();
    res.setHeader('X-Request-Id', requestId);
    RequestContextService.run({ requestId }, () => next());
  }
}
```

---

## src/common/logger/winston.factory.ts

```typescript
import * as winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import type { LoggerConfig } from '@config/logger.config';

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

function toKstTimestamp(date: Date): string {
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  return kst.toISOString().replace('T', ' ').slice(0, 23) + ' KST';
}

const jsonFileFormat = winston.format.combine(winston.format.timestamp(), winston.format.json());

function consoleFormat(): winston.Logform.Format {
  return winston.format.combine(
    winston.format.colorize({ all: true }),
    winston.format.printf((info) => {
      const { level, message, context, requestId, memberId, trace, ...rest } = info;
      const ts = toKstTimestamp(new Date());
      const ctx = typeof context === 'string' ? `[${context}]` : '';
      const rid = typeof requestId === 'string' ? ` (req=${requestId.slice(0, 8)}…)` : '';
      const mid = typeof memberId === 'string' ? ` (mid=${memberId})` : '';
      const extra = Object.keys(rest).filter((k) => k !== 'timestamp' && k !== 'ms').length
        ? ` ${JSON.stringify(rest)}`
        : '';
      const traceStr = typeof trace === 'string' ? `\n${trace}` : '';
      return `${ts}  ${String(level).padEnd(5)}  ${ctx}${rid}${mid} ${String(message)}${extra}${traceStr}`;
    }),
  );
}

export function buildWinstonLogger(cfg: LoggerConfig): winston.Logger {
  const transports: winston.transport[] = [
    new DailyRotateFile({
      dirname: cfg.dir,
      filename: 'app-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      zippedArchive: true,
      maxSize: cfg.maxSize,
      maxFiles: cfg.maxFiles,
      format: jsonFileFormat,
    }),
    new DailyRotateFile({
      dirname: cfg.dir,
      filename: 'error-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      level: 'error',
      zippedArchive: true,
      maxSize: cfg.maxSize,
      maxFiles: cfg.maxFiles,
      format: jsonFileFormat,
    }),
    new winston.transports.Console({
      format: process.env.NODE_ENV === 'production' ? jsonFileFormat : consoleFormat(),
    }),
  ];

  return winston.createLogger({ level: cfg.level, transports });
}
```

---

## src/common/logger/winston-logger.service.ts

```typescript
import { Injectable, LoggerService } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as winston from 'winston';
import { buildWinstonLogger } from './winston.factory';
import { RequestContextService } from './request-context.service';
import { maskObject } from './sanitizer';
import type { LoggerConfig } from '@config/logger.config';

@Injectable()
export class WinstonLoggerService implements LoggerService {
  private readonly winston: winston.Logger;

  constructor(configService: ConfigService) {
    const cfg = configService.get<LoggerConfig>('logger')!;
    this.winston = buildWinstonLogger(cfg);
  }

  log(message: unknown, context?: string): void {
    this.winston.info(this.toMeta(message, context));
  }

  error(message: unknown, trace?: string, context?: string): void {
    this.winston.error(this.toMeta(message, context, trace ? { trace } : {}));
  }

  warn(message: unknown, context?: string): void {
    this.winston.warn(this.toMeta(message, context));
  }

  debug(message: unknown, context?: string): void {
    this.winston.debug(this.toMeta(message, context));
  }

  verbose(message: unknown, context?: string): void {
    this.winston.verbose(this.toMeta(message, context));
  }

  private toMeta(message: unknown, context?: string, extra: Record<string, unknown> = {}): object {
    const requestId = RequestContextService.getRequestId();
    const memberId = RequestContextService.getMemberId();
    const base: Record<string, unknown> = {};
    if (context !== undefined) base.context = context;
    if (requestId !== undefined) base.requestId = requestId;
    if (memberId !== undefined) base.memberId = memberId;

    if (typeof message === 'string') return { message, ...base, ...extra };
    if (typeof message === 'object' && message !== null) {
      const sanitized = maskObject(message as Record<string, unknown>);
      return { message: 'log', ...sanitized, ...base, ...extra };
    }
    return { message: String(message), ...base, ...extra };
  }
}
```

---

## src/common/logger/http-logging.interceptor.ts

```typescript
import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap, finalize } from 'rxjs/operators';
import { Request, Response } from 'express';
import { WinstonLoggerService } from './winston-logger.service';
import { RequestContextService } from './request-context.service';
import { maskObject, maskHeaders } from './sanitizer';
import type { JwtPayload } from '@modules/auth/types/jwt-payload.type';

const CONTEXT = 'HTTP';

@Injectable()
export class HttpLoggingInterceptor implements NestInterceptor {
  constructor(
    private readonly logger: WinstonLoggerService,
    private readonly logRequestBody = false,
  ) {}

  intercept(ctx: ExecutionContext, next: CallHandler): Observable<unknown> {
    const http = ctx.switchToHttp();
    const req = http.getRequest<Request & { user?: JwtPayload }>();
    const { method } = req;
    const route = req.route as { path?: string } | undefined;
    const routePath = (req.baseUrl ?? '') + (route?.path ?? req.path);

    const memberId = req.user?.sub;
    if (memberId) RequestContextService.setMemberId(memberId);
    const startTime = Date.now();

    this.logger.log(`→ ${method} ${routePath}`, CONTEXT);

    if (this.logRequestBody && req.body !== undefined) {
      this.logger.debug(
        {
          msg: 'request.body',
          body: maskObject(req.body as Record<string, unknown>),
          headers: maskHeaders(req.headers),
        },
        CONTEXT,
      );
    }

    let statusCode: number | undefined;

    return next.handle().pipe(
      tap({ next: () => { statusCode = http.getResponse<Response>().statusCode; } }),
      finalize(() => {
        const duration = Date.now() - startTime;
        if (statusCode !== undefined) {
          this.logger.log(`← ${method} ${routePath} ${statusCode} ${duration}ms`, CONTEXT);
        } else {
          this.logger.debug(`← ${method} ${routePath} [exception] ${duration}ms`, CONTEXT);
        }
      }),
    );
  }
}
```

---

## src/common/logger/logger.module.ts

```typescript
import { Global, Module } from '@nestjs/common';
import { WinstonLoggerService } from './winston-logger.service';

@Global()
@Module({
  providers: [WinstonLoggerService],
  exports: [WinstonLoggerService],
})
export class LoggerModule {}
```
