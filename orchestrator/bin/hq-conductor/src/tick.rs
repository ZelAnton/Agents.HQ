//! Deterministic tick dispatcher for `hq-conductor tick`.
//! --mode mock runs canonical workers without LLM calls (for testing the state machine).
//!
//! Crash-safety model (important — read before changing recovery):
//! Восстановление здесь — **реконсиляция по состоянию**, а не буквальный replay журнала.
//! Журнал (`_runs/<run_id>/tick.json`, mutations[] с `applied:bool`) — это аудит-след
//! намерений; его никто не «доигрывает». Гарантии даёт сочетание:
//!   1. claim с lease+PID+host (fail-closed): `owner_reclaimable` отдаёт задачу только если
//!      владелец точно мёртв (или после force-grace), поэтому двойного claim/спавна нет;
//!   2. каждый статус-переход — ОДНА атомарная запись FM (нет «claimed, но статус ещё старый»
//!      для exec/review таким образом, что задача потерялась бы);
//!   3. рекавери в начале тика чинит «зависшие»: `in-progress` без живого claim → `ready`,
//!      `fix-needed` → requeue/escalate; задачи в intake/ready/in-review с протухшим claim
//!      снова становятся свободными для select (claim перезапишется при ре-диспатче);
//!   4. `gc_stale_sessions` архивирует осиротевшие сессии той же логикой `owner_reclaimable`.
//!
//! Убийство тика на любом шаге → следующий тик реконсилит и доводит, без двойной работы.

use crate::dispatch::{self, TaskInfo};
use crate::fm::{fm_get, fm_remove, fm_set, parse_fm, render_fm};
use crate::journal;
use crate::metrics;
use crate::session;
use crate::state::{current_hostname, LockInfo, Paths};
use clap::{Args, ValueEnum};
use std::fs::OpenOptions;
use std::io::Write as _;
use std::path::{Path, PathBuf};

const FIX_MAX: u32 = 3;

// ---------- CLI ----------

#[derive(Args)]
pub struct TickArgs {
    /// Режим: mock (без LLM), assist (показывает план), auto-low (реальные агенты, авто-land для risk=low)
    #[arg(long, value_enum, default_value_t = TickMode::Mock)]
    pub mode: TickMode,
    #[arg(long, default_value_t = 1)]
    pub max_plan: usize,
    #[arg(long, default_value_t = 2)]
    pub max_exec: usize,
    #[arg(long, default_value_t = 1)]
    pub max_review: usize,
    /// Maximum tasks per repo in-flight per role
    #[arg(long, default_value_t = 2)]
    pub max_per_repo: usize,
}

#[derive(ValueEnum, Clone, Debug)]
pub enum TickMode {
    AutoLow,
    Assist,
    Mock,
}

impl std::fmt::Display for TickMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TickMode::AutoLow => write!(f, "auto-low"),
            TickMode::Assist => write!(f, "assist"),
            TickMode::Mock => write!(f, "mock"),
        }
    }
}

// ---------- RAII lock guard ----------

struct LockGuard {
    path: PathBuf,
}
impl LockGuard {
    fn new(path: &Path) -> Self {
        Self { path: path.to_path_buf() }
    }
}
impl Drop for LockGuard {
    fn drop(&mut self) {
        // Only remove if we own it (PID matches)
        if let Some(lock) = LockInfo::read(&self.path) {
            if lock.pid == std::process::id() {
                std::fs::remove_file(&self.path).ok();
            }
        }
    }
}

// ---------- Lock acquire ----------

fn acquire_lock(lock_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    // Атомарное получение через create_new (O_EXCL): исключает TOCTOU-гонку двух тиков,
    // где оба видят «нет лока», оба пишут и оба продолжают (двойной спавн/claim).
    for _ in 0..3 {
        match OpenOptions::new().write(true).create_new(true).open(lock_path) {
            Ok(mut f) => {
                // Окно «файл создан, но пустой» до write_all: конкурент прочитает его как
                // непарсящийся и попробует remove_file. На Windows наш открытый хэндл `f`
                // (без FILE_SHARE_DELETE) блокирует удаление, пока мы не закончим запись —
                // поэтому гонка безопасна. Хэндл живёт до конца функции (drop при return).
                let content = format!("{}\t{}", std::process::id(), chrono::Utc::now().to_rfc3339());
                f.write_all(content.as_bytes())?;
                return Ok(());
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                // Лок существует. Забираем только если владелец мёртв ИЛИ лок протух.
                match LockInfo::read(lock_path) {
                    Some(lock) if lock.is_pid_alive() && !lock.is_stale() => {
                        return Err(format!(
                            "lock занят (PID={}, ещё свежий) — попробуй позже",
                            lock.pid
                        )
                        .into());
                    }
                    // мёртвый/протухший/непарсящийся → удалить и повторить create_new.
                    // Если конкурент успеет создать свой между remove и create_new — снова
                    // AlreadyExists, и цикл (до 3 раз) отрабатывает корректно.
                    _ => {
                        std::fs::remove_file(lock_path).ok();
                        continue;
                    }
                }
            }
            Err(e) => return Err(e.into()),
        }
    }
    Err("не удалось получить lock после нескольких попыток (гонка?)".into())
}

// ---------- Task frontmatter helpers ----------

/// Update (set/remove) frontmatter fields and write atomically.
fn write_task_fm(
    path: &Path,
    set: &[(&str, &str)],
    remove: &[&str],
) -> Result<(), Box<dyn std::error::Error>> {
    let content = std::fs::read_to_string(path)?;
    let (mut pairs, body_start) = parse_fm(&content);
    // body_start == 0 ⇔ parse_fm не нашёл валидный frontmatter (нет открывающего/закрывающего
    // `---`). Записывать в таком случае нельзя: render_fm затолкал бы весь файл в тело и потерял
    // бы исходные поля (id/scope/depends-on…) — задача молча выпала бы из диспетчера. Отказ.
    if body_start == 0 {
        return Err(format!(
            "отказ записи {}: не удалось распарсить frontmatter (повреждён?)",
            path.display()
        )
        .into());
    }
    let body = &content[body_start..];
    for (k, v) in set {
        fm_set(&mut pairs, k, v);
    }
    for k in remove {
        fm_remove(&mut pairs, k);
    }
    let new_content = render_fm(&pairs, body);
    let tmp = PathBuf::from(format!("{}.{}.tmp", path.display(), std::process::id()));
    std::fs::write(&tmp, &new_content)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

const CLAIM_FIELDS: &[&str] = &["claimed-at", "lease-until", "owner-pid", "owner-host"];

fn claim_fields_set(owner: &str, now: &str, lease_until: &str) -> Vec<(String, String)> {
    vec![
        ("assigned-to".to_owned(), owner.to_owned()),
        ("claimed-at".to_owned(), now.to_owned()),
        ("lease-until".to_owned(), lease_until.to_owned()),
        ("owner-pid".to_owned(), std::process::id().to_string()),
        ("owner-host".to_owned(), current_hostname()),
    ]
}

// ---------- Recovery ----------

/// Revert `in-progress` tasks with no active claim back to `ready`.
fn revert_stale_in_progress(
    tasks: &mut [TaskInfo],
    run_dir: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    for task in tasks.iter_mut() {
        if task.status != "in-progress" { continue; }
        if !dispatch::task_is_free(task) { continue; }
        let mid = journal::record_mutation(
            run_dir,
            "recovery-revert",
            &task.id,
            Some(serde_json::json!({"from": "in-progress", "to": "ready", "reason": "stale-claim"})),
        )?;
        write_task_fm(
            &task.path,
            &[("status", "ready"), ("assigned-to", "null")],
            CLAIM_FIELDS,
        )?;
        task.status = "ready".to_owned();
        journal::mark_mutation_applied(run_dir, &mid)?;
        println!("  recovery: {} in-progress → ready (stale claim)", task.id);
    }
    Ok(())
}

/// Handle `fix-needed` tasks: requeue or escalate based on fix-attempt counter.
fn requeue_fix_needed(
    tasks: &mut [TaskInfo],
    run_dir: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    for task in tasks.iter_mut() {
        if task.status != "fix-needed" { continue; }
        if task.fix_attempt < FIX_MAX {
            let new_attempt = (task.fix_attempt + 1).to_string();
            let mid = journal::record_mutation(run_dir, "fix-requeue", &task.id, None)?;
            write_task_fm(
                &task.path,
                &[("status", "ready"), ("fix-attempt", &new_attempt)],
                &[],
            )?;
            task.fix_attempt += 1;
            task.status = "ready".to_owned();
            journal::mark_mutation_applied(run_dir, &mid)?;
            println!("  fix-requeue: {} → ready (attempt {})", task.id, task.fix_attempt);
        } else {
            let reason = format!("fix-loop exhausted (attempt {})", task.fix_attempt);
            let mid = journal::record_mutation(run_dir, "fix-escalate", &task.id, None)?;
            write_task_fm(
                &task.path,
                &[("status", "escalated"), ("blocked-reason", &reason)],
                &[],
            )?;
            task.status = "escalated".to_owned();
            journal::mark_mutation_applied(run_dir, &mid)?;
            println!("  fix-escalate: {} → escalated (≥{FIX_MAX} attempts)", task.id);
        }
    }
    Ok(())
}

// ---------- Promotion ----------

/// Promote `queued` tasks whose deps are all done → `ready`.
fn promote_queued_to_ready(
    tasks: &mut [TaskInfo],
    run_dir: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    // Collect indices first to avoid double-borrow (both borrows are shared, but collect avoids
    // holding iterator + mutable ref simultaneously in the loop below)
    let to_promote: Vec<usize> = (0..tasks.len())
        .filter(|&i| {
            tasks[i].status == "queued" && dispatch::task_deps_done(&tasks[i], tasks)
        })
        .collect();
    for idx in to_promote {
        let task_id = tasks[idx].id.clone();
        let task_path = tasks[idx].path.clone();
        let mid = journal::record_mutation(run_dir, "promote-ready", &task_id, None)?;
        write_task_fm(&task_path, &[("status", "ready")], &[])?;
        tasks[idx].status = "ready".to_owned();
        journal::mark_mutation_applied(run_dir, &mid)?;
        println!("  promote: {task_id} queued → ready");
    }
    Ok(())
}

// ---------- Mock workers ----------

/// Lease per role. Claim-lease ДОЛЖЕН быть ≥ соответствующего session-lease, иначе claim
/// задачи протухает, пока живой воркер ещё держит её (риск кражи/двойного exec в M3).
const PLAN_LEASE_SEC: i64 = 300;
const EXEC_LEASE_SEC: i64 = 900;
const REVIEW_LEASE_SEC: i64 = 300;

fn make_claim(owner: &str, lease_sec: i64) -> Vec<(String, String)> {
    let now = chrono::Utc::now();
    let lease_until = now + chrono::Duration::seconds(lease_sec);
    claim_fields_set(owner, &now.to_rfc3339(), &lease_until.to_rfc3339())
}

fn apply_set(path: &Path, set: &[(String, String)]) -> Result<(), Box<dyn std::error::Error>> {
    let pairs_slice: Vec<(&str, &str)> = set.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();
    write_task_fm(path, &pairs_slice, &[])
}

/// Mock plan: `intake` → (claim) → `queued`, DoR always passes.
fn mock_plan(
    paths: &Paths,
    task: &TaskInfo,
    run_dir: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let task_id = &task.id;

    // Claim
    let mid_claim = journal::record_mutation(run_dir, "plan-claim", task_id, None)?;
    let claim = make_claim("mock-planner", PLAN_LEASE_SEC);
    apply_set(&task.path, &claim)?;
    journal::mark_mutation_applied(run_dir, &mid_claim)?;

    // Session
    let sess_id = session::session_new(
        paths, task_id, "plan", "mock", &task.scope, &run_dir.to_string_lossy(), None, None, PLAN_LEASE_SEC as u64,
    )?;

    // Transition intake → queued
    let mid_done = journal::record_mutation(
        run_dir,
        "plan-done",
        task_id,
        Some(serde_json::json!({"result": "queued", "session": sess_id})),
    )?;
    write_task_fm(
        &task.path,
        &[("status", "queued"), ("assigned-to", "null")],
        CLAIM_FIELDS,
    )?;
    session::session_end(paths, &sess_id, "done", Some("mock plan: intake → queued (DoR pass)"))?;
    journal::mark_mutation_applied(run_dir, &mid_done)?;

    println!("  plan: {task_id} → queued (mock)");
    Ok(())
}

/// Mock exec: `ready` → `in-progress` (claim) → `in-review`.
fn mock_exec(
    paths: &Paths,
    task: &TaskInfo,
    run_dir: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let task_id = &task.id;

    // Claim + set in-progress
    let mid_claim = journal::record_mutation(run_dir, "exec-claim", task_id, None)?;
    let mut claim = make_claim("mock-exec", EXEC_LEASE_SEC);
    claim.push(("status".to_owned(), "in-progress".to_owned()));
    apply_set(&task.path, &claim)?;
    journal::mark_mutation_applied(run_dir, &mid_claim)?;

    // Session
    let sess_id = session::session_new(
        paths, task_id, "exec", "mock", &task.scope, &run_dir.to_string_lossy(), None, None, EXEC_LEASE_SEC as u64,
    )?;

    // Transition in-progress → in-review
    let mid_done = journal::record_mutation(
        run_dir,
        "exec-done",
        task_id,
        Some(serde_json::json!({"result": "in-review", "session": sess_id})),
    )?;
    write_task_fm(
        &task.path,
        &[("status", "in-review"), ("assigned-to", "null"), ("session", &sess_id)],
        CLAIM_FIELDS,
    )?;
    session::session_end(paths, &sess_id, "done", Some("mock exec: ready → in-review"))?;
    journal::mark_mutation_applied(run_dir, &mid_done)?;

    println!("  exec: {task_id} → in-review (mock)");
    Ok(())
}

/// Mock review: `in-review` → (claim) → `done`. Always passes; risk=low.
fn mock_review(
    paths: &Paths,
    task: &TaskInfo,
    run_dir: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let task_id = &task.id;

    // Claim (status stays in-review while review is running)
    let mid_claim = journal::record_mutation(run_dir, "review-claim", task_id, None)?;
    let claim = make_claim("mock-reviewer", REVIEW_LEASE_SEC);
    apply_set(&task.path, &claim)?;
    journal::mark_mutation_applied(run_dir, &mid_claim)?;

    // Session
    let sess_id = session::session_new(
        paths, task_id, "review", "mock", &task.scope, &run_dir.to_string_lossy(), None, None, REVIEW_LEASE_SEC as u64,
    )?;

    // Transition in-review → done (mock: always pass, risk=low)
    let mid_done = journal::record_mutation(
        run_dir,
        "review-done",
        task_id,
        Some(serde_json::json!({"result": "done", "verdict": "pass", "risk": "low", "session": sess_id})),
    )?;
    write_task_fm(
        &task.path,
        &[("status", "done"), ("assigned-to", "null"), ("review", "pass/mock"), ("risk", "low")],
        CLAIM_FIELDS,
    )?;
    session::session_end(paths, &sess_id, "done", Some("mock review: pass → done"))?;
    journal::mark_mutation_applied(run_dir, &mid_done)?;

    println!("  review: {task_id} → done (mock)");
    Ok(())
}

// ---------- STATUS.md update ----------

fn render_sessions_section(sessions: &[session::SessionEntry]) -> String {
    if sessions.is_empty() {
        return "## Активные сессии\n(нет активных сессий)".to_owned();
    }
    let mut s = String::from(
        "## Активные сессии\n| ID | Роль | Задача | Состояние | Heartbeat |\n|---|---|---|---|---|\n",
    );
    for (id, _, pairs) in sessions {
        let role = fm_get(pairs, "role").unwrap_or_default();
        let task = fm_get(pairs, "task").unwrap_or_default();
        let st = fm_get(pairs, "state").unwrap_or_default();
        let hb = fm_get(pairs, "last-heartbeat").unwrap_or_else(|| "—".to_owned());
        s.push_str(&format!("| {id} | {role} | {task} | {st} | {hb} |\n"));
    }
    s
}

fn update_status_md(
    paths: &Paths,
    run_id: &str,
    mode_str: &str,
    now_iso: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let content = std::fs::read_to_string(&paths.status)
        .or_else(|_| std::fs::read_to_string(&paths.status_template))
        .unwrap_or_else(|_| "# STATUS\n\nПоследний тик: `—`\n\n## Метрики последних тиков\n\n## Активные сессии\n".to_owned());

    // Replace "Последний тик" line
    let new_header = format!("Последний тик: `{run_id}` · режим: `{mode_str}` · время: `{now_iso}`");
    let content = replace_last_tick_line(&content, &new_header);

    // Inject/replace metrics section
    let m = metrics::compute(&paths.hq, 20);
    let content = metrics::render_status(&content, &m, 20);

    // Inject/replace sessions section (идемпотентно, через тот же helper, что и метрики)
    let sessions = session::list_active(paths);
    let sessions_md = render_sessions_section(&sessions);
    let content = metrics::replace_section(&content, "## Активные сессии", &sessions_md);

    // Write atomically
    let tmp = PathBuf::from(format!("{}.{}.tmp", paths.status.display(), std::process::id()));
    std::fs::write(&tmp, &content)?;
    std::fs::rename(&tmp, &paths.status)?;
    Ok(())
}

fn replace_last_tick_line(content: &str, new_line: &str) -> String {
    if let Some(pos) = content.find("Последний тик:") {
        let end = content[pos..].find('\n').map(|i| pos + i).unwrap_or(content.len());
        format!("{}{}{}", &content[..pos], new_line, &content[end..])
    } else {
        content.to_owned()
    }
}

// ---------- automation.json ----------

fn is_paused(paths: &Paths) -> bool {
    let Ok(text) = std::fs::read_to_string(&paths.automation_json) else { return false; };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else { return false; };
    v.get("paused").and_then(|p| p.as_bool()).unwrap_or(false)
}

// ---------- tick.json init ----------

fn init_tick_json(
    run_dir: &Path,
    run_id: &str,
    mode_str: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let v = serde_json::json!({
        "run_id": run_id,
        "started": chrono::Utc::now().to_rfc3339(),
        "mode": mode_str,
        "mutations": []
    });
    let path = run_dir.join("tick.json");
    let json = serde_json::to_string_pretty(&v)?;
    let tmp = run_dir.join(format!("tick.json.{}.tmp", std::process::id()));
    std::fs::write(&tmp, &json)?;
    std::fs::rename(&tmp, &path)?;
    Ok(())
}

// ---------- main entry point ----------

pub fn run(hq: PathBuf, args: TickArgs) -> Result<(), Box<dyn std::error::Error>> {
    let paths = Paths::new(hq);
    std::fs::create_dir_all(&paths.runs)?;
    std::fs::create_dir_all(&paths.sessions_active)?;
    std::fs::create_dir_all(&paths.sessions_archive)?;

    // 0. Check pause
    if is_paused(&paths) {
        println!("tick: paused (automation.json) — новые спавны приостановлены");
        return Ok(());
    }

    // 1. Acquire lock
    acquire_lock(&paths.lock)?;
    let _lock = LockGuard::new(&paths.lock);

    // 2. Session GC
    let stale = session::gc_stale_sessions(&paths)?;
    if stale > 0 {
        println!("gc: архивировано {stale} stale-сессий");
    }

    // 3. Create run dir + tick.json. Миллисекунды (%3f) в run_id исключают коллизию двух
    //    тиков одного процесса в одну секунду (перезапись tick.json другого прогона).
    let run_id = format!(
        "TICK-{}-{}",
        chrono::Utc::now().format("%Y-%m-%d_%H-%M-%S-%3f"),
        std::process::id()
    );
    let run_dir = paths.runs.join(&run_id);
    std::fs::create_dir_all(&run_dir)?;
    let mode_str = args.mode.to_string();
    init_tick_json(&run_dir, &run_id, &mode_str)?;
    println!("tick: run={run_id} mode={mode_str}");

    // 4. Scan tasks
    let mut tasks = dispatch::scan_all_tasks(&paths);
    println!("tick: scanned {} task files", tasks.len());

    // 5. Recovery
    revert_stale_in_progress(&mut tasks, &run_dir)?;
    requeue_fix_needed(&mut tasks, &run_dir)?;

    // 6. Promote queued → ready
    promote_queued_to_ready(&mut tasks, &run_dir)?;

    // 7. Slot counts
    let plan_active = session::count_active_by_role(&paths, "plan");
    let exec_active = session::count_active_by_role(&paths, "exec");
    let review_active = session::count_active_by_role(&paths, "review");
    let plan_slots = args.max_plan.saturating_sub(plan_active);
    let exec_slots = args.max_exec.saturating_sub(exec_active);
    let review_slots = args.max_review.saturating_sub(review_active);

    // 8. Dispatch (mode=mock uses in-process workers; M3 will spawn real agents)
    match args.mode {
        TickMode::Mock => {
            // Plan phase
            let plan_candidates: Vec<_> = dispatch::select_for_dispatch(&tasks, "intake", plan_slots, args.max_per_repo).into_iter().cloned().collect();
            let mut planned = 0usize;
            for task in &plan_candidates {
                mock_plan(&paths, task, &run_dir)?;
                planned += 1;
            }

            // Exec phase (use updated in-memory tasks after promote). Доп. защита: повторно
            // проверяем deps_done — `done` терминален, поэтому это «ремни безопасности», но
            // дёшево и закрывает гонку, если граф зависимостей правят между тиками.
            let exec_candidates: Vec<_> = dispatch::select_for_dispatch(&tasks, "ready", exec_slots, args.max_per_repo)
                .into_iter()
                .filter(|t| dispatch::task_deps_done(t, &tasks))
                .cloned()
                .collect();
            let mut execed = 0usize;
            for task in &exec_candidates {
                mock_exec(&paths, task, &run_dir)?;
                execed += 1;
            }

            // Review phase
            let review_candidates: Vec<_> = dispatch::select_for_dispatch(&tasks, "in-review", review_slots, args.max_per_repo).into_iter().cloned().collect();
            let mut reviewed = 0usize;
            for task in &review_candidates {
                mock_review(&paths, task, &run_dir)?;
                reviewed += 1;
            }

            println!("tick done: planned={planned} exec={execed} reviewed={reviewed}");
        }
        TickMode::Assist | TickMode::AutoLow => {
            println!("tick: mode={mode_str} — live agents not implemented yet (M3)");
            println!("  intake={} ready={} in-review={}",
                tasks.iter().filter(|t| t.status == "intake").count(),
                tasks.iter().filter(|t| t.status == "ready").count(),
                tasks.iter().filter(|t| t.status == "in-review").count(),
            );
        }
    }

    // 9. Update STATUS.md
    let now_iso = chrono::Utc::now().to_rfc3339();
    update_status_md(&paths, &run_id, &mode_str, &now_iso)?;
    eprintln!("hq-conductor tick: STATUS.md обновлён");

    Ok(())
    // _lock drops here, releasing orchestrator/.lock
}
