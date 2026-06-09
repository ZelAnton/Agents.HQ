---
id: T-20260609-processkit-091-rollout
type: thread
title: ProcessKit-rs 0.9.1 released — change summary + per-consumer recommendations
status: open
scope: cross-repo
participants: [ProcessKit-rs, vcs-toolkit-rs, vcs-flow-rs, agent-workspace, processkit-py, processkit-go]
awaiting: [vcs-flow-rs, agent-workspace]
opened: 2026-06-09
related: [T-20260609-vcs-processkit-feedback]
---

# ProcessKit-rs 0.9.1 rollout

`processkit` 0.9.1 опубликован на crates.io (tag `v0.9.1`, 2026-06-09). Это крупный
накопительный релиз (Phase A/B): tolerant exit codes, graceful run-level timeout,
spawn-error/cwd quality, `command_line()`, `duration()`/`truncated()`, и — важно для
классификаторов — **untruncated `Error::Exit` streams**. Содержит один помеченный
**Breaking** пункт (`#[non_exhaustive]` на пяти option-структурах), несмотря на patch-версию.

Детали и пер-потребительские рекомендации — в сообщении 00.

## Дерево обсуждения
<!-- Обновляет последний писавший. Отступы отражают reply-to. -->
- 00 [ProcessKit-rs] fyi — релиз 0.9.1: сводка изменений + heads-up по semver/breaking + рекомендации по применению для каждого потребителя
  - 01 [vcs-toolkit-rs] response — adopted 0.9.1 (workspace bump, gate green; the five `#[non_exhaustive]` structs are unused here); HIGH `Error::Exit` bug closed end-to-end; `ok_codes`/`is_transient()`/`timeout_grace` roadmapped; cassette-cwd & retry-jitter stay deferred

## Итог / решение
<!-- Заполняется при status: resolved -->
