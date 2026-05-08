---
description: "task 구현 — TDD → 코드 → 타입체크 → 린트 → 코드리뷰"
---

# task 구현 — TDD → 코드 → 타입체크 → 린트 → 코드리뷰

브랜치 생성부터 코드 리뷰 피드백 반영 후 사용자 컨펌까지 진행한다.

## Arguments

`$ARGUMENTS` — task ID (예: `2.1`).

## Prerequisites

`/task-start $ARGUMENTS`가 완료되어 plan 컨펌이 받아진 상태여야 한다.

## Steps

1. **브랜치 생성** — task ID와 제목을 기반으로 kebab-case slug 생성.

   ```bash
   git checkout -b feature/<task-id>-<slug>
   ```

   예: `feature/2.1-add-attendance-mapper`

2. **TDD: 테스트 먼저 작성** — 구현 전에 실패하는 테스트를 먼저 작성한다.
   - `*.spec.ts` 또는 e2e 테스트 파일 생성/수정
   - 테스트가 실제로 실패하는지 확인:
     ```bash
     pnpm test --testPathPattern="<관련파일>"
     ```
   - 테스트가 실패하는 것을 확인한 후 구현 단계로 이동.

3. **구현** — plan에 따라 코드를 작성한다.

4. **테스트 통과 확인**:
   ```bash
   pnpm test --testPathPattern="<관련파일>"
   ```
   실패 시 수정 후 재실행. 모든 테스트가 통과할 때까지 반복.

5. **타입체크**:
   ```bash
   pnpm tsc --noEmit
   ```
   에러 발생 시 **반드시 수정** 후 다음 단계로. 무시하고 진행 금지.

6. **린트**:
   ```bash
   pnpm lint
   ```
   에러 발생 시 **반드시 수정** 후 다음 단계로. 무시하고 진행 금지.

7. **코드 리뷰** — `pr-review-toolkit:code-reviewer` 에이전트를 호출한다.
   - 에이전트에 변경된 파일 목록과 task 컨텍스트를 전달한다.
   - 리뷰 결과를 사용자에게 요약해서 보여준다.

8. **피드백 반영** — 리뷰 지적 사항을 수정한다.

9. **사용자 컨펌 대기** — 수정 내용을 요약하고 커밋 진행 여부를 묻는다. 사용자 명시적 확인 없이 커밋하지 않는다.

10. 컨펌 후 사용자에게 안내: PR 생성과 병합을 위해 `/task-ship <id>`를 호출한다.
