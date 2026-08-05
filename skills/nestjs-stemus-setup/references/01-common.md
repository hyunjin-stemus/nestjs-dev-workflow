# 공통 레이어 파일 템플릿

## src/common/types/api-response.type.ts

```typescript
export interface ApiResponse<T = unknown> {
  success: boolean;
  data: T | null;
  message: string;
}
```

---

## src/common/interceptors/response.interceptor.ts

```typescript
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  StreamableFile,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { ApiResponse } from '../types/api-response.type';

@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, ApiResponse<T> | StreamableFile> {
  intercept(
    _context: ExecutionContext,
    next: CallHandler<T>,
  ): Observable<ApiResponse<T> | StreamableFile> {
    return next.handle().pipe(
      map((data) => {
        if (data instanceof StreamableFile) return data;
        return { success: true, data, message: 'OK' };
      }),
    );
  }
}
```

---

## src/common/filters/alert-notifier.interface.ts

```typescript
export interface IAlertNotifier {
  sendAlert(message: string, context?: string): Promise<void>;
}
```

---

## src/common/filters/all-exceptions.filter.ts

```typescript
import { ExceptionFilter, Catch, ArgumentsHost, HttpException, HttpStatus } from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { ApiResponse } from '../types/api-response.type';
import { WinstonLoggerService } from '../logger/winston-logger.service';
import { RequestContextService } from '../logger/request-context.service';
import type { IAlertNotifier } from './alert-notifier.interface';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  constructor(
    private readonly httpAdapterHost: HttpAdapterHost,
    private readonly logger: WinstonLoggerService,
    private readonly alertNotifier?: IAlertNotifier,
  ) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const { httpAdapter } = this.httpAdapterHost;
    const ctx = host.switchToHttp();
    const request = ctx.getRequest<Record<string, unknown>>();

    const httpStatus =
      exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    const exceptionResponse = exception instanceof HttpException ? exception.getResponse() : null;

    const message =
      exceptionResponse && typeof exceptionResponse === 'object' && 'message' in exceptionResponse
        ? (exceptionResponse as { message: string | string[] }).message
        : exception instanceof HttpException
          ? exception.message
          : 'Internal server error';

    const normalizedMessage = Array.isArray(message) ? message.join(', ') : message;

    const customData = this.extractCustomData(exceptionResponse);

    const requestId = RequestContextService.getRequestId();
    const method = httpAdapter.getRequestMethod(request) as string;
    const path = httpAdapter.getRequestUrl(request) as string;
    const logMeta = { requestId, method, path, status: httpStatus, detail: normalizedMessage };

    if (httpStatus >= 500) {
      this.logger.error(
        logMeta,
        exception instanceof Error ? exception.stack : undefined,
        AllExceptionsFilter.name,
      );

      if (this.alertNotifier) {
        const exceptionType =
          exception instanceof Error
            ? exception.constructor.name || exception.name || 'Error'
            : 'UnknownError';
        const memberId = RequestContextService.getMemberId();
        const alertText = [
          `[5xx 오류] ${method} ${path}`,
          `상태: ${httpStatus}`,
          `예외: ${exceptionType}`,
          `메시지: ${normalizedMessage}`,
          `요청 ID: ${requestId}`,
          memberId ? `회원 ID: ${memberId}` : null,
        ]
          .filter(Boolean)
          .join('\n');
        this.alertNotifier.sendAlert(alertText, AllExceptionsFilter.name).catch((err: unknown) => {
          this.logger.error({ action: 'channelTalk.alertFailed', err }, AllExceptionsFilter.name);
        });
      }
    } else {
      this.logger.warn(logMeta, AllExceptionsFilter.name);
    }

    const responseBody: ApiResponse<unknown> = {
      success: false,
      data: customData,
      message: normalizedMessage,
    };

    const response = ctx.getResponse<{ headersSent?: boolean }>();
    if (response.headersSent) return;

    httpAdapter.reply(response, responseBody, httpStatus);
  }

  private extractCustomData(exceptionResponse: unknown): Record<string, unknown> | null {
    if (!exceptionResponse || typeof exceptionResponse !== 'object') return null;

    const STANDARD_KEYS = new Set(['message', 'statusCode', 'error', 'cause']);
    const rest = Object.fromEntries(
      Object.entries(exceptionResponse as Record<string, unknown>).filter(
        ([key]) => !STANDARD_KEYS.has(key),
      ),
    );

    return Object.keys(rest).length > 0 ? rest : null;
  }
}
```

---

## src/common/guards/throttler.guard.ts

```typescript
import { Injectable, ExecutionContext } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { ENFORCE_THROTTLE_KEY } from '../decorators/enforce-throttle.decorator';
import type { JwtPayload } from '@modules/auth/types/jwt-payload.type';

@Injectable()
export class HttpThrottlerGuard extends ThrottlerGuard {
  protected shouldSkip(context: ExecutionContext): Promise<boolean> {
    const enforce = this.reflector.get<boolean | undefined>(
      ENFORCE_THROTTLE_KEY,
      context.getHandler(),
    );
    if (enforce) return Promise.resolve(false);

    const req = context.switchToHttp().getRequest<{ method: string }>();
    return Promise.resolve(req.method === 'GET');
  }

  protected async getTracker(req: Record<string, unknown>): Promise<string> {
    const user = (req as { user?: JwtPayload }).user;
    if (user?.sub) return user.sub;

    const body = (req as { body?: { userId?: unknown } }).body;
    if (typeof body?.userId === 'string' && body.userId) return body.userId;

    return super.getTracker(req);
  }
}
```

---

## src/common/decorators/enforce-throttle.decorator.ts

```typescript
import { SetMetadata } from '@nestjs/common';

export const ENFORCE_THROTTLE_KEY = 'enforceThrottle';

/** GET 엔드포인트에 throttle을 명시적으로 적용할 때 사용한다. */
export const EnforceThrottle = () => SetMetadata(ENFORCE_THROTTLE_KEY, true);
```
