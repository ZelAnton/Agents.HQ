---
repo: vcs-toolkit-rs
type: card
kind: library
language: Rust
status: active
publishes: ["crates.io: vcs-git, vcs-jj, vcs-github, vcs-gitlab, vcs-gitea, vcs-core, vcs-forge, vcs-watch, vcs-mcp, vcs-diff, vcs-cli-support"]
depends-on: [ProcessKit-rs]
depended-on-by: [vcs-flow-rs]
pair: vcs-toolkit-dotNet
updated: 2026-06-09
---

## Назначение
Rust-тулкит для автоматизации Git, Jujutsu, GitHub, GitLab, Gitea через CLI (тонкие обёртки,
не реимплементация протоколов). 11 независимо версионируемых crate'ов: 5 CLI-обёрток + 2 facade
+ repo-watch + MCP-сервер + 2 foundation + testkit.

## Ответственность / границы
**Входит:** типизированные обёртки форджей/VCS, facades (`vcs-core`/`vcs-forge`), MCP-сервер.
**НЕ входит:** workflow-сценарии → `vcs-flow-rs`; запуск процессов → `processkit`.

## Публичный интерфейс / точки входа
Crate'ы `vcs-git`/`vcs-jj`/`vcs-github`/`vcs-gitlab`/`vcs-gitea`, facade `vcs-core`/`vcs-forge`,
`vcs-watch`, `vcs-mcp`, `vcs-diff`, `vcs-cli-support`.

## Сборка и тесты
```
cargo build
cargo test
cargo test -- --ignored
```

## Связи и зависимости
Поверх `processkit` (ProcessKit-rs). Потребитель — `vcs-flow-rs`. Пара паритета — `vcs-toolkit-dotNet`
(шире: .NET-версия покрывает Git/jj/GitHub, Rust добавляет GitLab/Gitea и MCP).

## На что смотреть при кросс-репо изменениях
Изменение crate-API затрагивает `vcs-flow-rs`. Crate'ы версионируются независимо — публикуй точечно.
Паритет — с `vcs-toolkit-dotNet`.

## Ссылки
- `../../../vcs-toolkit-rs/README.md`, `../../../vcs-toolkit-rs/AGENTS.md`, `../../../vcs-toolkit-rs/ROADMAP.md`
- `../../../vcs-toolkit-rs/docs/` (по crate'ам)
