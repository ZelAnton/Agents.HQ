---
type: knowledge
topic: ownership
updated: 2026-06-09
---

# Границы ответственности

Что входит в зону каждого репо — чтобы агенты не «чинили» чужое молча, а слали сообщение
в `comms/` владельцу. Детальные карточки — в `../projects/<repo>/card.md`.

| Репо | Язык | Зона ответственности | НЕ его зона (адресат) |
|---|---|---|---|
| **ProcessGroup** | .NET | Lifetime дерева процессов (Job Objects / POSIX groups) для .NET | Запуск/стриминг → ProcessKit |
| **ProcessKit** | .NET | Process runner + стриминг поверх ProcessGroup | Lifetime-примитивы → ProcessGroup; VCS → vcs-toolkit-dotNet |
| **ProcessKit-rs** | Rust | Async process management, kill-on-drop, CliClient (ядро `processkit`) | VCS-обёртки → vcs-toolkit-rs; worktree → agent-workspace |
| **vcs-toolkit-dotNet** | .NET | Типизированные обёртки Git/jj/GitHub (CLI-драйв) для .NET | Workflow-сценарии → vcs-flow-dotnet; запуск → ProcessKit |
| **vcs-toolkit-rs** | Rust | Обёртки Git/jj/GitHub/GitLab/Gitea + facades + MCP | Workflow → vcs-flow-rs; запуск → processkit |
| **vcs-flow-dotnet** | .NET | Workflow-команды (commit/push…) TUI поверх toolkit | Примитивы CLI → vcs-toolkit-dotNet |
| **vcs-flow-rs** | Rust | TUI workflow (ratatui) поверх vcs-toolkit-rs | Примитивы CLI → vcs-toolkit-rs; запуск → processkit |
| **agent-workspace** | Rust | `ws` — worktree-изоляция для AI-агентов (git/jj) | Process mgmt → processkit |
| **tessmux** | Rust | Терминальная сетка для параллельных AI-сессий (ConPTY) | — (независим) |
| **Work-scripts** | .NET | Локальные рабочие скрипты (Windows, рабочее окружение) | — (независим) |
| **claude-plugins** | конфиг | Маркетплейс плагинов Claude Code (vcs-workflow) | — (независим) |
| **processkit-py** | Rust+PyO3 | *(no-repo-yet)* Python-биндинги к ядру `processkit` | Логика ядра → ProcessKit-rs |
| **processkit-go** | Go+FFI | *(no-repo-yet)* Go-биндинги к ядру `processkit` | Логика ядра → ProcessKit-rs |

## Пары паритета `-rs` / `.NET`

Значимое изменение в одном члене пары — повод завести зеркальную идею/задачу во втором:

- `ProcessKit` ⇄ `ProcessKit-rs`
- `vcs-toolkit-dotNet` ⇄ `vcs-toolkit-rs`
- `vcs-flow-dotnet` ⇄ `vcs-flow-rs`

## Правило

Заметил, что надо менять чужой репо — **не правь напрямую**. Заведи тред в `../comms/`
с `to: <владелец>` (или `HT`/`DEC`, если нужен человек). Менять можно только свой репо.
