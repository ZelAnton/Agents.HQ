---
id: TASK-####
type: task
title: <короткое название>
date: YYYY-MM-DD
scope: cross            # cross | <repo>   (cross-репо спека → tasks/, single → projects/<repo>/tasks/)
status: queued          # queued | ready | in-progress | blocked | done | cancelled
priority: P1            # P0 | P1 | P2
repos: [<repoA>, <repoB>]
depends-on: []          # [TASK-####] — only-after
parallel-safe-with: []  # [TASK-####] — можно параллельно
assigned-to: null       # claim оркестратором
origin: null            # IDEA-... | T-...#NN | DEC-... | MSG-...
---

## Цель
<!-- Что должно стать правдой по завершении. -->

## Объём по репозиториям
### <repoA>
<!-- Конкретные изменения. -->
### <repoB>

## Последовательность шагов
1.
2.

## Критерии готовности (DoD)
- [ ]

## Риски / зависимости
