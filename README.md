# nestjs-dev-workflow

NestJS + Prisma 7 백엔드 개발 워크플로우 플러그인.

Task Master AI 기반 개발 사이클과 코드 리뷰 에이전트, 아키텍처 규칙을 한 번에 설치합니다.

---

## 포함 내용

### Agents (서브에이전트)

| 이름 | 역할 | 자동 트리거 |
|------|------|------------|
| `database-reviewer` | Prisma 쿼리, migration, 트랜잭션 리뷰 | `*.repository.ts` 수정, Prisma 쿼리 추가, migration 생성 |
| `pr-diff-reviewer` | PR diff 리뷰, 프로덕션 안전성 검토 | 소스 파일 수정, 기능 구현 완료 |
| `nestjs-backend-architect` | NestJS 아키텍처 설계, API 구현 | NestJS 관련 설계 질문 |
| `db-erd-architect` | ERD 설계, 인덱스 전략, 쿼리 최적화 | DB 스키마 설계 작업 |
| `prd-writer` | REQUIREMENT.md → PRD(.taskmaster/docs/prd.md) 변환 | Task Master 작업 시작 전 |
| `docker-container-manager` | Docker 컨테이너 생성/관리 | 컨테이너 관련 요청 |

### Skills (스킬)

| 이름 | 역할 | 트리거 |
|------|------|--------|
| `nestjs-stemus-setup` | `nest new` 이후 Stemus 표준 공통 레이어(응답 래퍼, 로거, Prisma+Redis, JWT Auth, Rate Limiting, ChannelTalk/S3 어댑터, Health Check 등) 전체 세팅 | 새 백엔드 레포 시작, "NestJS 프로젝트 세팅" 등 요청 시 |

### Slash Commands (슬래시 커맨드)

Task Master AI 기반 개발 사이클:

| 커맨드 | 역할 |
|--------|------|
| `/cycle:task-cycle [task-id]` | task 조회 → plan(애매하면 확인) → 구현 → 코드리뷰(자동 반영 + 애매한 것만 확인) → PR 생성 → PR 리뷰(자동 반영 + 애매한 것만 확인) → 병합 컨펌 → API.md → done |
| `/cycle:cycle-finish` | 사이클 완료 회고 문서화 |
| `/cycle:prd-from-requirement` | docs/REQUIREMENT.md → .taskmaster/docs/prd.md 변환 |

### Rules (코딩 규칙)

`rules/` 디렉토리에 포함된 파일 (CLAUDE.md에서 import하여 사용):

- `architecture.md` — 계층 구조, 책임 분리, 의존성 방향
- `api-design.md` — REST 설계, 응답 형식, Swagger
- `database.md` — ORM vs Raw SQL, 트랜잭션, N+1 방지, 인덱스
- `security.md` — 인증/인가, 입력 검증, SQL 인젝션 방지
- `testing.md` — TDD, 테스트 피라미드, 커버리지 기준

---

## 설치

### 1. 마켓플레이스로 등록 (GitHub 저장소 사용 시)

```bash
# GitHub에 push 후 마켓플레이스 등록
claude plugin marketplace add github:<username>/nestjs-dev-workflow --name nestjs-workflow

# 플러그인 설치
claude plugin install nestjs-dev-workflow@nestjs-workflow
```

### 2. 로컬 경로에서 설치

```bash
# 로컬 마켓플레이스 등록
claude plugin marketplace add /path/to/nestjs-dev-workflow --name nestjs-local

# 플러그인 설치
claude plugin install nestjs-dev-workflow@nestjs-local
```

---

## 설치 후 프로젝트 설정

### 1. CLAUDE.md에 rules import 추가

플러그인의 coding rules를 프로젝트 CLAUDE.md에서 import합니다:

```bash
# rules 파일을 프로젝트 .claude/rules/ 로 복사
mkdir -p .claude/rules
cp <plugin-path>/rules/*.md .claude/rules/
```

그리고 CLAUDE.md에 추가:

```markdown
@./.claude/rules/architecture.md
@./.claude/rules/api-design.md
@./.claude/rules/database.md
@./.claude/rules/security.md
@./.claude/rules/testing.md
```

### 2. 의존 플러그인 설치

cycle 커맨드가 사용하는 플러그인:

```bash
claude plugin install pr-review-toolkit@claude-plugins-official
```

Task Master AI (task-master CLI):

```bash
npm install -g task-master-ai
# 또는
claude plugin install task-master-ai@claude-plugins-official
```

### 3. CLAUDE.md에 에이전트 자동 호출 규칙 추가

```markdown
## 에이전트 사용 규칙

### database-reviewer 자동 호출
아래 중 하나라도 해당되면 database-reviewer 서브에이전트를 호출한다:
- *.repository.ts 파일 생성 또는 수정
- Prisma 쿼리 추가 또는 변경
- prisma/schema.prisma 수정
- migration 파일 생성
- 트랜잭션 로직 추가 또는 변경

### pr-diff-reviewer 자동 호출
아래 중 하나라도 해당되면 pr-diff-reviewer 서브에이전트를 호출한다:
- 소스 파일(*.ts, *.js, *.json, *.prisma) 생성 또는 수정 후
- 기능 구현 또는 버그 수정 완료 시 (commit 전)
- Controller, Service, Repository, Guard, Interceptor, Filter 추가 또는 수정 후
```

---

## 개발 사이클 워크플로우

```
요구사항 작성 (docs/REQUIREMENT.md)
    ↓
/cycle:prd-from-requirement
    ↓
task-master parse-prd → analyze-complexity → expand --all
    ↓ (각 task에 대해 반복)
/cycle:task-cycle [id]     → plan(애매하면 확인) + 구현 + 코드리뷰(자동 반영/애매한 것만 확인)
                             + PR 생성 + PR 리뷰(자동 반영/애매한 것만 확인) + 병합 컨펌 + done
    ↓ (모든 task 완료 후)
/cycle:cycle-finish        → 회고 문서화
```

---

## 빠른 설치 (curl)

claude plugin 명령어가 없어도 설치 가능:

```bash
curl -fsSL https://raw.githubusercontent.com/hyunjin-stemus/nestjs-dev-workflow/main/install.sh | bash
```

Claude Code를 재시작하면 적용됩니다.
