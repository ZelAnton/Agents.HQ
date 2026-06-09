---
repo: agent-workspace
type: card
kind: cli
language: Rust
status: active
publishes: ["бинарь ws", "npm-субпакеты"]
depends-on: [ProcessKit-rs]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Быстрый workflow git/jujutsu worktree для AI-агентов (CLI `ws`): изолирует работу агента
по worktree, snap-режим, интеграция с вкладками терминала, авто-merge. Один статический бинарь
+ npm-субпакеты.

## Ответственность / границы
**Входит:** управление worktree-изоляцией агентов (git/jj), интеграция с терминалом.
**НЕ входит:** process management → `processkit`.

## Публичный интерфейс / точки входа
CLI `ws`. JSON-выход (см. docs/json-output.md).

## Сборка и тесты
```
cargo build
cargo test                       # tests/cmd_*.rs требуют предварительный cargo build
./scripts/build-npm.sh current   # или all
```

## Связи и зависимости
Использует `processkit` (ProcessKit-rs) как launcher. Потребляется системами оркестрации
для изоляции AI-агентов (концептуально связан с `tessmux`).

## На что смотреть при кросс-репо изменениях
Зависит от API `processkit`. Полезно держать в курсе изменений изоляции/worktree, если их
используют оркестраторы.

## Ссылки
- `../../../agent-workspace/README.md`, `../../../agent-workspace/AGENTS.md`, `../../../agent-workspace/docs/json-output.md`
