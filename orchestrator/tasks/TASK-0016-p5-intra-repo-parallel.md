---
id: TASK-0016
type: task
title: Оркестратор P5 — параллель внутри одного репозитория
date: 2026-06-09
scope: orchestrator
status: done
priority: P2
repos: [orchestrator]
depends-on: [TASK-0015]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P5)
---

## Цель
Самое сложное: параллельные подзадачи в одном репо без «конфликтных штормов».

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P5) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§5, §4).

## Объём / что делаем
- `Planner` объявляет `scope_paths`; метит `parallel-safe` только при непересечении (+ нет общего публичного API); сомнение → только-после.
- Параллельные ws на одном репо; интеграция rebase по одной; `Merge` чинит jj-конфликты; тесты после каждой.
- Стресс-тест: пересекающиеся подзадачи сериализуются, непересекающиеся — сливаются.

## DoD
- [x] Общие/моноширинные файлы (список в `card.md`) авто-сериализуют задачу; `scope_paths` файловой гранулярности; `restructures` ⇒ отдельная волна (`IMPLEMENTATION.md §11.6`).
- [x] Авторитет parallel-safe — Дирижёр (из `scope_paths` + общие файлы); `parallel_safe_with` planner-а — только подсказка.
- [x] 2 непересекающиеся подзадачи одного репо слиты параллельно начисто; пересекающаяся пара выполнена по очереди; % конфликтов/откатов в норме.

## Результат (2026-06-10)

### Артефакты
- `bin/plan-waves.ps1` — авторитетный расчёт волн (Дирижёр §11.6)
- `bin/integrate.ps1` — последовательная интеграция: rebase + hq-merge + build/test gate
- `bin/tick5.ps1` — P5 драйвер (3 фазы: exec all waves → integrate → land)
- `agents/hq-merge.md` + `schemas/merge.schema.json` — Merge-агент
- `_fixtures/sample-intra-disjoint-{a,b}.md`, `sample-intra-overlap-{1,2}.md`
- `_templates/knowledge-card.md` — поле `shared_files`
- Правки `land.ps1`: chain-rebase fix (P5 chain root), conflicts_resolved из summary

### Валидация на scratch `.hq-scratch-p5` с `-Modules`
- **Case A (непересекающиеся):** INTRA-A(alpha.rs)+INTRA-B(beta.rs) → plan-waves=1 волна → exec ∥ → integrate clean (conflicts_resolved=[]) → ✅ AUTO-LAND (оба коммита на bare-remote)
- **Case B (пересекающиеся):** INTRA-OV1+INTRA-OV2(shared.rs) → plan-waves=2 волны → exec оба с одной базы main → integrate: OV1 OK, rebase OV2→OV1 = jj-конфликт → hq-merge сохранил b1+b2 → conflicts_resolved=[src/shared.rs] → 🟥 DEC (main НЕ сдвинут, оба b1+b2 в рабочей копии)
- **Stop-case:** integrate failure → tick5 СТОП без land, main не изменён (fail-closed)

### Исправления
- `integrate.ps1`: `RevId '@-'`/`'@ & conflicts()'` → `"${change}-"`/`"$change & conflicts()"` (работало с main workspace's @, а не exec workspace)
- `land.ps1`: rebase всей цепочки (`roots(rangeBase..change)`) вместо tip-only для P5 chains
- `tick5.ps1`: все волны сначала exec, потом один integrate, один land (иначе OV2 стартовал бы с обновлённого main → нет конфликта)

## Зависимости
Только-после P4.
