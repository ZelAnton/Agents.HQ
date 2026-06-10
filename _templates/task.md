---
id: TASK-####
type: task
title: <короткое название>
date: YYYY-MM-DD
scope: cross            # cross | <repo>   (cross-репо спека → tasks/, single → projects/<repo>/tasks/)
status: queued          # intake | queued | ready | in-progress | in-review | fix-needed | blocked | escalated | done | cancelled | rejected
priority: P1            # P0 | P1 | P2
repos: [<repoA>, <repoB>]
depends-on: []          # [TASK-####] — only-after
parallel-safe-with: []  # [TASK-####] — можно параллельно
assigned-to: null       # claim оркестратором
origin: null            # IDEA-... | T-...#NN | DEC-... | MSG-... | human
created-by: null        # human | agent:<repo>
risk: null              # low | medium | high — ставит планировщик
fix-attempt: 0          # счётчик неуспешных review-fix циклов
session: null           # SESS-TASK-####-... — активная/последняя сессия
blocked-reason: null    # dependency | external | human — причина блокировки
review: null            # pass | fail | <ссылка на verdict>
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
