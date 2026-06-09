---
id: TASK-0015
type: task
title: Оркестратор P4 — jj-интеграция + авто-land низкого риска
date: 2026-06-09
scope: orchestrator
status: queued
priority: P2
repos: [orchestrator]
depends-on: [TASK-0014]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P4)
---

## Цель
Автоматическое слияние и приземление безопасного; рисковое — человеку.

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P4) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§4 интеграция/конфликты, §7 риски).

## Объём / что делаем
- `Merge`-агент (`agents/hq-merge.md`) + инкрементальный `jj rebase` на интеграционную ревизию (конфликты не блокируют).
- `Verifier`-агент (`agents/hq-verify.md`, переиспользует `code-review`/`security-review`) как гейт против DoD.
- **Диск автономии**: `auto-low` → авто-land после зелёного гейта; иначе `DEC` человеку (через `vcs-toolkit`).

## DoD
- [ ] `risk()` определён исполнимо и **fail-closed** (`IMPLEMENTATION.md §11.1`); непустые конфликты ⇒ риск не-low (§11.2).
- [ ] Гейт «нет нерешённых jj-конфликтов» перед land; `build/tests == skipped` = НЕ-зелёный (§11.3).
- [ ] Кросс-репо: фундамент не auto-land-ится при незавершённых downstream-задачах потребителей (§11.4).
- [ ] Контур DEC замкнут: ответ человека возвращается в тред и возобновляет работу (§11.7).
- [ ] Волна низкого риска авто-приземлена (тесты+ревью); рисковая — корректно эскалирована в `DEC`; есть откат на провале гейта.

## Зависимости
Только-после P3.
