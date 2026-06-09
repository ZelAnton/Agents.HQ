---
repo: claude-plugins
type: card
kind: marketplace
language: конфиг (JSON/bash/YAML)
status: active
publishes: ["Claude Code marketplace: zelanton/claude-plugins"]
depends-on: []
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Персональный маркетплейс плагинов Claude Code. Два плагина: `vcs-workflow` (hook-based,
для Claude Code/Copilot/Factory) и `vcs-workflow-skill` (портативный skill, для ~20 allagents-клиентов)
— напоминания о version-control workflow. Без сборки/тестов.

## Ответственность / границы
**Входит:** манифесты маркетплейса/плагинов, hook-скрипты, skill-тела.
**НЕ входит:** прикладной код.

## Публичный интерфейс / точки входа
`.claude-plugin/marketplace.json` (+ `<plugin>/.claude-plugin/plugin.json`). Hooks в `<plugin>/hooks/`,
skills в `<plugin>/skills/<name>/SKILL.md`. Инструкции — в `CLAUDE.md` (не `AGENTS.md`).

## Сборка и тесты
```
(нет — конфигурационный репозиторий)
```

## Связи и зависимости
Самостоятельный. Сам сериализует workflow-философию (jj/git PR-flow), общую для остальных репо —
полезен как референс конвенций.

## На что смотреть при кросс-репо изменениях
Hook-текст и skill-тело держать семантически синхронными (см. CLAUDE.md). Стенза протокола `.hq`
дописана в `CLAUDE.md` (у репо нет `AGENTS.md`).

## Ссылки
- `../../../claude-plugins/README.md`, `../../../claude-plugins/CLAUDE.md`
