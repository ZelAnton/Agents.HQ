---
id: DEC-0003
type: decision
title: Приземлять ли изменение в .hq-scratch-p5 (pnzvvmvvoxpk)?
date: 2026-06-10
from: orchestrator/land.ps1
priority: P1
status: open
blocks: []
from-thread: null
land-repo: .hq-scratch-p5
land-workspace: hq-sample-intra-overlap-2
land-dest: D:\GitHub\Personal\.hq-worktrees\.hq-scratch-p5\hq-sample-intra-overlap-2
land-change: pnzvvmvvoxpk
land-remote: origin
land-risk: not-low
consumed-at: null
options:
  - id: A
    label: land — приземлить (advance main + push)
  - id: B
    label: abandon — откатить (forget workspace, без land)
recommended: null

# ↓↓↓ ЗАПОЛНЯЕТ ЧЕЛОВЕК. Авторитетный ответ — здесь. ↓↓↓
answer:
  decision: null        # A | B | other
  note: null
  by: anton
  date: null
# и переключи status: open → answered, затем: land.ps1 -Resume DEC-0003
---

## Контекст
Оркестратор исполнил задачу в изолированной workspace `hq-sample-intra-overlap-2` (репо **.hq-scratch-p5**), прогнал гейт и
Верификатор. Авто-приземление НЕ выполнено: `risk=not-low`, `autonomy=auto-low`.

**Изменение** `pnzvvmvvoxpk`; build/test = `True`/`True`; объём = `8` строк.
Изменённые файлы:
- `src\shared.rs`

## Почему не приземлено автоматически
- были разрешённые конфликты ⇒ не-low (§11.2)

## Замечания Верификатора (pass)
- (нет замечаний Верификатора)

## Что делать
- Проверь diff: `cd "D:\GitHub\Personal\.hq-worktrees\.hq-scratch-p5\hq-sample-intra-overlap-2"; jj diff`
- **A (land):** ответь `decision: A` + `status: answered` → затем `pwsh land.ps1 -Resume DEC-0003`
- **B (abandon):** ответь `decision: B` + `status: answered` → затем `pwsh land.ps1 -Resume DEC-0003`
