---
id: DEC-####
type: decision
title: <вопрос, на который нужен твой выбор>
date: YYYY-MM-DD
from: <repo-или-agent>
priority: P1            # P0 | P1 | P2
status: open            # open | answered | deferred
blocks: []              # [TASK-####] которые ждут решения
from-thread: null       # T-...  если решение выросло из обсуждения
options:
  - id: A
    label: <вариант A>
  - id: B
    label: <вариант B>
recommended: A          # что рекомендует агент (или null)

# ↓↓↓ ЗАПОЛНЯЕТ ЧЕЛОВЕК. Это авторитетный ответ — агент читает отсюда. ↓↓↓
answer:
  decision: null        # id выбранного варианта (A/B/...) или 'other'
  note: null            # свободный комментарий, если 'other' или нужны нюансы
  by: anton
  date: null
# и переключи status: open → answered
---

## Контекст
<!-- Зачем нужно решение, что зависит от ответа. -->

## Варианты
- **A. <label>** — плюсы/минусы, последствия.
- **B. <label>** — плюсы/минусы, последствия.

## Рекомендация агента
<!-- Почему recommended именно такой. -->

## Мой ответ
<!-- Необязательная свободная форма от человека (нюансы сверх answer.decision). -->
