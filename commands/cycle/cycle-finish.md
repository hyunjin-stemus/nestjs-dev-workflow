---
description: "사이클 완료 — 회고 문서화 및 다음 사이클 준비"
---

# 사이클 완료 — 회고 문서화 및 다음 사이클 준비

모든 task가 done인지 확인하고 `docs/PROJECT_HISTORY.md`에 사이클 회고를 추가한다.

## Steps

1. **task 완료 여부 확인**:

   ```bash
   task-master list
   ```

   `done`이 아닌 task가 있으면 중단하고 사용자에게 알린다. 미완료 task가 있을 경우 이 커맨드를 계속 진행하지 않는다.

2. **사이클 정보 수집** — 다음 정보를 자동으로 수집한다.
   - `docs/REQUIREMENT.md` 내용 요약
   - task-master list 결과 (task 목록 + 제목)
   - 머지된 PR 목록 (`gh pr list --state merged --limit 20`)
   - 새로 추가된 모듈/파일 목록 (`git log --name-only --since="<사이클 시작일>"`)

3. **`docs/PROJECT_HISTORY.md`에 섹션 추가** — 파일 상단(`<!-- 사이클 추가 영역 -->` 주석 직후)에 새 섹션을 삽입한다.

   형식:
   ```markdown
   ## 사이클 N — YYYY-MM-DD

   ### 요구사항 요약
   <docs/REQUIREMENT.md 핵심 내용 2-3줄>

   ### 완료된 tasks
   | Task ID | 제목 | 비고 |
   |---|---|---|
   | 1.1 | ... | |

   ### 주요 기술 결정
   - <중요한 아키텍처/설계 결정 불릿>

   ### 산출 모듈/파일
   - `src/modules/<name>/` — 설명

   ### 머지된 PR
   - #<번호> — <제목>

   ### 다음 사이클 참고사항
   - <다음 작업자가 알아야 할 컨텍스트>
   ```

4. **Claude 메모리 저장** — 이번 사이클에서 새롭게 발견한 프로젝트 컨텍스트(기술 결정, 팀 컨벤션 등)를 메모리에 저장한다.

5. **사용자에게 보고** — 다음을 안내한다.
   - 완료된 사이클 요약
   - `docs/PROJECT_HISTORY.md` 업데이트 위치
   - 새 사이클을 시작하려면 `docs/REQUIREMENT.md`를 업데이트하고 `/prd-from-requirement`를 호출한다.
