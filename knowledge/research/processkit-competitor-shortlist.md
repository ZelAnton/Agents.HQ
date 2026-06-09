# Shortlist репозиториев для анализа

Ниже — shortlist GitHub-репозиториев по категориям: прямые конкуренты, источники идей и неожиданные, но полезные аналоги.

## 1. Прямые конкуренты

| Репозиторий | Язык | Почему важен | Что смотреть |
|---|---:|---|---|
| [botify-labs/process-kit](https://github.com/botify-labs/process-kit) | Python | Alternative unix process interface implementation; самый близкий по общей задаче процесс-менеджмента. | API-слой, semantics результата, lifecycle child process’ов. |
| [pkrumins/node-tree-kill](https://github.com/pkrumins/node-tree-kill) | JavaScript | Убивает дерево процессов целиком, включая root; очень близко к обещанию no-orphan guarantee. | Семантика tree kill, edge cases, portability. |
| [jub3i/tree-kill](https://github.com/jub3i/tree-kill) | JavaScript | Форк node-tree-kill, тоже про убийство process tree. | Отличия форка, качество cleanup, dependency surface. |

## 2. Источники идей

| Репозиторий | Язык | Почему важен | Что смотреть |
|---|---:|---|---|
| [GitHub Topics: process-management](https://github.com/topics/process-management) | Mixed | Витрина множества похожих репозиториев по управлению процессами. | Идеи для поиска supervision, cleanup, orchestration. |
| [taKO8Ki/awesome-alternatives-in-rust](https://github.com/taKO8Ki/awesome-alternatives-in-rust) | Markdown | Каталог Rust-альтернатив, полезен как навигатор по соседним системным инструментам. | Соседние crates, UX-паттерны, design references. |
| [GitHub Issues](https://github.com/features/issues) / [Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects) | Platform | Не репозиторий, но полезен как референс для issue-driven workflow и doc/metadata UX. | Как оформлять задачи, статусы, sub-issues, roadmap. |

## 3. Неожиданные, но полезные аналоги

| Репозиторий | Язык | Почему полезен | Что смотреть |
|---|---:|---|---|
| [youki](https://github.com/youki-dev/youki) | Rust | Container runtime; хороший источник идей по cgroups, containment и Linux-изоляции. | Job/container model, platform handling, resource control. |
| [just](https://github.com/casey/just) | Rust | Task runner; полезен для UX команд, композиции и читабельности CLI-ориентированного API. | Command syntax, ergonomics, docs, examples. |
| [pandora](https://github.com/pandora) | Mixed | Application manager; полезен как референс для supervision, restart policy и health-driven control. | Lifecycle management, restart/backoff, status UX. |

## 4. Что брать в анализ

Для каждого репозитория я бы сравнивал такие оси:

- tree-kill semantics: убивает ли только child или всё дерево.
- async API: есть ли streaming, interactive stdin, readiness.
- timeout/cancellation: как различаются exit, timeout, kill, cancel.
- supervision: restart policies, backoff, stop conditions.
- platform coverage: Windows, Linux, macOS/BSD.
- testing: mock, scripted runner, record/replay.

## 5. Приоритет для разбора

Если начинать с малого, я бы взял такой порядок:

1. [botify-labs/process-kit](https://github.com/botify-labs/process-kit)
2. [pkrumins/node-tree-kill](https://github.com/pkrumins/node-tree-kill)
3. [jub3i/tree-kill](https://github.com/jub3i/tree-kill)
4. [youki](https://github.com/youki-dev/youki)
5. [just](https://github.com/casey/just)