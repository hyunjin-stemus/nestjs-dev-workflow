# API Design Rules

## REST Principles
리소스 중심으로 설계한다.
예외:
memberId가 필요한 경우는 path-variable이 아니라 jwt에서 id값을 추출해서 사용한다.

Good:
```text
GET /api/v1/recordings/{id}
POST /api/v1/recordings
PATCH /api/v1/recordings/{id}
```

Bad:
```text
POST /getUser
POST /updateUserInfo
```

---

## HTTP Method Rules
- GET: 조회
- POST: 생성
- PUT: 전체 교체
- PATCH: 부분 수정
- DELETE: 삭제

조회 API에서 POST 사용 금지
특별한 검색 조건 제외

---

## Response Structure
모든 응답은 `ApiResponse<T>` 타입으로 래핑된다 (`src/common/types/api-response.type.ts`).
`ResponseInterceptor` 가 성공 응답을 자동 래핑하고,
`AllExceptionsFilter` 가 예외를 동일 구조의 실패 응답으로 매핑한다.

성공:
```json
{
  "success": true,
  "data": {},
  "message": "OK",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "path": "/api/v1/recordings"
}
```

실패:
```json
{
  "success": false,
  "data": null,
  "message": "Recording not found",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "path": "/api/v1/recordings/123"
}
```

예외는 반드시 `HttpException` 서브클래스로 throw한다. `AllExceptionsFilter` 가 자동으로 위 구조로 매핑.
```ts
throw new NotFoundException(`Recording ${id} not found`);
```

---

## Status Code
- 200 OK
- 201 Created
- 204 No Content
- 400 Bad Request
- 401 Unauthorized
- 403 Forbidden
- 404 Not Found
- 409 Conflict
- 422 Unprocessable Entity
- 500 Internal Server Error

---

## Validation
모든 request는 validation 필수

검증 대상:
- body
- query
- path param
- headers

예시:
- string length
- enum
- email format
- date format
- pagination range

---

## Pagination
목록 API는 반드시 pagination 지원

```json
{
  "items": [],
  "page": 1,
  "pageSize": 20,
  "totalCount": 100
}
```

cursor pagination 우선 고려

---

## Versioning
글로벌 prefix `api/v1` 사용. breaking change 발생 시 버전 명시.

예시:
```text
GET /api/v1/recordings
GET /api/v2/recordings   ← breaking change 시 버전 올림
```

---

## Swagger Documentation

모든 Controller / DTO는 반드시 Swagger 데코레이터를 포함한다.

### Controller 필수 데코레이터

```ts
@ApiTags('리소스명')                        // Controller 클래스
@ApiOperation({ summary: '한 줄 설명' })    // 각 핸들러
@ApiParam(...)                              // path variable 있을 때
@ApiQuery(...)                              // query param 있을 때
@ApiResponse({ status: 200, type: XxxDto }) // 성공 응답 — 반드시 type 명시
@ApiResponse({ status: 400, description: '...' })
@ApiResponse({ status: 404, description: '...' })
```

### DTO 필수 데코레이터

모든 request DTO / response 클래스의 프로퍼티에 `@ApiProperty()` 필수.

```ts
// Request DTO
export class CreateRecordingDto {
  @ApiProperty({ description: '파일 URL', example: 'https://...' })
  @IsUrl()
  fileUrl: string;

  @ApiProperty({ required: false, description: '메모' })
  @IsOptional()
  @IsString()
  note?: string;
}

// Response 클래스 (interface 대신 class 사용)
export class RecordingDto {
  @ApiProperty({ type: String, description: 'BigInt → string' })
  id: string;

  @ApiProperty()
  fileUrl: string;
}
```

### Response type 규칙

- 응답 타입이 interface라면 Swagger용 class를 별도 작성한다.
- `@ApiResponse`의 `type`에 반드시 해당 클래스를 지정한다.
- `ResponseInterceptor`가 `ApiResponse<T>`로 래핑하므로 data 내부 타입만 클래스로 작성하면 된다.

```ts
// Bad — type 없으면 Swagger에서 스키마 미표시
@ApiResponse({ status: 200, description: '성공' })

// Good
@ApiResponse({ status: 200, description: '성공', type: RecordingDto })
```

### 금지 사항

- `@ApiProperty()` 없이 DTO 프로퍼티 선언 금지
- `@ApiTags` 없는 Controller 금지
- `type` 없는 200 `@ApiResponse` 금지

---

## Naming Convention
snake_case 금지
camelCase 사용

예시:
```json
{
  "createdAt": "",
  "updatedAt": ""
}
```

---
