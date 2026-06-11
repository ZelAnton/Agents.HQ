---
type: knowledge
topic: orchestrator-state
updated: 2026-06-11
---

# Состояние Дирижёра — форматы и правила

Всё состояние оркестра — это файлы в `.hq` (в git). Здесь — конкретные форматы **as-built**
(реализовано в `hq-conductor`, этапы M1–M4 TASK-0018), дополняющие архитектурный план в
[`IMPLEMENTATION.md`](IMPLEMENTATION.md). Контракты данных — в [`schemas/`](schemas/).

## Единственный писатель + лок
- Очередь `tasks/QUEUE.md` и статусы задач пишет **только Дирижёр** (`hq-conductor tick`).
  Субагенты (plan/exec/review) возвращают структурный результат; применяет его Дирижёр.
- На время тика Дирижёр держит лок **`orchestrator/.lock`** (git-ignored), берётся атомарно
  через `create_new` (O_EXCL) — нет TOCTOU-гонки двух тиков. Один активный тик. Стейл-лок
  (владелец-PID мёртв ИЛИ возраст > 60 мин) снимается при старте.

## `hq-conductor` — сабкоманды
Rust-бинарь `orchestrator/bin/hq-conductor`. Корень `.hq` ищется вверх от cwd или задаётся `--hq`.
- `tick [--mode mock|assist|auto-low] [--max-plan P] [--max-exec E] [--max-review R] [--max-per-repo K]`
  — один детерминированный тик (см. ниже).
- `session <new|heartbeat|end|list|gc>` — управление каталогом сессий.
- `claim` · `journal` — lease/claim на задачу и идемпотентный журнал мутаций (S3).
- `doctor` — recovery-probe (локи, прогоны, stale-сессии), read-only.
- `metrics` — метрики последних тиков (рендер в `STATUS.md`).

## Один тик (`hq-conductor tick`)
Под `.lock`, single-writer. Шаги:
1. **Pause-гейт** — `automation.json` `paused:true` ⇒ тик выходит, ничего не делая.
2. **Session GC** — осиротевшие сессии (lease истёк + PID мёртв) → `_archive`, `state: stale`.
3. **Scan** — все спеки задач из `tasks/`, `orchestrator/tasks/`, `projects/*/tasks/` (дедуп по `id`).
4. **Recovery** (реконсиляция по состоянию, не replay журнала):
   - `in-progress` без живого claim → `ready`;
   - протухший claim на `intake`/`ready`/`in-review` → снят (статус не меняется);
   - `fix-needed` → `ready` (`fix-attempt` < N) или `escalated` (≥ N).
5. **Promote** — `queued` со всеми `depends-on` в терминале → `ready`.
6. **Dispatch** под лимитами (свободный слот роли = лимит − активные сессии этой роли),
   per-repo cap на роль:
   - `intake` → роль **plan** (DoR-гейт, `plan-one.ps1`/`hq-dor`);
   - `ready` → роль **exec** (ТОЛЬКО `autonomy: auto-low|auto`, `exec-one.ps1`/`hq-exec`);
   - `in-review` → роль **review** (`verify-one.ps1`/`hq-verify` → risk() → land|fix-needed|DEC).
7. **Finalize** — снять лок, перегенерировать `STATUS.md` (метрики + секция активных сессий).

**Режимы.** `mock` — канонические переходы без LLM и без land (проверка state machine;
autonomy-гейт НЕ применяется, но `owner:human` исключается как и везде); `assist` — «сухой»
прогон (печатает, что бы запустил, ничего не спавнит); `auto-low` — реальные агенты + авто-land
низкорисковых, рисковое → DEC.

**Crash-safety.** `tick.json` (`mutations[]` с `applied:bool`) — аудит-след намерений; гарантии
даёт сочетание: claim с lease+PID+host (fail-closed — нет двойного спавна), **атомарная** FM-запись
на каждый переход, recovery в начале следующего тика. Убийство тика на любом шаге → следующий тик
реконсилит и доводит, без двойной работы.

## Журнал тиков — `orchestrator/_runs/<run_id>/`
- `run_id` = `TICK-<YYYY-MM-DD_HH-MM-SS-fff>-<pid>` (миллисекунды + PID исключают коллизию
  двух тиков одного процесса в одну секунду).
- `tick.json` — `{run_id, started, mode, mutations[]}`; каждая мутация — `{id, kind, task,
  applied, …}` (идемпотентный журнал S3).
- Подкаталоги по роли/задаче (live-режимы `assist`/`auto-low`):
  - `plan-<TASK>/plan-result.json` — `{decision: accept|reject|escalate, reason}`
    ([`plan-result.schema.json`](schemas/plan-result.schema.json));
  - `exec-<TASK>/` — `summary.json` (repo, workspace, dest, гейты `gate_build`/`gate_tests`,
    `out_of_scope`, `leaks`, `executor_status`), `executor-result.json`, `build.log`,
    `test.log`, `diff.txt`;
  - `review-<TASK>/` — `verify.json` (`verdict`/`dod_met`/`findings`,
    [`verify.schema.json`](schemas/verify.schema.json)), `review-context.json` (`changed_files`,
    `diff_lines`, `has_conflict`, `is_empty`, `leaks` — факты для `risk()`);
  - `fix-feedback/<TASK>.md` — замечания ревью для следующего re-exec (informed retry, см. fix-loop).
- `_runs/` **git-ignored** (может содержать произвольный текст/абсолютные пути) — каталог хранится
  через `.gitkeep`.

## State machine задачи (полный словарь)

```
intake ──planner(DoR ok)──> queued ──(deps done)──> ready
intake ──planner reject──> rejected
intake ──needs human────> escalated ──DEC answered──> intake|queued
ready  ──conductor claim (auto-low, под лимитом)──> in-progress
in-progress ──exec ok──> in-review
in-progress ──exec blocked──> blocked (blocked-reason: dependency|external)
in-progress ──exec needs human──> escalated
in-review ──review pass + risk=low + autonomy≥auto-low──> land ──> done
in-review ──review pass + risk≠low──> escalated (DEC land)
in-review ──review fail──> fix-needed
fix-needed ──fix-attempt<N──> ready (re-exec: НОВЫЙ workspace + замечания ревью из _runs/fix-feedback/)
fix-needed ──fix-attempt≥N──> escalated
blocked ──dep done / answered──> ready
escalated ──answered──> resume (intake|queued|ready по контексту)
любой leased + lease истёк + PID мёртв ──doctor──> stale → blocked|escalated
done / cancelled / rejected = терминал → _archive/
```

Хранимые статусы (11): `intake` · `queued` · `ready` · `in-progress` · `in-review` ·
`fix-needed` · `blocked` · `escalated` · `done` · `cancelled` · `rejected`.
Производные (не хранятся): `stale` (doctor по lease+PID), `ready_set` (topo deps=done).

> **`owner: human`** исключает задачу из ВСЕГО авто-обслуживания — recovery её не дёргает и
> dispatch не берёт ни в одну роль (см. ниже). Поэтому мета/человеческие задачи не «ездят»
> по этой машине автоматически.

Дополнительные поля задачи (additive к claim-полям S3):
```yaml
created-by: human|agent:<repo>      # источник задачи
owner: human|agent:<repo>|null      # КТО УПРАВЛЯЕТ; owner:human ⇒ вне авто-recovery и авто-диспатча
autonomy: auto-low|auto|assist|propose|human-approval|null  # гейт безнадзорного exec (см. ниже)
risk: low|medium|high               # risk level, ставит планировщик
fix-attempt: 0                      # число неуспешных fix-циклов; учитывается на fix-needed→ready
session: SESS-TASK-####-...         # ID активной/последней сессии
blocked-reason: dependency|external|human
review: pass|fail|<ссылка>          # итог последнего ревью
run-dir: <путь в _runs/>            # ephemeral: ставит exec (где workspace/результат), снимается
                                    #   на терминальном review (done/escalated)
```

## Поля claim в спеке задачи (frontmatter)
Ставит Дирижёр при взятии задачи в работу:
```yaml
assigned-to: <agent-id|null>   # кто исполняет
claimed-at: <ISO|null>         # когда взято
lease-until: <ISO|null>        # TTL лизы; истекла + PID мёртв → задача снова свободна
owner-pid: <int|null>          # PID исполнителя (для is_pid_alive)
owner-host: <string|null>      # хост исполнителя (fail-closed для чужого хоста)
```
Переподхват — единая логика `owner_reclaimable` (та же для задач и сессий): свой хост + PID мёртв
→ забрать сразу; PID жив (мог быть переиспользован) или чужой хост → только после `lease +
FORCE_RELEASE_GRACE` (3 ч); claimed без lease и владелец не подтверждён мёртвым → НЕ забирать.

## Автономия — гейт безнадзорного exec
**As-built: гейт читает поле `autonomy` САМОЙ задачи** (`autonomy_allows_auto_exec`, fail-closed):
- `auto-low` / `auto` → задача может быть исполнена безнадзорно (exec-спавн в `--mode auto-low`);
- отсутствует / `propose` / `assist` / `human-approval` → НЕ исполняется авто (паркуется в `ready`,
  печатается `exec-skip`) — нужно решение человека.

Гейт стоит ТОЛЬКО на роли exec (plan и review read-only, репо не мутируют; до `in-review` задача
уже прошла exec-гейт). Это и есть защита продуктовых репо: **задача без явного `auto-low` никогда
не исполняется сама**. Repo-уровневое наследование автономии (`projects/<repo>/card.md`:
`propose|assist|auto-low`, default `propose`) — будущий слой (каталог репо); сейчас задача
opt-in'ит явно своим полем.

## `owner: human` / мета-задачи
`owner: human` исключает задачу из ВСЕГО авто-обслуживания: recovery не меняет ей статус (переходы
ведёт человек), dispatch не берёт ни в plan/exec/review (единый chokepoint `select_for_dispatch`).
Комплементарно автономии: `autonomy` opt-in'ит задачу В безнадзорный exec; `owner:human` opt-out'ит
ИЗ всего. Так мета/человеческие задачи (напр. TASK-0017/0018) не демоутятся и не диспатчатся каждый
тик. (Авто-гейт и так не пустил бы их в exec — но `owner:human` ещё и убирает шум recovery в логе.)

## Каталог сессий — `orchestrator/sessions/{active,_archive}/`
Живая память выполнения. Запись `SESS-TASK-<id>-<run_token>.md`
([`session.schema.json`](schemas/session.schema.json)):
- **frontmatter** (машинный head): `role` (plan|exec|review), `model`, `state`
  (running|done|failed|stale), `repo`, `worktree`, `branch`, `run-dir` (→ `_runs/<run_id>/`),
  `lease-until`, `last-heartbeat`, `started`, `ended`, `owner-pid`, `owner-host`;
- **тело** (дозаписываемое): `## Milestones`, `## Decisions`, `## Handoff`, `## Next`.

Heartbeat продлевает `lease-until` + `last-heartbeat`. Stale = `owner_reclaimable` (та же логика,
что claim задач, чтобы не расходились) → `gc` архивирует, `state: stale`. По завершении воркера —
`state: done|failed` + перенос в `_archive/`. `run_token` несёт `run_id` тика, поэтому id уникален
между тиками (re-exec не перезаписывает архив прошлого). `sessions/active/*` и `_archive/*`
**git-ignored** (содержат PID/пути) — каталоги хранятся через `.gitkeep`.

## Стоп-кран и политики — `orchestrator/automation.json`
**Версионируемый** (НЕ git-ignored) конфиг:
```json
{ "paused": false, "max_plan": 1, "max_exec": 2, "max_review": 1, "autonomy": "auto-low" }
```
- `paused` — **kill-switch**: `tick` и обёртка `hq-tick.ps1` выходят в начале, не спавня новое
  (активные сессии доживают, не убиваются). Тоггл — скиллы `/hq-pause` / `/hq-resume`.
- `max_plan` / `max_exec` / `max_review` — лимиты слотов на роль за тик (обёртка `hq-tick.ps1`
  берёт их отсюда; явный CLI-аргумент переопределяет; `tick` сам по себе использует свои дефолты
  1/2/1, если запущен напрямую).
- `autonomy` — зарезервировано; **живой гейт — поле задачи** (см. выше), это поле пока декоративно.

## Поверхность skills — `orchestrator/skills/<name>/SKILL.md`
Источник правды — `orchestrator/skills/`; установка в `.claude/skills/` через `install-skill.ps1`
(сверяет хеш). Headless-эквиваленты — в `orchestrator/bin/`.
- `/add-task` — intake-задача + строка в `QUEUE.md` (headless: `bin/add-task.ps1`).
- `/hq-tick` — один тик (тело `/loop /hq-tick` для автономного режима; обёртка `bin/hq-tick.ps1`).
- `/hq-status` — read-only сводка состояния (счётчики, очередь, сессии, DEC, INBOX, последний тик).
- `/hq-pause` · `/hq-resume` — kill-switch через `automation.json`.
- `/comms` — триаж + планирование входящего (`bin/comms.ps1`).

## Дашборд — `orchestrator/STATUS.md`
Генерируется Дирижёром в конце тика. Человеко-читаемая сводка: строка «Последний тик», метрики
последних 20 прогонов, секция «Активные сессии». Шаблон — `STATUS.template.md`. Не редактировать
вручную (перезаписывается).

## Исключения обработки
Конфиг тика держит список входящих, которые Дирижёр **пропускает** (`skip`). Сейчас в нём —
`T-20260609-vcs-processkit-feedback` (по решению: не обрабатываем). Альтернатива — поле
`orchestrator: skip` во frontmatter треда (не используем, чтобы не править реальный тред).
