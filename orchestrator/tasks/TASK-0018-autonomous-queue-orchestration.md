---
id: TASK-0018
type: task
title: Автономный агентный процесс — три очереди, сессии, диспетчер, skills
date: 2026-06-10
scope: orchestrator
status: in-progress
priority: P1
repos: [orchestrator]
depends-on: [TASK-0017]
parallel-safe-with: []
assigned-to: null
origin: human/conversation-2026-06-10
---

## Цель

Замкнуть петлю «idea → plan → impl → review → done» как управляемый, наблюдаемый, crash-safe
автономный процесс. Сильная модель (Opus) планирует и ревьюит; дешёвая (Sonnet/Haiku) реализует
малые подготовленные задачи. Все переходы журналируются, у каждой сессии — структурный след,
человек сохраняет контроль через kill-switch и обязательный human-approval для рисковых решений.

**Принцип: расширяем существующую модель, не плодим параллельную.**

## Объём

### orchestrator

**M1 — State machine + схемы + intake + каркас сессий (без живых агентов)**
- Расширить state machine: добавить статусы `intake`, `in-review`, `fix-needed`, `rejected`;
  поля задачи: `created-by`, `risk`, `fix-attempt`, `session`, `blocked-reason`, `review`.
- `schemas/session.schema.json` (новый); расширить `_templates/task.md`.
- `hq-conductor session <new|heartbeat|end|list|gc>` (новый Rust-модуль `src/session.rs`).
- Skill `/add-task` + `bin/add-task.ps1`.
- Обновить `STATE.md`/`IMPLEMENTATION.md` (state machine).

**M2 — Детерминированный тик-диспетчер (mock-воркеры)**
- `src/dispatch.rs` + `src/tick.rs` в `hq-conductor`; `--mode mock`.
- Сквозной mock: add-task → tick(plan) → ready → tick(exec) → in-review → tick(review) → done.
- Crash-safety через journal replay (уже в S3).

**M3 — Живые агенты (auto-low) на scratch**
- Exec → Sonnet (`exec-one.ps1`); review → Opus (`hq-verify`); plan → Opus (`hq-planner`).
- Fix loop (review fail → fix-needed → re-exec, ограничен N).
- Land через `land.ps1`; DEC для рискового.

**M4 — Supervisor + observability**
- `/hq-tick`, `/hq-status`, `/hq-pause`, `/hq-resume`; `automation.json`.
- `/loop /hq-tick` для автономного режима.
- Секция сессий в `STATUS.md`.

## DoD

- [ ] M1: `cargo build/clippy` зелёные; `/add-task` создаёт intake; `session` round-trip; doctor видит stale.
- [ ] M2: mock-сценарий add→tick×3→done; crash→replay доводит; нет двойного claim.
- [ ] M3: низкорисковая задача до `done` без присмотра на scratch; рисковая → DEC; N-fix → escalate.
- [ ] M4: `/loop /hq-tick` ≥3 тика без присмотра; pause останавливает новые спавны; status актуален.

## Риски / зависимости

- Зависит от S1–S3 TASK-0017 (завершены 2026-06-10).
- `hq-conductor tick` — детерминированный код, не LLM; дешёвый агент — только исполнитель.
- Provider-адаптеры (Codex/Copilot/Qwen) — вне scope; Claude-only на старте.
- Tray-app супервизора — будущее (ROADMAP.md), сейчас `/loop`.
