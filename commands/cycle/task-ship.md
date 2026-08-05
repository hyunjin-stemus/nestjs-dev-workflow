---
description: "task 배포 — 커밋 → PR → 리뷰 → 병합 → API.md → done"
---

# task 배포 — 커밋 → PR → 리뷰 → 병합 → API.md → done

커밋부터 PR 생성, 공식 code-review 스킬 리뷰, 병합, API.md 업데이트, task done 처리까지 진행한다.

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

4. **PR 생성** — base 브랜치를 `develop`으로 지정하고, 1단계에서 통과한 항목은 `[x]`로 체크한다:

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

5. **PR 리뷰** — 커스텀 서브에이전트 대신 **클로드 코드 공식 `code-review` 스킬**을 사용한다.
   - 현재 브랜치가 곧 PR 브랜치이므로, `Skill` 도구로 `code-review` 스킬을 호출해 `develop` 대비 diff를 리뷰한다:

     ```
     Skill({ skill: "code-review", args: "high --comment" })
     ```

   - effort는 기본 `high`를 사용한다(더 폭넓은 커버리지 필요 시 `xhigh`/`max`, 더 빠른 확인이면 `low`/`medium`).
   - `ultra`(멀티에이전트 클라우드 리뷰)는 **사용자가 명시적으로 요청한 경우에만** 사용한다 — 과금이 발생하고 직접 트리거할 수 없으므로 이 스킬 안에서 자동으로 선택하지 않는다.
   - `--comment` 플래그를 사용하면 스킬이 PR에 인라인 코멘트를 자동으로 게시한다 — 별도 `gh pr comment` 호출은 생략한다. `--comment` 없이 실행했다면 리뷰 결과 전문을 아래처럼 직접 게시한다:

     ```bash
     gh pr comment <PR번호> --body "$(cat <<'EOF'
     ## 🤖 PR Code Review

     <리뷰 결과 전문>
     EOF
     )"
     ```

   - 리뷰 완료 후 아래 형식으로 **모든 리뷰 항목을 빠짐없이 정리**해서 사용자에게 보여준다:

     **[PR 코드 리뷰 결과 전체 목록]**

     | # | 파일 | 심각도 | 내용 | 반영 시 고려사항 |
     |---|------|--------|------|-----------------|
     | 1 | path/to/file.ts | 🔴 critical | 지적 내용 | 반영 시 발생 가능한 문제점, side effect, 연쇄 영향, 추가 커밋 필요 여부 등 상세 기술 |
     | 2 | ... | 🟡 warning | ... | ... |

     심각도 기준: 🔴 critical (버그/보안/타입오류) / 🟡 warning (컨벤션/성능) / 🔵 suggestion (개선 제안)

   - 각 항목에 대해 **반영 시 발생 가능한 문제점과 고려사항**을 구체적으로 기술한다:
     - 다른 파일/모듈로의 연쇄 영향
     - 추가 테스트 수정이 필요한 경우
     - 기존 동작 변경 가능성
     - 병합 전 반드시 반영해야 하는 항목 여부

   - **컨펌 대기**: 위 목록을 보여준 후 반드시 사용자에게 "어떤 항목을 반영할까요?" 확인을 받는다.
     컨펌 없이 코드를 수정하지 않는다.

6. **PR 피드백 반영** — 컨펌된 항목만 수정한 후 추가 커밋을 생성하고 푸시한다. 컨펌되지 않은 항목은 건드리지 않는다.

7. **`docs/API.md` 업데이트** — 병합 요청 전, 이번 task에서 추가/변경된 엔드포인트를 기록한다.
   - API 변경이 없는 task(내부 리팩터링 등)는 "API 변경 없음"으로 명시.
   - 변경 사항을 커밋하고 푸시해 **PR에 포함시킨다** (병합 후 develop에 별도로 반영하지 않는다 — 리뷰 대상에서 누락되므로 반드시 병합 전에 PR 브랜치에 포함).

   ```bash
   git add docs/API.md
   git commit -m "docs: API.md 업데이트 (task <id>)"
   git push
   ```

8. **병합 컨펌 대기** — 사용자에게 병합 여부를 확인한다. **사용자 명시적 컨펌 없이 병합하지 않는다.**

9. **병합** (사용자 컨펌 후):

   ```bash
   gh pr merge <PR번호> --squash
   ```

10. **로컬 develop 브랜치 동기화**:

    ```bash
    git checkout develop
    git pull origin develop
    ```

11. **Notion API 명세서 동기화** (해당 시) — 프로젝트 `CLAUDE.md`에 Notion API 명세서 링크가
    기록돼 있는지 확인한다.
    - 링크가 있으면 `syncing-notion-api-docs` 스킬을 사용해서 이번 task로 `docs/API.md`에
      반영한 변경 사항(신규 엔드포인트, 필드 추가/제거, 제거된 엔드포인트 등)을 Notion에도
      동일하게 반영한다.
    - 링크가 없으면 이 단계는 건너뛴다.

12. **task done 처리**:

    ```bash
    task-master set-status --id=$ARGUMENTS --status=done
    ```

13. **task-master update-subtask** — 구현 중 발견한 중요 사항을 subtask에 기록한다.

    ```bash
    task-master update-subtask --id=$ARGUMENTS --prompt="구현 완료. 주요 결정 및 참고 사항: ..."
    ```

14. 사용자에게 안내: 다음 task를 진행하려면 `/task-start`를 호출하거나, 모든 task가 완료되면 `/cycle-finish`를 호출한다.
