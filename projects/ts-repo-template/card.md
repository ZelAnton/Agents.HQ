---
repo: ts-repo-template
type: card
kind: template
language: TypeScript
status: active
publishes: ["новые репо → npm"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых TypeScript-репозиториев. Generic-скелет по общим стандартам шаблонов.

## Ответственность / границы
**Входит:** generic TS-репо (package.json, tsconfig, CI/release, community-health, агентские доки,
init-скрипты). **НЕ входит:** наши локальные процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}` (токены `__ProjectName__`/…), release `workflow_dispatch`.
Точные команды сборки/публикации — см. README/TEMPLATE.md шаблона.

## Сборка и тесты (в сгенерированном репо)
Через выбранный пакетный менеджер (npm/pnpm) + тест-раннер — уточнить по README шаблона.

## Связи
Создаётся из `meta-repo-template`. Добавлен позже исходной четвёрки стандартов.

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/ts-repo-template/`, `../../../.Templates/TEMPLATE-STANDARDS.md`
