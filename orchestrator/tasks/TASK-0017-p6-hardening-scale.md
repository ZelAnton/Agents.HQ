---
id: TASK-0017
type: task
title: Оркестратор P6 — hardening, масштаб, наблюдаемость
date: 2026-06-09
scope: orchestrator
status: in-progress
priority: P2
repos: [orchestrator]
depends-on: [TASK-0016]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P6)
session: null
risk: null
---

## Цель
Надёжная безнадзорная работа.

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P6) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§2, §6, §8).

## Объём / что делаем
- `hq-conductor` как Rust-бинарь (догфуд **processkit** + **vcs-toolkit-rs** + **agent-workspace**):
  устойчивый планировщик, лизы/claim, восстановление после краша (состояние из `.hq`).
- **tessmux**-дашборд, метрики (пропускная способность, % конфликтов/эскалаций/зелёных тестов, % автономии),
  бюджеты, record/replay-тесты тиков (processkit), полные режимы автономии per-repo.

## DoD
- [ ] Несколько тиков подряд без присмотра с восстановлением после сбоя; дашборд и метрики; воспроизводимые прогоны в тестах.

## Результат (S1→S3, 2026-06-10)

### Артефакты
- `bin/hq-conductor/` — новый Rust-крейт (P6); `cargo build --release` + `cargo clippy` зелёные
- `src/main.rs` — clap-диспетчер 4 сабкоманд: `metrics`, `doctor`, `claim`, `journal`
- `src/state.rs` — резолв путей `.hq`, `find_hq_root()`, `LockInfo`, `is_pid_alive()`, `walk_files()`
- `src/metrics.rs` — **S1**: `hq-conductor metrics [--window N] [--json] [--out STATUS.md]`
- `src/doctor.rs` — **S2**: `hq-conductor doctor [--json]`, read-only, dogfuds `vcs-jj`
- `src/claim.rs` — **S3**: `hq-conductor claim write|check|release`; lease fail-closed
- `src/journal.rs` — **S3**: `hq-conductor journal record|mark-applied|list|replay`
- `schemas/claim.schema.json` — новая схема lease/claim
- `schemas/tick-log.schema.json` — добавлены опциональные `metrics` + `mutations[]`
- `STATUS.md` — стал генерируемым (шаблон из `STATUS.template.md`, секция `## Метрики`)

### Валидация
- **S1:** `hq-conductor metrics --window 20` → 8 прогонов, 100% green, 12.5% conflict, 0% авто-resolve (§11.2), 60% escalated, 40% auto-landed; `--out STATUS.md` перезаписал секцию корректно ✅
- **S2:** `doctor` читает `_runs/`, вызывает `jj.workspace_list()` (vcs-jj 0.5 read-only), опознаёт удалённые workspace как INFO, orphaned_workspaces=[] ✅
- **S3 claim:** write→check(exit 1)→release→check(exit 0) ✅; fail-closed: lease активен → exit 1; lease истёк + PID мёртв → "free" ✅
- **S3 journal:** record(3 мутации)→list→mark-applied(mut-001)→replay(показывает mut-002,003) ✅; атомарная запись tick.json ✅

### Что осталось (S4–S6)
- **S4** — устойчивый внешний цикл: Дирижёр гоняет реальный тик через processkit, журнал+lease
- **S5** — бюджеты токенов/итераций + processkit record/replay для воспроизводимых тестов
- **S6** — tessmux-дашборд + полные режимы автономии
- Полный порт triage/planner/exec/integrate/land в Rust (архив PS-скриптов)

## Зависимости
Только-после P5.
