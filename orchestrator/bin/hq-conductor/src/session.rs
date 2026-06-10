use crate::fm::{fm_get, fm_set, parse_fm, render_fm};
use crate::state::{current_hostname, is_pid_alive, Paths};
use clap::{Args, Subcommand};
use std::path::{Path, PathBuf};

#[derive(Args)]
pub struct SessionArgs {
    #[command(subcommand)]
    pub action: SessionAction,
}

#[derive(Subcommand)]
pub enum SessionAction {
    /// Создать новую запись сессии
    New {
        #[arg(long)]
        task: String,
        #[arg(long)]
        role: String, // plan | exec | review
        #[arg(long)]
        model: String,
        #[arg(long)]
        repo: String,
        #[arg(long)]
        run_dir: String,
        #[arg(long)]
        worktree: Option<String>,
        #[arg(long)]
        branch: Option<String>,
        /// Lease duration in seconds (default 900)
        #[arg(long, default_value = "900")]
        lease_sec: u64,
    },
    /// Обновить heartbeat и продлить lease
    Heartbeat {
        #[arg(long)]
        id: String,
        #[arg(long, default_value = "900")]
        lease_sec: u64,
    },
    /// Закрыть сессию (done | failed) и переместить в _archive
    End {
        #[arg(long)]
        id: String,
        #[arg(long)]
        state: String, // done | failed
        #[arg(long)]
        note: Option<String>,
    },
    /// Список активных сессий
    List {
        #[arg(long)]
        json: bool,
    },
    /// Пометить зависшие сессии как stale (если lease истёк и PID мёртв)
    Gc,
}

// ---------- session file helpers ----------

fn session_path(dir: &Path, id: &str) -> PathBuf {
    dir.join(format!("{id}.md"))
}

fn write_atomic(path: &Path, content: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Уникальный tmp по PID: два писателя (heartbeat/gc/два тика) не делят один tmp-файл (гонка).
    let tmp = PathBuf::from(format!("{}.{}.tmp", path.display(), std::process::id()));
    std::fs::write(&tmp, content)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Санитизирует строку под класс `[0-9A-Za-z-]` (требование pattern в session.schema.json):
/// прочие символы (`_`, `.`, unicode и т.п.) → `-`.
fn sanitize_id_part(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '-' })
        .collect()
}

fn find_session(paths: &Paths, id: &str) -> Option<PathBuf> {
    let active = session_path(&paths.sessions_active, id);
    if active.exists() { return Some(active); }
    let arch = session_path(&paths.sessions_archive, id);
    if arch.exists() { return Some(arch); }
    None
}

/// Scan активных сессий. Возвращает (id, path, pairs).
fn list_active(paths: &Paths) -> Vec<SessionEntry> {
    let Ok(entries) = std::fs::read_dir(&paths.sessions_active) else { return vec![]; };
    let mut out = Vec::new();
    for e in entries.flatten() {
        let p = e.path();
        if p.extension().and_then(|s| s.to_str()) != Some("md") { continue; }
        let Ok(text) = std::fs::read_to_string(&p) else { continue; };
        let (pairs, _) = parse_fm(&text);
        let id = fm_get(&pairs, "id").unwrap_or_else(|| {
            p.file_stem().and_then(|s| s.to_str()).unwrap_or("?").to_owned()
        });
        out.push((id, p, pairs));
    }
    out
}

type SessionEntry = (String, PathBuf, Vec<(String, String)>);

// ---------- command handler ----------

pub fn run(hq: PathBuf, args: SessionArgs) -> Result<(), Box<dyn std::error::Error>> {
    let paths = Paths::new(hq);
    std::fs::create_dir_all(&paths.sessions_active)?;
    std::fs::create_dir_all(&paths.sessions_archive)?;

    match args.action {
        SessionAction::New { task, role, model, repo, run_dir, worktree, branch, lease_sec } => {
            let now = chrono::Utc::now();
            let run_basename_raw = Path::new(&run_dir)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("run");
            // id обязан соответствовать pattern схемы: SESS-TASK-[0-9]{4}-[0-9A-Za-z-]+
            let run_basename = sanitize_id_part(run_basename_raw);
            let task_short = sanitize_id_part(&task.replace("TASK-", ""));
            let id = format!("SESS-TASK-{task_short}-{run_basename}");
            let lease_until = now + chrono::Duration::seconds(lease_sec as i64);

            let worktree_val = worktree.as_deref().unwrap_or("null");
            let branch_val = branch.as_deref().unwrap_or("null");

            let content = format!(
                "---\nid: {id}\ntype: session\ntask: {task}\nrole: {role}\nprovider: claude\n\
                 model: {model}\nstate: running\nrepo: {repo}\nworktree: {worktree_val}\n\
                 branch: {branch_val}\nremote: null\nrun-dir: {run_dir}\n\
                 lease-until: {lease_until}\nlast-heartbeat: {now}\nstarted: {now}\nended: null\n\
                 owner-pid: {pid}\nowner-host: {host}\n---\n\n\
                 ## Milestones\n\n## Decisions\n\n## Handoff\n\n## Next\n",
                lease_until = lease_until.to_rfc3339(),
                now = now.to_rfc3339(),
                pid = std::process::id(),
                host = current_hostname(),
            );
            let path = session_path(&paths.sessions_active, &id);
            write_atomic(&path, &content)?;
            println!("{id}");
        }

        SessionAction::Heartbeat { id, lease_sec } => {
            // Heartbeat — только для активных сессий: «оживлять» завершённую (архивную) нельзя.
            let path = session_path(&paths.sessions_active, &id);
            if !path.exists() {
                return Err(format!("активная сессия не найдена: {id} (завершённую нельзя heartbeat'ить)").into());
            }
            let content = std::fs::read_to_string(&path)?;
            let (mut pairs, body_start) = parse_fm(&content);
            let body = &content[body_start..];
            let now = chrono::Utc::now();
            let lease_until = now + chrono::Duration::seconds(lease_sec as i64);
            fm_set(&mut pairs, "last-heartbeat", &now.to_rfc3339());
            fm_set(&mut pairs, "lease-until", &lease_until.to_rfc3339());
            write_atomic(&path, &render_fm(&pairs, body))?;
            println!("heartbeat: {id} lease→{}", lease_until.to_rfc3339());
        }

        SessionAction::End { id, state, note } => {
            let path = find_session(&paths, &id)
                .ok_or_else(|| format!("сессия не найдена: {id}"))?;
            if !path.starts_with(&paths.sessions_active) {
                eprintln!("сессия уже в архиве: {id}");
                return Ok(());
            }
            let content = std::fs::read_to_string(&path)?;
            let (mut pairs, body_start) = parse_fm(&content);
            let mut body = content[body_start..].to_owned();
            let now = chrono::Utc::now();
            fm_set(&mut pairs, "state", &state);
            fm_set(&mut pairs, "ended", &now.to_rfc3339());
            if let Some(note_text) = note {
                body.push_str(&format!("\n## End note\n{note_text}\n"));
            }
            let dest = session_path(&paths.sessions_archive, &id);
            write_atomic(&dest, &render_fm(&pairs, &body))?;
            std::fs::remove_file(&path)?;
            println!("ended: {id} → {state} (archived)");
        }

        SessionAction::List { json } => {
            let sessions = list_active(&paths);
            if json {
                let items: Vec<serde_json::Value> = sessions
                    .iter()
                    .map(|(id, _, pairs)| {
                        let mut obj = serde_json::Map::new();
                        for (k, v) in pairs {
                            // Литерал "null"/пусто → JSON null (для чистого потребления в /hq-status).
                            let val = if v == "null" || v.is_empty() {
                                serde_json::Value::Null
                            } else {
                                serde_json::Value::String(v.clone())
                            };
                            obj.insert(k.clone(), val);
                        }
                        obj.insert("id".to_owned(), serde_json::Value::String(id.clone()));
                        serde_json::Value::Object(obj)
                    })
                    .collect();
                println!("{}", serde_json::to_string_pretty(&items)?);
            } else if sessions.is_empty() {
                println!("(нет активных сессий)");
            } else {
                println!("{:<40} {:<8} {:<10} {:<10} heartbeat", "ID", "role", "task", "state");
                for (id, _, pairs) in &sessions {
                    let role = fm_get(pairs, "role").unwrap_or_default();
                    let task = fm_get(pairs, "task").unwrap_or_default();
                    let state = fm_get(pairs, "state").unwrap_or_default();
                    let hb = fm_get(pairs, "last-heartbeat").unwrap_or_else(|| "—".to_owned());
                    println!("{:<40} {:<8} {:<10} {:<10} {}", id, role, task, state, hb);
                }
            }
        }

        SessionAction::Gc => {
            let sessions = list_active(&paths);
            let mut stale_count = 0u32;
            for (id, path, pairs) in &sessions {
                let lease_expired = fm_get(pairs, "lease-until")
                    .as_deref()
                    .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    .map(|t| chrono::Utc::now() > t.to_utc())
                    .unwrap_or(true);
                if !lease_expired { continue; }

                let owner_host = fm_get(pairs, "owner-host").unwrap_or_default();
                let owner_pid: Option<u32> = fm_get(pairs, "owner-pid")
                    .and_then(|s| s.parse().ok());
                let same_host = owner_host.eq_ignore_ascii_case(&current_hostname());
                let pid_dead = if same_host {
                    owner_pid.map(|p| !is_pid_alive(p)).unwrap_or(false)
                } else {
                    false
                };

                if lease_expired && pid_dead {
                    // Пометить как stale и архивировать
                    let content = std::fs::read_to_string(path)?;
                    let (mut fm_pairs, body_start) = parse_fm(&content);
                    let body = &content[body_start..];
                    fm_set(&mut fm_pairs, "state", "stale");
                    fm_set(&mut fm_pairs, "ended", &chrono::Utc::now().to_rfc3339());
                    let dest = session_path(&paths.sessions_archive, id);
                    write_atomic(&dest, &render_fm(&fm_pairs, body))?;
                    std::fs::remove_file(path)?;
                    println!("stale→archived: {id}");
                    stale_count += 1;
                } else {
                    eprintln!("lease_expired but can't confirm death (fail-closed): {id}");
                }
            }
            if stale_count == 0 {
                println!("gc: нет stale-сессий");
            } else {
                println!("gc: архивировано {stale_count} stale-сессий");
            }
        }
    }
    Ok(())
}
