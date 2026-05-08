# Security Checklist

## Secrets
절대 아래 항목을 코드에 하드코딩하지 않는다.

- API key
- DB password
- JWT secret
- OAuth client secret
- private key

반드시 .env 사용

---

## Logging
절대 로그에 출력 금지

- password
- access token
- refresh token
- 주민번호 / 개인정보
- 카드번호
- 이메일 전체값

민감정보는 masking 처리

예시:
user@example.com
-> us***@example.com

---

## Authentication
모든 protected API는 인증 필수

검증 항목:
- token signature
- expiration
- issuer
- audience

---

## Authorization
인증과 권한은 반드시 분리

예시:
- 로그인 여부
- role
- ownership

---

## Input Validation
모든 외부 입력은 신뢰하지 않는다.

검증 대상:
- SQL injection
- XSS
- command injection
- path traversal

---

## SQL Rules
반드시 parameterized query 사용

Good:
```sql
SELECT * FROM users WHERE id = $1
```

Bad:
```sql
SELECT * FROM users WHERE id = '${id}'
```

---

## File Upload
검증 필수

- MIME type
- file extension
- max size
- malware scan
- executable 차단

---

## CORS
운영 환경에서 wildcard 금지

Bad:
```text
*
```

반드시 허용 origin 명시

---

## Dependency Security
신규 패키지 추가 시 아래 필수

- 유지보수 여부
- 최근 업데이트
- CVE 확인
- 다운로드 수
- license 확인

---

## Rate Limiting
필수 대상

- login
- signup
- otp
- password reset
- public API

---

## Audit
민감 작업은 반드시 audit log 남긴다

예시:
- role 변경
- 결제
- 삭제
- 관리자 액션