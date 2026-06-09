---
repo: Python-repo-template
type: card
kind: template
language: Python
status: active
publishes: ["новые репо → PyPI"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых Python-репозиториев. Generic-скелет по общим стандартам шаблонов.

## Ответственность / границы
**Входит:** generic Python-репо (пакет, CI/release, community-health, агентские доки, init-скрипты).
**НЕ входит:** наши локальные процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}` (токены `__ProjectName__`/…), release `workflow_dispatch`.
Точные команды сборки/публикации — см. README/TEMPLATE.md шаблона.

## Сборка и тесты (в сгенерированном репо)
Сборка/тест через выбранный инструмент (uv/pip + pytest) — уточнить по README шаблона.

## Связи
Создаётся из `meta-repo-template`. Добавлен позже исходной четвёрки стандартов.

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/Python-repo-template/`, `../../../.Templates/TEMPLATE-STANDARDS.md`
