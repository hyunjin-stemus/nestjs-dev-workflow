---
description: "task 사이클 — plan(애매하면 확인) → 구현 → 코드리뷰(자동 반영 + 애매한 것만 확인) → PR 생성 → PR 리뷰(자동 반영 + 애매한 것만 확인) → 병합 컨펌 → done"
---

# task 사이클 — plan → 구현 → 코드리뷰 → PR → 병합

task 선택부터 plan 수립, 구현, 코드리뷰, PR 생성, PR 코드리뷰, 병합, API.md 업데이트, task done 처리까지 하나의 흐름으로 진행한다.

## Arguments

`$ARGUMENTS` — task ID (예: `2.1`). 생략 시 `task-master next`로 자동 선택.

## 확인(컨펌) 기준 — "애매함"의 정의

이 사이클 전체에서 사용자에게 확인을 요청할지 여부는 **판단 성격**을 기준으로 정한다. 심각도(critical/warning/suggestion)는 확인 여부를 가르지 않는다.

- **자동으로 진행/반영한다** — 정답이 기계적으로 판별 가능한 것
  - 버그, 런타임 에러, 타입 오류
  - 기존 요구사항/PRD/API 명세와의 명백한 불일치
  - 코드 컨벤션 위반, 이 프로젝트 아키텍처 규칙(계층 분리, repository/service 책임 등) 위반
  - Prisma 타입이 repository 밖으로 노출되는 등 database.md/architecture.md 규칙 위반
  - 반영해도 영향 범위와 사이드이펙트가 명확히 파악되고 통제 가능한 수정
- **반드시 사용자에게 확인한다** — 판단에 재량이 개입되는 것
  - 요구사항에 명시되지 않아 추측(guess)이 필요한 시나리오/엣지케이스
  - 여러 구현 방식/설계 중 선택이 필요하고 트레이드오프가 있는 경우
  - 비즈니스 로직, 트랜잭션 경계, 동시성 정책 등 판단이 필요한 경우
  - 마이그레이션처럼 되돌리기 어렵거나 운영 데이터에 영향을 줄 수 있는 스키마 변경
  - 반영 시 사이드이펙트나 영향 범위가 불확실한 경우

plan 단계의 시나리오/로직 판단, 코드리뷰 단계의 리뷰 항목, PR 코드리뷰 단계의 리뷰 항목 모두 위 기준을 동일하게 적용한다. 애매한 항목이 하나도 없으면 해당 단계의 확인 절차 자체를 생략한다.

## Steps

### 1. task 준비

- `$ARGUMENTS`가 있으면: `task-master show $ARGUMENTS`
- 없으면: `task-master next` 후 조회된 ID로 `task-master show <id>`
- 상태 변경: `task-master set-status --id=<id> --status=in-progress`

### 2. 계획 수립

아래 항목을 포함한 구현 계획을 세운다.

- 구현 접근법
- 변경 대상 파일 목록 (계층 별로 — controller/service/repository/domain/mapper/dto)
- TDD 테스트 전략 (어떤 케이스를 먼저 작성할 것인지 — unit/integration 구분)
- 트랜잭션/동시성/마이그레이션이 필요한지 여부
- 예상 위험 요소
- 타입체크/린트 사전 확인 사항

계획 수립 중 위 "확인 기준"에 해당하는 애매한 지점(로직상 여러 해석이 가능하거나, 시나리오가 명세에 없어 추측이 필요한 경우, 스키마/마이그레이션 변경이 필요한 경우)이 있으면 목록으로 정리해 **AskUserQuestion으로 사용자에게 확인**한다. 확인받기 전에는 구현에 들어가지 않는다.

애매한 지점이 전혀 없으면 계획 승인 절차(`ExitPlanMode`) 없이 **바로 3단계(구현)로 진입**한다. 이 경우에도 계획 내용은 짧게 로그로 공유하되, 승인을 기다리지 않는다.

### 3. 브랜치 생성

develop 브랜치를 최신화한 뒤 feature 브랜치를 생성한다.

```bash
git checkout develop
git pull origin develop
git checkout -b feature/<task-id>-<slug>
```

예: `feature/2.1-add-attendance-mapper`

### 4. TDD: 테스트 먼저 작성

구현 전에 실패하는 테스트를 먼저 작성한다.

- `*.spec.ts` 또는 e2e 테스트 파일 생성/수정
- 테스트가 실제로 실패하는지 확인:
  ```bash
  pnpm test --testPathPattern="<관련파일>"
  ```
- 테스트가 실패하는 것을 확인한 후 구현 단계로 이동.

### 5. 구현

plan에 따라 코드를 작성한다. 계층 책임(controller/service/repository/domain/mapper)을 침범하지 않는다.

마이그레이션 파일을 생성한 경우, CLAUDE.md 규칙에 따라 `database-reviewer` 서브에이전트를 반드시 호출해 안전성을 검토한다.

### 6. 테스트 통과 확인

```bash
pnpm test --testPathPattern="<관련파일>"
```

실패 시 수정 후 재실행. 모든 테스트가 통과할 때까지 반복.

### 7. 타입체크

```bash
pnpm tsc --noEmit
```

에러 발생 시 **반드시 수정** 후 다음 단계로. 무시하고 진행 금지.

### 8. 린트

```bash
pnpm lint
```

에러 발생 시 **반드시 수정** 후 다음 단계로. 무시하고 진행 금지.

### 9. 코드 리뷰 — 자동 반영 + 애매한 것만 확인

커스텀 서브에이전트 대신 **클로드 코드 공식 `code-review` 스킬**을 사용한다. 아직 커밋 전 워킹 디렉터리 변경사항이므로, `Skill` 도구로 `code-review` 스킬을 호출해 현재 diff를 리뷰한다:

```
Skill({ skill: "code-review", args: "high" })
```

- effort는 기본 `high`를 사용한다(더 폭넓은 커버리지 필요 시 `xhigh`/`max`, 더 빠른 확인이면 `low`/`medium`).
- `ultra`(멀티에이전트 클라우드 리뷰)는 **사용자가 명시적으로 요청한 경우에만** 사용한다 — 과금이 발생하고 직접 트리거할 수 없으므로 이 커맨드 안에서 자동으로 선택하지 않는다.
- 이 단계는 커밋 전이라 PR이 아직 없으므로 `--comment`/`--fix` 플래그는 사용하지 않는다(PR 생성 후 리뷰는 11단계에서 별도로 수행).

리뷰 완료 후 아래 형식으로 **모든 리뷰 항목을 빠짐없이 정리**해서 사용자에게 보여준다. 이때 각 항목을 위 "확인 기준"에 따라 자동 반영 / 확인 필요로 분류해 표기한다.

**[코드 리뷰 결과]**

| # | 파일 | 심각도 | 내용 | 처리 | 반영 시 고려사항 |
|---|------|--------|------|------|-----------------|
| 1 | path/to/file.ts | 🔴 critical | 지적 내용 | 자동 반영 | 반영 시 발생 가능한 문제점, side effect, 타입 변경 연쇄 영향, 테스트 수정 필요 여부 등 |
| 2 | ... | 🟡 warning | ... | 확인 필요 | 여러 구현 방식 중 선택이 필요한 이유 |

심각도 기준: 🔴 critical (버그/보안/타입오류) / 🟡 warning (컨벤션/성능) / 🔵 suggestion (개선 제안) — 단, 자동 반영 여부는 심각도가 아니라 "확인 기준"의 판단 성격으로 정한다.

- **자동 반영 항목**은 별도 확인 없이 바로 수정한다.
- **확인 필요 항목만** 모아 사용자에게 질문(AskUserQuestion 등)하고, 승인된 것만 반영한다. 반려된 항목은 건드리지 않는다.
- 반영 완료 후 변경 사항을 짧게 요약해 공유한다.

### 10. 커밋 전 검증 → 커밋 → 푸시 → PR 생성

아래 순서대로 실행하고, 모두 통과한 경우에만 다음으로 진행한다. 실패 시 반드시 수정 후 재실행한다.

```bash
# 1) 린트
pnpm lint

# 2) 타입체크
pnpm tsc --noEmit

# 3) 관련 테스트 (unit + e2e)
pnpm test <관련 파일 경로>

# 4) 빌드
pnpm build

# 5) 서버 기동 확인 (10초 내 정상 기동 여부 확인 후 종료)
timeout 15 node dist/main && echo "✅ 기동 성공" || echo "❌ 기동 실패"
```

통과 후 커밋한다 (conventional commits 형식: `feat`, `fix`, `refactor`, `test`, `docs`).

```bash
git add <변경 파일들>
git commit -m "feat: <task 제목 요약> (task <id>)"
git push -u origin feature/<task-id>-<slug>
```

base 브랜치를 `develop`으로 지정해 PR을 생성한다. 위에서 통과한 항목은 `[x]`로 체크한다:

```bash
gh pr create \
  --base develop \
  --title "<task 제목>" \
  --body "$(cat <<'EOF'
## Summary
- <변경 내용 불릿 요약>

## Task
Task Master task ID: <id>

## Test plan
- [x] 린트 통과 (`pnpm lint`)
- [x] 타입체크 통과 (`pnpm tsc --noEmit`)
- [x] 관련 unit/e2e 테스트 통과
- [x] 빌드 성공 (`pnpm build`)
- [x] 서버 기동 확인 (`node dist/main`)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 11. PR 코드 리뷰 — 자동 반영 + 애매한 것만 확인

현재 브랜치가 곧 PR 브랜치이므로, `Skill` 도구로 `code-review` 스킬을 호출해 `develop` 대비 diff를 리뷰한다:

```
Skill({ skill: "code-review", args: "high --comment" })
```

- `--comment` 플래그를 사용하면 스킬이 PR에 인라인 코멘트를 자동으로 게시한다 — 별도 `gh pr comment` 호출은 생략한다. `--comment` 없이 실행했다면 리뷰 결과 전문을 `gh pr comment <PR번호>`로 직접 게시한다.
- `ultra`는 사용자가 명시적으로 요청한 경우에만 사용한다.

리뷰 완료 후 아래 형식으로 **모든 리뷰 항목을 빠짐없이 정리**해서 사용자에게 보여준다. 9단계와 동일하게 항목별로 자동 반영 / 확인 필요를 분류한다.

**[PR 코드 리뷰 결과]**

| # | 파일 | 심각도 | 내용 | 처리 | 반영 시 고려사항 |
|---|------|--------|------|------|-----------------|
| 1 | path/to/file.ts | 🔴 critical | 지적 내용 | 자동 반영 | 반영 시 발생 가능한 문제점, side effect, 연쇄 영향, 추가 커밋 필요 여부 등 |
| 2 | ... | 🟡 warning | ... | 확인 필요 | 판단이 필요한 이유 |

- **자동 반영 항목**은 바로 수정한다.
- **확인 필요 항목만** 사용자에게 질문하고, 승인된 것만 반영한다. 반려된 항목은 건드리지 않는다.
- 반영한 내용으로 추가 커밋을 생성하고 푸시한다.

### 12. `docs/API.md` 업데이트

병합 요청 전, 이번 task에서 추가/변경된 엔드포인트를 기록한다.

- API 변경이 없는 task(내부 리팩터링 등)는 "API 변경 없음"으로 명시.
- 변경 사항을 커밋하고 푸시해 **PR에 포함시킨다** (병합 후 develop에 별도로 반영하지 않는다 — 리뷰 대상에서 누락되므로 반드시 병합 전에 PR 브랜치에 포함).

```bash
git add docs/API.md
git commit -m "docs: API.md 업데이트 (task <id>)"
git push
```

### 13. 병합 컨펌 대기

사용자에게 병합 여부를 명시적으로 확인한다. **이 단계는 "확인 기준"과 무관하게 항상 사용자 컨펌을 거친다** — 병합은 공유 브랜치(develop)에 영향을 주고 되돌리기 어려운 행위이기 때문이다. 컨펌 없이 병합하지 않는다.

### 14. 병합 (사용자 컨펌 후)

```bash
gh pr merge <PR번호> --squash
```

### 15. 로컬 develop 브랜치 동기화

```bash
git checkout develop
git pull origin develop
```

### 16. Notion API 명세서 동기화 (해당 시)

프로젝트 `CLAUDE.md`에 Notion API 명세서 링크가 기록돼 있는지 확인한다.

- 링크가 있으면 `syncing-notion-api-docs` 스킬을 사용해서 이번 task로 `docs/API.md`에 반영한 변경 사항(신규 엔드포인트, 필드 추가/제거, 제거된 엔드포인트 등)을 Notion에도 동일하게 반영한다.
- 링크가 없으면 이 단계는 건너뛴다.
- **아이콘 규칙**: Notion "기능 명세서(BE)" 데이터베이스에서 신규 항목을 추가하거나 기존 항목의 아이콘이 비어 있으면, `기능 명세`(title) 아이콘은 **도메인(그룹)별로 서로 다른 색상**을 사용한다. 같은 도메인 내 모든 항목은 동일한 색상으로 통일하고, 다른 도메인과는 구분되는 색상을 사용한다 (예: `notification` 도메인 → 🔴, `auth` → 🟡, `payment` → 🔵 등 프로젝트 내 기존 도메인 색상 매핑을 우선 따르고, 없으면 새로 정해서 일관되게 적용). Notion 공개 API로는 기본 제공 도형 아이콘(`circle-dot` 등)을 안정적으로 설정할 수 없으므로(값은 저장되나 렌더링되지 않는 것이 확인됨) 색상 원형 이모지(🔴🟠🟡🟢🔵🟣 등)로 대체한다.

### 17. task done 처리

```bash
task-master set-status --id=$ARGUMENTS --status=done
```

### 18. task-master update-subtask

구현 중 발견한 중요 사항을 subtask에 기록한다.

```bash
task-master update-subtask --id=$ARGUMENTS --prompt="구현 완료. 주요 결정 및 참고 사항: ..."
```

### 19. 다음 안내

사용자에게 안내한다.

- 다음 task를 진행하려면 `/task-cycle` 또는 `/task-cycle <id>`를 호출한다.
- 모든 task가 완료되면 `/cycle-finish`를 호출한다.
