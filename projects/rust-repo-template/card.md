---
repo: rust-repo-template
type: card
kind: template
language: Rust
status: active
publishes: ["новые репо → crates.io"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых Rust-репозиториев. Source общих стандартов для jj-workflow-таблицы
и local-only-рецепта (`TEMPLATE-STANDARDS.md`).

## Ответственность / границы
**Входит:** generic Rust-репо (`Cargo.toml` центр.деп, `rust-toolchain.toml`, rustfmt, `cargo-deny`,
CI/release через crates.io, community-health, агентские доки). Имя crate выводится из `__ProjectName__`.
**НЕ входит:** наши локальные процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}`, release `workflow_dispatch` + App bypass. **Без CodeQL** (нет Rust-экстрактора);
`dtolnay/rust-toolchain@stable` не пиннится по SHA (git-ref — селектор toolchain).

## Сборка и тесты (в сгенерированном репо)
`cargo build` / `cargo test` / `cargo clippy` / `cargo deny check`.

## Связи
Создаётся из `meta-repo-template`. Паритет стандартов: cs/fs/kt.

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/rust-repo-template/`, `../../../.Templates/TEMPLATE-STANDARDS.md`
