---
id: T-fixture-awaiting
type: thread
title: (ФИКСТУРА) awaiting-only → vcs-toolkit-rs — без поля to:
status: open
scope: single:vcs-toolkit-rs
participants: [agent-workspace, vcs-toolkit-rs]
awaiting: [vcs-toolkit-rs]
opened: 2026-06-09
related: []
fixture: true
---

# (СИНТЕТИЧЕСКАЯ ФИКСТУРА — проверка M1: адресат берётся из `awaiting`, а не из `to:`)

В сообщениях НЕТ поля `to:` — Дирижёр обязан определить адресата `vcs-toolkit-rs` из `awaiting`.

## Дерево обсуждения
- 00 [agent-workspace] question/change-request — без `to:`, адресат только в `awaiting`
