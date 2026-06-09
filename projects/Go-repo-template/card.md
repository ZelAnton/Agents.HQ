---
repo: Go-repo-template
type: card
kind: template
language: Go
status: active
publishes: ["новые репо → Go module / pkg.go.dev"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых Go-репозиториев. Generic-скелет по общим стандартам шаблонов.

## Ответственность / границы
**Входит:** generic Go-репо (модуль, CI/release, community-health, агентские доки, init-скрипты).
**НЕ входит:** наши локальные процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}` (токены `__ProjectName__`/…), release `workflow_dispatch`.
Точные команды сборки/публикации — см. README/TEMPLATE.md шаблона.

## Сборка и тесты (в сгенерированном репо)
`go build ./...` / `go test ./...` (уточнить по README шаблона).

## Связи
Создаётся из `meta-repo-template`. Не входит в исходную четвёрку `TEMPLATE-STANDARDS.md` (добавлен позже).

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/Go-repo-template/`, `../../../.Templates/TEMPLATE-STANDARDS.md`
