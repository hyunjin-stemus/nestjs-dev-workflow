# 인프라 어댑터 파일 템플릿

## src/infrastructure/channel-talk/channel-talk.adapter.ts

```typescript
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ChannelTalkConfig } from '@config/channel-talk.config';
import { WinstonLoggerService } from '@common/logger/winston-logger.service';
import type { IAlertNotifier } from '@common/filters/alert-notifier.interface';

const CHANNEL_TALK_API_URL = 'https://api.channel.io/open/v5/groups';

@Injectable()
export class ChannelTalkAdapter implements IAlertNotifier {
  private readonly config: ChannelTalkConfig;

  constructor(
    configService: ConfigService,
    private readonly logger: WinstonLoggerService,
  ) {
    this.config = configService.getOrThrow<ChannelTalkConfig>('channelTalk');
  }

  /**
   * 범용 알림 발송. notifyEnabled=false면 warn 로그만 남기고 스킵.
   * 발송 실패는 error 로그로 처리하며 호출 측으로 예외를 전파하지 않는다.
   */
  async sendAlert(message: string, context?: string): Promise<void> {
    if (!this.config.notifyEnabled) {
      this.logger.warn({ action: 'channelTalk.skipped', context }, ChannelTalkAdapter.name);
      return;
    }

    try {
      await this.sendWithRetry(message);
      this.logger.log({ action: 'channelTalk.sent', context }, ChannelTalkAdapter.name);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      this.logger.error(
        { action: 'channelTalk.sendFailed', context, message: errorMessage },
        ChannelTalkAdapter.name,
      );
    }
  }

  private async sendWithRetry(text: string, attempt = 0): Promise<void> {
    const url = `${CHANNEL_TALK_API_URL}/${this.config.groupId}/messages`;

    let res: Response;
    try {
      res = await globalThis.fetch(url, {
        method: 'POST',
        signal: AbortSignal.timeout(5_000),
        headers: {
          'Content-Type': 'application/json',
          'x-access-key': this.config.accessKey,
          'x-access-secret': this.config.accessSecret,
        },
        body: JSON.stringify({ plainText: text }),
      });
    } catch (fetchErr) {
      // 네트워크 오류(타임아웃, 연결 실패) — 서버 미수신 가능성이 있으므로 1회 재시도
      if (attempt === 0) return this.sendWithRetry(text, 1);
      throw fetchErr;
    }

    if (!res.ok) {
      // HTTP 오류 응답은 재시도하지 않음 (중복 발송 방지)
      throw new Error(`Channel Talk API error: ${res.status} ${res.statusText}`);
    }
  }
}
```

---

## src/infrastructure/channel-talk/channel-talk.module.ts

```typescript
import { Global, Module } from '@nestjs/common';
import { ChannelTalkAdapter } from './channel-talk.adapter';

@Global()
@Module({
  providers: [ChannelTalkAdapter],
  exports: [ChannelTalkAdapter],
})
export class ChannelTalkModule {}
```

---

## src/infrastructure/s3/s3.adapter.ts

```typescript
import {
  Injectable,
  InternalServerErrorException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { WinstonLoggerService } from '@common/logger/winston-logger.service';
import { S3Config } from '@config/s3.config';

const AUTH_ERROR_NAMES = new Set(['AccessDenied', 'InvalidAccessKeyId', 'SignatureDoesNotMatch']);
const TIMEOUT_ERROR_NAMES = new Set(['TimeoutError', 'AbortError']);

@Injectable()
export class S3Adapter {
  private readonly client: S3Client;
  private readonly config: S3Config;

  constructor(
    configService: ConfigService,
    private readonly logger: WinstonLoggerService,
  ) {
    this.config = configService.getOrThrow<S3Config>('s3');
    this.client = new S3Client({
      region: this.config.region || 'us-east-1',
      ...(this.config.endpoint ? { endpoint: this.config.endpoint, forcePathStyle: true } : {}),
    });
  }

  async uploadFile(fileKey: string, body: Buffer, mimeType: string, bucket?: string): Promise<void> {
    const targetBucket = bucket ?? this.config.bucket;
    this.logger.log(
      { action: 'uploadFile.start', bucket: targetBucket, fileKey, bytes: body.length },
      S3Adapter.name,
    );

    const command = new PutObjectCommand({
      Bucket: targetBucket,
      Key: fileKey,
      Body: body,
      ContentType: mimeType,
    });

    try {
      await this.client.send(command, { abortSignal: AbortSignal.timeout(this.config.uploadTimeoutMs) });
      this.logger.log({ action: 'uploadFile.done', bucket: targetBucket, fileKey }, S3Adapter.name);
    } catch (err) {
      this.mapS3Error(err, 'uploadFile.error');
    }
  }

  async deleteFile(fileKey: string, bucket?: string): Promise<void> {
    const targetBucket = bucket ?? this.config.bucket;
    this.logger.log({ action: 'deleteFile.start', bucket: targetBucket, fileKey }, S3Adapter.name);
    try {
      await this.client.send(new DeleteObjectCommand({ Bucket: targetBucket, Key: fileKey }));
      this.logger.log({ action: 'deleteFile.done', bucket: targetBucket, fileKey }, S3Adapter.name);
    } catch (err) {
      this.mapS3Error(err, 'deleteFile.error');
    }
  }

  async getPresignedUrl(fileKey: string, expiresInSec?: number): Promise<string> {
    const expiresIn = expiresInSec ?? this.config.presignedUrlDefaultTtlSec;
    this.logger.log(
      { action: 'getPresignedUrl.start', bucket: this.config.bucket, fileKey, expiresIn },
      S3Adapter.name,
    );
    try {
      const url = await getSignedUrl(
        this.client,
        new GetObjectCommand({ Bucket: this.config.bucket, Key: fileKey }),
        { expiresIn },
      );
      this.logger.log(
        { action: 'getPresignedUrl.done', bucket: this.config.bucket, fileKey },
        S3Adapter.name,
      );
      return url;
    } catch (err) {
      return this.mapS3Error(err, 'getPresignedUrl.error');
    }
  }

  private mapS3Error(err: unknown, action: string): never {
    const errorName = err instanceof Error ? err.name : 'UnknownError';
    const errorMessage = err instanceof Error ? err.message : String(err);
    const errorCode =
      err != null && typeof err === 'object' && 'Code' in err ? String(err.Code) : undefined;
    this.logger.error(
      { action, errorName, errorCode, errorMessage },
      err instanceof Error ? err.stack : undefined,
      S3Adapter.name,
    );
    if (errorName === 'NoSuchBucket') throw new InternalServerErrorException('S3 bucket not found');
    if (AUTH_ERROR_NAMES.has(errorName)) throw new UnauthorizedException('S3 access denied');
    if (TIMEOUT_ERROR_NAMES.has(errorName)) throw new ServiceUnavailableException('S3 request timeout');
    throw new ServiceUnavailableException('S3 request failed');
  }
}
```

---

## src/infrastructure/s3/s3.module.ts

```typescript
import { Global, Module } from '@nestjs/common';
import { S3Adapter } from './s3.adapter';

@Global()
@Module({
  providers: [S3Adapter],
  exports: [S3Adapter],
})
export class S3Module {}
```
