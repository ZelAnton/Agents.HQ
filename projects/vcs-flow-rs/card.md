---
repo: vcs-flow-rs
type: card
kind: tui
language: Rust
status: active
publishes: [бинари команд (cargo install)]
depends-on: [ProcessKit-rs, vcs-toolkit-rs]
depended-on-by: []
pair: vcs-flow-dotnet
updated: 2026-06-09
---

## Назначение
Опинионированные консольные workflow для Git/jj/GitHub (TUI-инструменты вроде `commit`);
каждый — член Cargo-workspace, компонующий полезные последовательности VCS-операций (ratatui).

## Ответственность / границы
**Входит:** сценарии workflow + TUI.
**НЕ входит:** примитивы CLI → `vcs-toolkit-rs`; запуск → `processkit`.

## Публичный интерфейс / точки входа
Бинари `vcs-flow-commit` и др. Построен на facade `vcs-core`/`vcs-git`/`vcs-jj`/`vcs-github`
и launcher `processkit`.

## Сборка и тесты
```
cargo build
cargo run -p vcs-flow-commit
cargo test                # ignores: -- --ignored
cargo install --path crates/commit
```

## Связи и зависимости
Поверх `vcs-toolkit-rs` + `processkit`. Пара паритета — `vcs-flow-dotnet`.

## На что смотреть при кросс-репо изменениях
Зависит от crate-API `vcs-toolkit-rs` и `processkit`. Паритет — с `vcs-flow-dotnet`.

## Ссылки
- `../../../vcs-flow-rs/README.md`, `../../../vcs-flow-rs/AGENTS.md`
