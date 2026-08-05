# Auth 모듈 파일 템플릿

> **중요**: 이 auth 모듈은 Prisma User 모델을 직접 사용하지 않는다.
> AuthService의 `findAndVerifyUser` 메서드를 프로젝트에 맞게 구현해야 한다.
> (DB 조회 + 비밀번호 검증 로직을 채워 넣는다)

---

## src/modules/auth/types/role.type.ts

```typescript
export type Role = 'user' | 'admin';
```

---

## src/modules/auth/types/jwt-payload.type.ts

```typescript
import type { Role } from './role.type';

export interface JwtPayload {
  sub: string;       // 사용자 ID (string)
  role: Role;
  jti: string;       // JWT ID (refresh 토큰 재사용 감지)
  /** 발급 시각(초). JWT 표준 클레임 — jwtService.sign()이 자동 주입한다. */
  iat?: number;
}
```

---

## src/modules/auth/constants/auth.constants.ts

```typescript
export const IS_PUBLIC_KEY = 'isPublic';
export const REDIS_SESSION_KEY_PREFIX = 'auth:session:user:';
export const REDIS_BLOCKLIST_JTI_PREFIX = 'auth:blocklist:jti:';
export const REDIS_INVALIDATE_AFTER_KEY_PREFIX = 'auth:invalidate-after:user:';

export const getRedisSessionKey = (userId: string): string =>
  `${REDIS_SESSION_KEY_PREFIX}${userId}`;

export const getRedisBlocklistJtiKey = (jti: string): string =>
  `${REDIS_BLOCKLIST_JTI_PREFIX}${jti}`;

/** logout/force-logout 시각(초)을 기록해 이 시각 이전 발급된 RT를 refresh에서 거부한다 */
export const getRedisInvalidateAfterKey = (userId: string): string =>
  `${REDIS_INVALIDATE_AFTER_KEY_PREFIX}${userId}`;
```

---

## src/modules/auth/decorators/public.decorator.ts

```typescript
import { SetMetadata } from '@nestjs/common';
import { IS_PUBLIC_KEY } from '../constants/auth.constants';

export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

---

## src/modules/auth/decorators/current-user.decorator.ts

```typescript
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import type { JwtPayload } from '../types/jwt-payload.type';

export function currentUserFactory(_data: unknown, ctx: ExecutionContext): JwtPayload | undefined {
  const request = ctx.switchToHttp().getRequest<Request & { user?: JwtPayload }>();
  return request.user;
}

export const CurrentUser = createParamDecorator(currentUserFactory);
```

---

## src/modules/auth/guards/jwt-auth.guard.ts

```typescript
import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '../constants/auth.constants';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}
```

---

## src/modules/auth/strategies/jwt.strategy.ts

```typescript
import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import type { Request } from 'express';
import type Redis from 'ioredis';
import { WinstonLoggerService } from '@common/logger/winston-logger.service';
import { REDIS_CLIENT } from '@database/redis/redis.constants';
import type { JwtConfig } from '@config/jwt.config';
import { getRedisSessionKey } from '../constants/auth.constants';
import type { JwtPayload } from '../types/jwt-payload.type';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(
    configService: ConfigService,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
    private readonly logger: WinstonLoggerService,
  ) {
    const { secret } = configService.getOrThrow<JwtConfig>('jwt');
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: secret,
      ignoreExpiration: false,
      passReqToCallback: true,
    });
  }

  async validate(req: Request, payload: JwtPayload): Promise<JwtPayload> {
    const rawToken = ExtractJwt.fromAuthHeaderAsBearerToken()(req);

    if (!rawToken) {
      this.logger.warn({ action: 'auth.jwt.validate.failed', reason: 'missing_token' }, JwtStrategy.name);
      throw new UnauthorizedException('Missing token');
    }

    const sessionKey = getRedisSessionKey(payload.sub);
    const storedToken = await this.redis.get(sessionKey);

    if (!storedToken) {
      this.logger.warn({ action: 'auth.jwt.validate.failed', userId: payload.sub, reason: 'session_not_found' }, JwtStrategy.name);
      throw new UnauthorizedException('Session not found');
    }

    if (rawToken !== storedToken) {
      this.logger.warn({ action: 'auth.jwt.validate.failed', userId: payload.sub, reason: 'token_mismatch' }, JwtStrategy.name);
      throw new UnauthorizedException('Session token mismatch');
    }

    return payload;
  }
}
```

---

## src/modules/auth/utils/parse-ttl.util.ts

```typescript
const TTL_PATTERN = /^(\d+)(ms|s|m|h|d|w)$/;

const UNIT_TO_SECONDS: Record<string, number> = {
  ms: 0.001,
  s: 1,
  m: 60,
  h: 3600,
  d: 86400,
  w: 604800,
};

export function parseTtlSeconds(ttl: string): number {
  const match = TTL_PATTERN.exec(ttl);
  if (!match) throw new Error(`Invalid TTL format: ${ttl}. Expected format: 1h, 30m, 14d, etc.`);
  const [, value, unit] = match;
  return Math.floor(Number(value) * UNIT_TO_SECONDS[unit]);
}

export function parseTtlMillis(ttl: string): number {
  return parseTtlSeconds(ttl) * 1000;
}
```

---

## src/modules/auth/dto/login.dto.ts

```typescript
import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsNotEmpty, MinLength } from 'class-validator';

export class LoginRequestDto {
  @ApiProperty({ description: '사용자 ID', example: 'user01' })
  @IsString()
  @IsNotEmpty()
  userId: string;

  @ApiProperty({ description: '비밀번호', example: 'password123' })
  @IsString()
  @IsNotEmpty()
  @MinLength(4)
  password: string;
}

export class LoginResponseDto {
  @ApiProperty({ description: 'JWT Access Token' })
  accessToken: string;
}
```

---

## src/modules/auth/auth.service.ts

```typescript
import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { JwtSignOptions } from '@nestjs/jwt';
import type Redis from 'ioredis';
import { randomUUID } from 'crypto';
import { WinstonLoggerService } from '@common/logger/winston-logger.service';
import { REDIS_CLIENT } from '@database/redis/redis.constants';
import type { JwtConfig } from '@config/jwt.config';
import {
  getRedisSessionKey,
  getRedisBlocklistJtiKey,
  getRedisInvalidateAfterKey,
} from './constants/auth.constants';
import { parseTtlMillis, parseTtlSeconds } from './utils/parse-ttl.util';
import type { JwtPayload } from './types/jwt-payload.type';
import type { LoginRequestDto } from './dto/login.dto';

interface LoginResult {
  accessToken: string;
  refreshToken: string;
  refreshTtlMs: number;
}

interface RefreshResult {
  accessToken: string;
  refreshToken: string;
  refreshTtlMs: number;
}

@Injectable()
export class AuthService {
  private readonly jwtConfig: JwtConfig;

  constructor(
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
    private readonly jwtService: JwtService,
    private readonly logger: WinstonLoggerService,
    configService: ConfigService,
  ) {
    this.jwtConfig = configService.getOrThrow<JwtConfig>('jwt');
  }

  async login(dto: LoginRequestDto): Promise<LoginResult> {
    this.logger.log({ action: 'login.start', userId: dto.userId }, AuthService.name);

    // TODO: 아래 메서드를 프로젝트의 실제 사용자 조회 + 비밀번호 검증 로직으로 구현한다.
    //       예시) DB에서 userId로 User를 조회하고 bcrypt.compare()로 비밀번호 검증
    const userId = await this.findAndVerifyUser(dto.userId, dto.password);

    const sessionKey = getRedisSessionKey(userId);
    const { accessTokenTtl, refreshTokenTtl } = this.jwtConfig;
    const payload: JwtPayload = { sub: userId, role: 'user', jti: randomUUID() };

    const accessToken = this.jwtService.sign(payload);
    const refreshToken = this.jwtService.sign(payload, {
      expiresIn: refreshTokenTtl as JwtSignOptions['expiresIn'],
    });
    const accessTtlSeconds = parseTtlSeconds(accessTokenTtl);

    const result = await this.redis.set(sessionKey, accessToken, 'EX', accessTtlSeconds, 'NX');
    if (result === null) {
      this.logger.warn(
        { action: 'login.failed', userId, reason: 'session_exists' },
        AuthService.name,
      );
      throw new ConflictException({ userId, message: '이미 로그인된 세션이 존재합니다' });
    }

    this.logger.log({ action: 'login.success', userId }, AuthService.name);
    return { accessToken, refreshToken, refreshTtlMs: parseTtlMillis(refreshTokenTtl) };
  }

  async refresh(refreshToken: string): Promise<RefreshResult> {
    this.logger.log({ action: 'refresh.start' }, AuthService.name);

    const { secret, accessTokenTtl, refreshTokenTtl } = this.jwtConfig;

    let payload: JwtPayload;
    try {
      payload = this.jwtService.verify<JwtPayload>(refreshToken, { secret });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    if (typeof payload.jti !== 'string' || !payload.jti) {
      throw new UnauthorizedException('Invalid token structure');
    }

    const refreshTtlSeconds = parseTtlSeconds(refreshTokenTtl);
    const blocklistKey = getRedisBlocklistJtiKey(payload.jti);

    const claimed = await this.redis.set(blocklistKey, 'used', 'EX', refreshTtlSeconds, 'NX');
    if (claimed === null) {
      await this.redis.del(getRedisSessionKey(payload.sub));
      this.logger.error(
        { action: 'auth.refresh.reuse.detected', userId: payload.sub, jti: payload.jti },
        undefined,
        AuthService.name,
      );
      throw new UnauthorizedException('Refresh token reuse detected');
    }

    const invalidateAfterRaw = await this.redis.get(getRedisInvalidateAfterKey(payload.sub));
    if (invalidateAfterRaw !== null) {
      const invalidateAfterSec = Number(invalidateAfterRaw);
      const iat = payload.iat ?? 0;
      if (isNaN(invalidateAfterSec) || iat < invalidateAfterSec) {
        await this.redis.del(getRedisSessionKey(payload.sub));
        throw new UnauthorizedException('Session has been invalidated');
      }
    }

    const newPayload: JwtPayload = { sub: payload.sub, role: payload.role, jti: randomUUID() };
    const newAccessToken = this.jwtService.sign(newPayload);
    const newRefreshToken = this.jwtService.sign(newPayload, {
      expiresIn: refreshTokenTtl as JwtSignOptions['expiresIn'],
    });

    await this.redis.set(
      getRedisSessionKey(payload.sub),
      newAccessToken,
      'EX',
      parseTtlSeconds(accessTokenTtl),
    );

    this.logger.log({ action: 'refresh.done', userId: payload.sub }, AuthService.name);
    return { accessToken: newAccessToken, refreshToken: newRefreshToken, refreshTtlMs: parseTtlMillis(refreshTokenTtl) };
  }

  async logout(userId: string): Promise<void> {
    const refreshTtlSeconds = parseTtlSeconds(this.jwtConfig.refreshTokenTtl);
    const nowEpochSec = Math.floor(Date.now() / 1000);
    await this.redis.set(
      getRedisInvalidateAfterKey(userId),
      String(nowEpochSec),
      'EX',
      refreshTtlSeconds,
    );
    await this.redis.del(getRedisSessionKey(userId));
    this.logger.log({ action: 'logout.done', userId }, AuthService.name);
  }

  async tryLogoutByRefreshToken(refreshToken: string): Promise<void> {
    try {
      const payload = this.jwtService.verify<JwtPayload>(refreshToken, {
        secret: this.jwtConfig.secret,
      });
      if (payload?.sub) await this.logout(payload.sub);
    } catch {
      // 만료/위조 토큰 — 세션이 없는 것으로 처리
    }
  }

  /**
   * TODO: 프로젝트의 사용자 조회 + 비밀번호 검증 로직으로 구현한다.
   *
   * 예시 구현 (Prisma + bcrypt):
   * ```typescript
   * import * as bcrypt from 'bcrypt';
   * private async findAndVerifyUser(userId: string, password: string): Promise<string> {
   *   const user = await this.prisma.user.findUnique({ where: { userId } });
   *   if (!user) throw new NotFoundException('User not found');
   *   const isValid = await bcrypt.compare(password, user.password);
   *   if (!isValid) throw new UnauthorizedException('Invalid credentials');
   *   return String(user.id);
   * }
   * ```
   */
  private async findAndVerifyUser(userId: string, _password: string): Promise<string> {
    // PLACEHOLDER: 실제 사용자 조회 및 비밀번호 검증 로직으로 교체할 것
    throw new NotFoundException(`findAndVerifyUser not implemented. userId=${userId}`);
  }
}
```

---

## src/modules/auth/auth.controller.ts

```typescript
import {
  Body, Controller, Get, HttpCode, HttpStatus,
  Post, Req, Res, UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiCookieAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { SkipThrottle, Throttle } from '@nestjs/throttler';
import type { CookieOptions, Request, Response } from 'express';
import { Public } from './decorators/public.decorator';
import { CurrentUser } from './decorators/current-user.decorator';
import { AuthService } from './auth.service';
import { LoginRequestDto, LoginResponseDto } from './dto/login.dto';
import type { JwtPayload } from './types/jwt-payload.type';

const LOGIN_THROTTLE_LIMIT = parseInt(process.env.THROTTLE_LOGIN_LIMIT ?? '5', 10) || 5;
const LOGIN_BLOCK_DURATION =
  parseInt(process.env.THROTTLE_LOGIN_BLOCK_DURATION ?? '70000', 10) || 70_000;

@SkipThrottle()
@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  private readonly isProduction: boolean;
  private readonly cookieDomain: string | undefined;

  constructor(
    private readonly authService: AuthService,
    configService: ConfigService,
  ) {
    this.isProduction = configService.get<string>('app.nodeEnv') === 'production';
    this.cookieDomain = configService.get<string | undefined>('app.cookieDomain');
  }

  private buildRefreshCookieOptions(): CookieOptions {
    return {
      httpOnly: true,
      sameSite: 'lax',
      secure: this.isProduction,
      domain: this.cookieDomain,
      path: '/api/v1/auth',
    };
  }

  @SkipThrottle({ default: false })
  @Throttle({
    default: { limit: LOGIN_THROTTLE_LIMIT, ttl: 60_000, blockDuration: LOGIN_BLOCK_DURATION },
  })
  @Post('login')
  @Public()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: '로그인' })
  @ApiResponse({ status: 200, type: LoginResponseDto })
  @ApiResponse({ status: 401, description: '인증 실패' })
  @ApiResponse({ status: 409, description: '이미 로그인된 세션 존재' })
  async login(
    @Body() dto: LoginRequestDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<LoginResponseDto> {
    const { accessToken, refreshToken, refreshTtlMs } = await this.authService.login(dto);
    res.cookie('refreshToken', refreshToken, {
      ...this.buildRefreshCookieOptions(),
      maxAge: refreshTtlMs,
    });
    return { accessToken };
  }

  @Post('refresh')
  @Public()
  @HttpCode(HttpStatus.OK)
  @ApiCookieAuth('refreshToken')
  @ApiOperation({ summary: 'Access Token 갱신' })
  @ApiResponse({ status: 200, type: LoginResponseDto })
  @ApiResponse({ status: 401, description: 'Refresh token 무효' })
  async refresh(
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ): Promise<LoginResponseDto> {
    const refreshToken = req.cookies?.refreshToken as string | undefined;
    if (!refreshToken) throw new UnauthorizedException('Refresh token not found');

    const { accessToken, refreshToken: newRefreshToken, refreshTtlMs } =
      await this.authService.refresh(refreshToken);

    res.cookie('refreshToken', newRefreshToken, {
      ...this.buildRefreshCookieOptions(),
      maxAge: refreshTtlMs,
    });
    return { accessToken };
  }

  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: '로그아웃' })
  @ApiResponse({ status: 204 })
  async logout(
    @CurrentUser() user: JwtPayload,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ): Promise<void> {
    const refreshToken = req.cookies?.refreshToken as string | undefined;
    if (refreshToken) {
      await this.authService.tryLogoutByRefreshToken(refreshToken);
    } else if (user?.sub) {
      await this.authService.logout(user.sub);
    }
    res.clearCookie('refreshToken', this.buildRefreshCookieOptions());
  }

  @Get('me')
  @ApiOperation({ summary: '현재 로그인 사용자 정보' })
  @ApiResponse({ status: 200 })
  me(@CurrentUser() user: JwtPayload) {
    return { userId: user.sub, role: user.role };
  }
}
```

---

## src/modules/auth/auth.module.ts

```typescript
import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import type { JwtSignOptions } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import type { JwtConfig } from '@config/jwt.config';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { JwtStrategy } from './strategies/jwt.strategy';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';

@Module({
  imports: [
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const jwt = config.getOrThrow<JwtConfig>('jwt');
        return {
          secret: jwt.secret,
          signOptions: { expiresIn: jwt.accessTokenTtl as JwtSignOptions['expiresIn'] },
        };
      },
    }),
  ],
  controllers: [AuthController],
  providers: [
    JwtStrategy,
    JwtAuthGuard,
    { provide: APP_GUARD, useExisting: JwtAuthGuard },
    AuthService,
  ],
  exports: [JwtAuthGuard, JwtModule, PassportModule],
})
export class AuthModule {}
```
