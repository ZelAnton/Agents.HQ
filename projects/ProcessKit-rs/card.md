---
repo: ProcessKit-rs
type: card
kind: library
language: Rust
status: active
publishes: ["crates.io: processkit"]
depends-on: []
depended-on-by: [vcs-toolkit-rs, vcs-flow-rs, agent-workspace, processkit-py, processkit-go]
pair: ProcessKit
updated: 2026-06-09
---

## Назначение
Async (tokio) управление дочерними процессами для Rust с kernel-backed no-orphan гарантией
(Windows Job Object, Linux cgroup v2, POSIX process groups). Содержит `CliClient` + макрос
`cli_client!` для типизированных обёрток над CLI-инструментами. Ядро публикуется как `processkit`.
Вытеснил внутренний прототип `vcs-process`.

## Ответственность / границы
**Входит:** процессы/группы, runner, стриминг, supervision, limits, cancellation, record/replay, CliClient.
**НЕ входит:** конкретные VCS-обёртки → `vcs-toolkit-rs`; worktree-логика → `agent-workspace`.

## Публичный интерфейс / точки входа
`Command`/`ProcessRunner`/`ProcessResult`, `ProcessGroup` (kill-on-drop), `CliClient<R>`.
Фичи: `stats`, `process-control`, `limits`, `mock`, `tracing`, `cancellation`, `record`.

## Сборка и тесты
```
cargo build
cargo test
cargo test --all-features -- --ignored   # реальные subprocess/kill-on-drop тесты
cargo clippy --all-targets
cargo deny check advisories bans
```

## Связи и зависимости
Фундамент Rust-линии. Потребители: `vcs-toolkit-rs`, `vcs-flow-rs`, `agent-workspace`.
Будущие биндинги: `processkit-py`, `processkit-go` (пиннят версию crate).

## На что смотреть при кросс-репо изменениях
Изменение публичного API/фич затрагивает всех потребителей (`depends-on`). Пара паритета — `ProcessKit`.
Биндинги py/go следуют за версией осознанно.

## Ссылки
- `../../../ProcessKit-rs/README.md`, `../../../ProcessKit-rs/AGENTS.md`, `../../../ProcessKit-rs/ROADMAP.md`
- `../../../ProcessKit-rs/docs/` (commands, cookbook, pipelines, streaming, supervision, testing, …)
