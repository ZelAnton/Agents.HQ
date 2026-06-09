---
id: HT-0001
type: human-task
title: Создать удалённый репозиторий для .hq и запушить
date: 2026-06-09
from: setup
repo: cross
priority: P2
status: todo
blocks: []
related: []
---

## Что сделать
`.hq` инициализирован как локальный git-репозиторий (identity `Anton Zhelezniakou <github@zelanton.net>`,
GitHub `ZelAnton`), сделан первый коммит. Для истории/переносимости/бэкапа нужно завести remote:

1. Создать приватный репозиторий на GitHub (например `ZelAnton/personal-hq` — имя на твой выбор).
   - через CLI: `gh repo create ZelAnton/personal-hq --private --source d:\GitHub\Personal\.hq --remote origin --push`
   - или вручную: создать пустой репо, затем в `d:\GitHub\Personal\.hq`:
     `git remote add origin <url>` и `git push -u origin master`.
2. (Опц.) Настроить branch protection, если захочешь PR-flow и для `.hq`.

## Как проверить, что готово
`git -C d:\GitHub\Personal\.hq remote -v` показывает `origin`; `git push` проходит;
репозиторий виден на GitHub.

## Результат
<!-- Заполни: ссылка на репозиторий, имя, что запушено. Затем status: done. -->
