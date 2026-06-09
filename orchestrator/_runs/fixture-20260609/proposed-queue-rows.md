# Предлагаемые строки QUEUE (валидация, НЕ применено)

Источник: фикстура `T-fixture-sample` → triage=accept → planner. Реальный `tasks/QUEUE.md` не тронут.

| ID | Scope | Приоритет | Статус | scope_paths | depends-on | parallel-safe-with |
|----|-------|-----------|--------|-------------|------------|--------------------|
| TASK-0005 | ProcessKit-rs | P2 | queued | src/buffer.rs | — | 0008, 0009 |
| TASK-0006 | ProcessKit-rs | P2 | queued | src/command.rs | TASK-0005 | 0008, 0009 |
| TASK-0007 | ProcessKit-rs | P2 | queued | src/buffer.rs, src/command.rs, tests/ | TASK-0005, TASK-0006 | 0008, 0009 |
| TASK-0008 | ProcessKit-rs | P2 | queued | docs/streaming.md | — | 0005, 0006, 0007, 0009 |
| TASK-0009 | ProcessKit-rs | P2 | queued | CHANGELOG.md | — | 0005..0008 |
| TASK-0010 | ProcessKit (.NET) | P2 | queued | (паритет, отдельная декомпозиция) | — | 0005..0009 |

## Волны
- **Волна 1 (нет зависимостей):** TASK-0005, TASK-0008, TASK-0009, TASK-0010 — параллельно.
- **Волна 2 (after 0005):** TASK-0006.
- **Волна 3 (after 0005+0006):** TASK-0007.

Замечание: 0008/0009 параллельно-безопасны (непересекающиеся файлы); 0006 только-после 0005 (нужен enum);
0007 только-после 0005+0006 (тесты обоих модулей); 0010 — другой репо (физически без конфликтов).
