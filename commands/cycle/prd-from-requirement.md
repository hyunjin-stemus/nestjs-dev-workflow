---
description: "PRD 생성 및 task 분할 — docs/REQUIREMENT.md → .taskmaster/docs/prd.md"
---

# PRD 생성 및 task 분할

`docs/REQUIREMENT.md`를 읽어 `.taskmaster/docs/prd.md`를 생성하고 task-master parse-prd를 실행한다.

## Steps

1. `docs/REQUIREMENT.md` 전체 내용을 읽는다.

2. 아래 구조로 `.taskmaster/docs/prd.md`를 생성한다.
   - `# Overview` — 프로젝트 목적과 배경
   - `# Goals` — 명확한 달성 목표 (불릿 리스트)
   - `# Technical Requirements` — 기술 스택, 제약 조건
   - `# Features` — 기능 단위로 섹션 분리 (task-master가 task로 분할할 단위)
   - `# Out of Scope` — 이번 사이클에서 제외할 내용
   - `# Success Metrics` — 완료 판단 기준

3. 생성된 `.taskmaster/docs/prd.md` 내용을 사용자에게 보여주고 **검토 및 승인**을 요청한다. 승인 없이 다음 단계로 진행하지 않는다.

4. 사용자가 승인하면 다음 명령을 순서대로 실행한다.

   ```bash
   task-master parse-prd .taskmaster/docs/prd.md
   ```

   parse-prd 완료 후 생성된 task 목록을 확인:

   ```bash
   task-master list
   ```

5. task가 생성되었으면 다음을 실행한다.

   ```bash
   task-master analyze-complexity --research
   task-master expand --all --research
   ```

6. **develop 브랜치 준비** — task 분할이 완료된 시점에 develop 브랜치를 생성하거나 체크아웃한다.

   ```bash
   git fetch origin
   # develop 브랜치가 이미 있으면 체크아웃, 없으면 main 기반으로 생성
   git checkout develop 2>/dev/null || git checkout -b develop main
   git push -u origin develop 2>/dev/null || true
   ```

   사용자에게 현재 브랜치가 `develop`임을 확인시킨다.

7. 완료 후 사용자에게 다음을 안내한다.
   - 생성된 task 수
   - 현재 브랜치: `develop` (모든 feature 브랜치는 이 브랜치 기반으로 생성됨)
   - 다음 작업 시작을 위해 `/task-cycle` 또는 `/task-cycle <id>` 호출 안내
