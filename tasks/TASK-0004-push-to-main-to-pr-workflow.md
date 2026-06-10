---
id: TASK-0004
type: task
title: Миграция workflow push-to-main → PR во всех репо
date: 2026-06-09
scope: cross
status: queued
priority: P2
repos: [ProcessKit-rs, vcs-toolkit-rs, vcs-flow-rs, agent-workspace, ProcessGroup, ProcessKit, vcs-toolkit-dotNet, vcs-flow-dotnet, tessmux]
depends-on: []
parallel-safe-with: [TASK-0001, TASK-0002, TASK-0003]
assigned-to: null
origin: migration (root rewrite-push-to-main-to-pr-workflow.md)
session: null
risk: null
---

## Цель
Перевести репозитории с прямого пуша в `main` на PR-flow (branch protection + feature-бранчи),
как описано в исходном документе.

## Детальная спека
См. исходный документ: [`_src-push-to-main-to-pr-workflow.md`](_src-push-to-main-to-pr-workflow.md)
(мигрирован из корня `rewrite-push-to-main-to-pr-workflow.md`).

## Объём по репозиториям
Для каждого репо: настроить branch protection, релизный bypass, обновить инструкции workflow.
Часть шагов — **ручные** (включение branch protection, App/PAT bypass) → заводятся как `HT-####`
в `../human/tasks/` (см. `../knowledge/howto/release-token-bypass.md`).

## Последовательность шагов
1. По репо: создать `HT` на включение branch protection + bypass (ручное).
2. Обновить документацию workflow в каждом репо.
3. Проверить, что прямой пуш в `main` отклоняется, а релизный actor проходит.

## Критерии готовности (DoD)
- [ ] Во всех целевых репо `main` защищён; релиз проходит через bypass.

## Риски / зависимости
Независимо от processkit-rollout (`TASK-0001..0003`) → можно параллельно. Требует ручных действий человека.
