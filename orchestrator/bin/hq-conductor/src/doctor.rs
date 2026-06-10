use crate::state::{self, LockInfo, Paths};
use clap::Args;
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use vcs_jj::{Jj, JjApi};

#[derive(Args)]
pub struct DoctorArgs {
    /// Вывести JSON вместо текста
    #[arg(long)]
    pub json: bool,
}

#[derive(Serialize, Debug)]
pub struct Finding {
    pub level: Level,
    pub category: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub safe_resume: Option<String>,
}

#[derive(Serialize, Debug)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)]
pub enum Level {
    Info,
    Warning,
    Error,
}

#[derive(Serialize, Debug)]
pub struct OrphanedWs {
    pub repo: String,
    pub workspace: String,
    pub run_dir: Option<String>,
    pub note: String,
}

#[derive(Serialize, Debug, Default)]
pub struct Report {
    pub findings: Vec<Finding>,
    pub orphaned_workspaces: Vec<OrphanedWs>,
}

fn scan_locks(paths: &Paths, report: &mut Report) {
    for (name, path) in [(".lock", &paths.lock), (".lock5", &paths.lock5)] {
        if !path.exists() { continue; }
        match LockInfo::read(path) {
            None => {
                report.findings.push(Finding {
                    level: Level::Warning,
                    category: format!("lock/{name}"),
                    message: format!("замок существует но не парсится: {}", path.display()),
                    safe_resume: Some(format!("Remove-Item -Force '{}'", path.display())),
                });
            }
            Some(lock) => {
                let alive = lock.is_pid_alive();
                let stale = lock.is_stale();
                if !alive || stale {
                    report.findings.push(Finding {
                        level: Level::Warning,
                        category: format!("lock/{name}"),
                        message: format!(
                            "замок PID={} ({}) — alive={alive} stale={stale}",
                            lock.pid, lock.started_iso
                        ),
                        safe_resume: Some(format!("Remove-Item -Force '{}'", path.display())),
                    });
                } else {
                    report.findings.push(Finding {
                        level: Level::Info,
                        category: format!("lock/{name}"),
                        message: format!("замок активен PID={}", lock.pid),
                        safe_resume: None,
                    });
                }
            }
        }
    }
}

/// Возвращает (repo, workspace, run_dir_path) для прогонов без land-result.json.
fn scan_orphaned_candidates(paths: &Paths) -> Vec<(String, String, String)> {
    let Ok(entries) = std::fs::read_dir(&paths.runs) else { return vec![]; };
    let mut candidates: Vec<(String, String, String)> = Vec::new();
    let mut seen: HashSet<(String, String)> = HashSet::new();

    for entry in entries.flatten() {
        let run_dir = entry.path();
        if !run_dir.is_dir() { continue; }

        let files = state::walk_files(&run_dir);
        let has_land = files.iter().any(|f| {
            f.file_name().and_then(|n| n.to_str()) == Some("land-result.json")
        });
        if has_land { continue; } // прогон завершён

        for f in &files {
            if f.file_name().and_then(|n| n.to_str()) != Some("summary.json") { continue; }
            let Ok(text) = std::fs::read_to_string(f) else { continue; };
            let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else { continue; };
            if v.get("integrated").is_some() { continue; } // integ-summary — пропустить
            let Some(ws) = v["workspace"].as_str() else { continue; };
            let Some(repo) = v["repo"].as_str() else { continue; };
            let key = (repo.to_owned(), ws.to_owned());
            if seen.insert(key) {
                candidates.push((
                    repo.to_owned(),
                    ws.to_owned(),
                    run_dir.to_string_lossy().into_owned(),
                ));
            }
        }
    }
    candidates
}

pub async fn run(hq: PathBuf, args: DoctorArgs) -> Result<(), Box<dyn std::error::Error>> {
    let paths = Paths::new(hq.clone());
    let personal = paths.personal().to_path_buf();
    let mut report = Report::default();

    // 1. Замки
    scan_locks(&paths, &mut report);

    // 2. Незавершённые прогоны → кандидаты на осиротевшие workspaces
    let candidates = scan_orphaned_candidates(&paths);

    // 3. Живые workspaces через vcs-jj (read-only)
    let jj = Jj::new();
    let mut repos_checked: HashSet<String> = HashSet::new();
    let mut live_ws: HashMap<String, Vec<String>> = HashMap::new();

    for (repo, _, _) in &candidates {
        if repos_checked.insert(repo.clone()) {
            let repo_path = personal.join(repo);
            if !repo_path.join(".jj").is_dir() { continue; }
            match jj.workspace_list(&repo_path).await {
                Ok(wss) => {
                    let names: Vec<String> = wss.iter()
                        .filter(|w| w.name != "default")
                        .map(|w| w.name.clone())
                        .collect();
                    live_ws.insert(repo.clone(), names);
                }
                Err(e) => {
                    report.findings.push(Finding {
                        level: Level::Warning,
                        category: format!("jj/{repo}"),
                        message: format!("workspace_list: {e}"),
                        safe_resume: None,
                    });
                }
            }
        }
    }

    // 4. Сопоставить кандидатов с живыми workspaces
    for (repo, ws, run_dir) in &candidates {
        let live = live_ws.get(repo).map(|v| v.iter().any(|n| n == ws)).unwrap_or(false);
        let note = if live { "живой workspace без land-result" } else { "workspace уже удалён" };
        let run_name = std::path::Path::new(run_dir)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(run_dir.as_str());

        report.findings.push(Finding {
            level: if live { Level::Warning } else { Level::Info },
            category: format!("workspace/{repo}"),
            message: format!("{repo}/{ws}: {note} (run: {run_name})"),
            safe_resume: if live {
                Some(format!(
                    "Push-Location '{}'; jj workspace forget {ws}; Pop-Location",
                    personal.join(repo).display()
                ))
            } else {
                None
            },
        });

        if live {
            report.orphaned_workspaces.push(OrphanedWs {
                repo: repo.clone(),
                workspace: ws.clone(),
                run_dir: Some(run_dir.clone()),
                note: note.to_owned(),
            });
        }
    }

    if report.findings.is_empty() {
        report.findings.push(Finding {
            level: Level::Info,
            category: "summary".to_owned(),
            message: "дрейф не обнаружен".to_owned(),
            safe_resume: None,
        });
    }

    if args.json {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        println!("=== doctor report ===");
        for f in &report.findings {
            let tag = match f.level {
                Level::Info => "[INFO]",
                Level::Warning => "[WARN]",
                Level::Error => "[ERR!]",
            };
            println!("  {tag} [{}] {}", f.category, f.message);
            if let Some(fix) = &f.safe_resume {
                println!("       resume: {fix}");
            }
        }
        if !report.orphaned_workspaces.is_empty() {
            println!("\nОсиротевшие workspaces:");
            for o in &report.orphaned_workspaces {
                println!("  {}/{}", o.repo, o.workspace);
            }
        }
    }
    Ok(())
}
