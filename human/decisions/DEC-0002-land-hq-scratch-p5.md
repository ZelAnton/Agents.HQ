---
id: DEC-0002
type: decision
title: Приземлять ли изменение в .hq-scratch-p5 (tykrntvlnxnk)?
date: 2026-06-10
from: orchestrator/land.ps1
priority: P1
status: open
blocks: []
from-thread: null
land-repo: .hq-scratch-p5
land-workspace: hq-sample-intra-disjoint-b
land-dest: D:\GitHub\Personal\.hq-worktrees\.hq-scratch-p5\hq-sample-intra-disjoint-b
land-change: tykrntvlnxnk
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
# и переключи status: open → answered, затем: land.ps1 -Resume DEC-0002
---

## Контекст
Оркестратор исполнил задачу в изолированной workspace `hq-sample-intra-disjoint-b` (репо **.hq-scratch-p5**), прогнал гейт и
Верификатор. Авто-приземление НЕ выполнено: `risk=not-low`, `autonomy=auto-low`.

**Изменение** `tykrntvlnxnk`; build/test = `True`/`True`; объём = `12` строк.
Изменённые файлы:
- `src\alpha.rs`
- `src\beta.rs`

## Почему не приземлено автоматически
- Верификатор verdict=fail
- DoD не покрыт (dod_met=false)
- выход за scope: src/beta.rs

## Замечания Верификатора (fail)
- [high] src/beta.rs изменён за пределами объявленного scope_paths (src/alpha.rs). DoD третьим пунктом явно требует «менялся только src/alpha.rs» — это условие нарушено. Выход за объём является hard-stop для авто-приземления.

## Что делать
- Проверь diff: `cd "D:\GitHub\Personal\.hq-worktrees\.hq-scratch-p5\hq-sample-intra-disjoint-b"; jj diff`
- **A (land):** ответь `decision: A` + `status: answered` → затем `pwsh land.ps1 -Resume DEC-0002`
- **B (abandon):** ответь `decision: B` + `status: answered` → затем `pwsh land.ps1 -Resume DEC-0002`
