---
description: "task 배포 — 커밋 → PR → 리뷰 → 병합 → API.md → done"
---

# task 배포 — 커밋 → PR → 리뷰 → 병합 → API.md → done

커밋부터 PR 생성, pr-diff-reviewer 리뷰, 병합, API.md 업데이트, task done 처리까지 진행한다.

## Arguments

`$ARGUMENTS` — task ID (예: `2.1`).

## Prerequisites

`/task-implement $ARGUMENTS`가 완료되어 사용자 컨펌이 받아진 상태여야 한다.

## Steps

1. **커밋 전 검증** — 아래 순서대로 실행하고, 모두 통과한 경우에만 커밋으로 진행한다. 실패 시 반드시 수정 후 재실행한다.

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

2. **커밋** — 변경된 파일을 스테이징하고 커밋한다.

   ```bash
   git add <변경 파일들>
   git commit -m "feat: <task 제목 요약> (task <id>)"
   ```

   커밋 메시지는 conventional commits 형식을 따른다 (`feat`, `fix`, `refactor`, `test`, `docs`).

3. **푸시**:

   ```bash
   git push -u origin feature/<task-id>-<slug>
   ```

4. **PR 생성** — 1단계에서 통과한 항목은 `[x]`로 체크한다:

   ```bash
   gh pr create \
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

5. **PR 리뷰** — `pr-diff-reviewer` 에이전트를 호출한다.
   - PR URL 또는 PR 번호를 에이전트에 전달한다.
   - 리뷰 결과를 사용자에게 요약해서 보여준다.
   - 리뷰 결과를 PR 댓글로도 게시한다:

     ```bash
     gh pr comment <PR번호> --body "$(cat <<'EOF'
     ## 🤖 PR Diff Review

     <리뷰 결과 전문>
     EOF
     )"
     ```

6. **PR 피드백 반영** — 리뷰 지적 사항을 수정한 후 추가 커밋을 생성하고 푸시한다.

7. **병합 컨펌 대기** — 사용자에게 병합 여부를 확인한다. **사용자 명시적 컨펌 없이 병합하지 않는다.**

8. **병합** (사용자 컨펌 후):

   ```bash
   gh pr merge <PR번호> --squash
   ```

9. **로컬 main 브랜치 동기화**:

   ```bash
   git checkout main
   git pull origin main
   ```

10. **`docs/API.md` 업데이트** — 이번 task에서 추가/변경된 엔드포인트를 기록한다.
    - API 변경이 없는 task(내부 리팩터링 등)는 "API 변경 없음"으로 명시.

11. **task done 처리**:

    ```bash
    task-master set-status --id=$ARGUMENTS --status=done
    ```

12. **task-master update-subtask** — 구현 중 발견한 중요 사항을 subtask에 기록한다.

    ```bash
    task-master update-subtask --id=$ARGUMENTS --prompt="구현 완료. 주요 결정 및 참고 사항: ..."
    ```

13. 사용자에게 안내: 다음 task를 진행하려면 `/task-start`를 호출하거나, 모든 task가 완료되면 `/cycle-finish`를 호출한다.
