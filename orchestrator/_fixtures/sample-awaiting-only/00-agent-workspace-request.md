---
id: T-fixture-awaiting#00
thread: T-fixture-awaiting
seq: "00"
from: agent-workspace
reply-to: null
date: 2026-06-09
kind: question
fixture: true
---

## Контекст
`agent-workspace` хочет единообразный способ узнать версию доступного `jj` через обёртку `vcs-jj`,
вместо парсинга `jj --version` вручную.

## Суть (предложение)
Добавить в `vcs-jj` типизированный метод `version()` → структура `{major, minor, patch}`.

## Предлагаемое действие
Рассмотреть как предложение: нужно ли это в зоне `vcs-toolkit-rs` (crate `vcs-jj`), и если да — оценить объём.
*(Намеренно без поля `to:` — адресат определяется по `awaiting`.)*
