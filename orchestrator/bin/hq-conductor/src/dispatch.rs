//! Task discovery and dispatch selection for `hq-conductor tick`.

use crate::fm::{fm_get, parse_fm};
use crate::state::{current_hostname, is_pid_alive, Paths};
use std::path::{Path, PathBuf};

// ---------- TaskInfo ----------

#[derive(Debug, Clone)]
pub struct TaskInfo {
    pub id: String,
    pub path: PathBuf,
    pub status: String,
    pub scope: String,
    pub priority: String,
    /// Parsed from `depends-on: [TASK-0001, TASK-0002]`
    pub depends_on: Vec<String>,
    pub fix_attempt: u32,
    pub assigned_to: Option<String>,
    pub lease_until: Option<chrono::DateTime<chrono::Utc>>,
    pub owner_pid: Option<u32>,
    pub owner_host: String,
}

/// Parse a YAML-like list scalar: `[A, B, C]` → `["A", "B", "C"]`
pub fn parse_list(s: &str) -> Vec<String> {
    let inner = s.trim().trim_start_matches('[').trim_end_matches(']').trim();
    if inner.is_empty() { return vec![]; }
    inner.split(',').map(|x| x.trim().to_owned()).filter(|x| !x.is_empty()).collect()
}

fn optional_str(pairs: &[(String, String)], key: &str) -> Option<String> {
    fm_get(pairs, key).filter(|s| s != "null" && !s.is_empty())
}

fn task_from_path(path: &Path) -> Option<TaskInfo> {
    let text = std::fs::read_to_string(path).ok()?;
    let (pairs, _) = parse_fm(&text);
    let id = fm_get(&pairs, "id")?;
    if fm_get(&pairs, "type").as_deref() != Some("task") { return None; }
    let status = fm_get(&pairs, "status").unwrap_or_default();
    let scope = fm_get(&pairs, "scope").unwrap_or_default();
    let priority = fm_get(&pairs, "priority").unwrap_or_else(|| "P2".to_owned());
    let depends_on = fm_get(&pairs, "depends-on").map(|s| parse_list(&s)).unwrap_or_default();
    let fix_attempt: u32 = optional_str(&pairs, "fix-attempt").and_then(|s| s.parse().ok()).unwrap_or(0);
    let lease_until = optional_str(&pairs, "lease-until")
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(&s).ok())
        .map(|t| t.to_utc());
    let owner_pid: Option<u32> = optional_str(&pairs, "owner-pid").and_then(|s| s.parse().ok());
    Some(TaskInfo {
        id,
        path: path.to_path_buf(),
        status,
        scope,
        priority,
        depends_on,
        fix_attempt,
        assigned_to: optional_str(&pairs, "assigned-to"),
        lease_until,
        owner_pid,
        owner_host: fm_get(&pairs, "owner-host").unwrap_or_default(),
    })
}

fn scan_dir(dir: &Path, out: &mut Vec<TaskInfo>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return; };
    for e in entries.flatten() {
        let p = e.path();
        if p.extension().and_then(|s| s.to_str()) != Some("md") { continue; }
        if !p.file_name().and_then(|s| s.to_str()).unwrap_or("").starts_with("TASK-") { continue; }
        if let Some(task) = task_from_path(&p) {
            out.push(task);
        }
    }
}

/// Scan all task dirs: `hq/tasks/`, `hq/orchestrator/tasks/`, `hq/projects/*/tasks/`.
pub fn scan_all_tasks(paths: &Paths) -> Vec<TaskInfo> {
    let mut tasks = Vec::new();
    scan_dir(&paths.tasks, &mut tasks);
    scan_dir(&paths.orch.join("tasks"), &mut tasks);
    if let Ok(projects) = std::fs::read_dir(paths.hq.join("projects")) {
        for proj in projects.flatten() {
            let proj_tasks = proj.path().join("tasks");
            if proj_tasks.is_dir() {
                scan_dir(&proj_tasks, &mut tasks);
            }
        }
    }
    tasks
}

// ---------- Claim helpers ----------

/// Is the task's claim free (no owner, or lease expired + PID confirmed dead on same host)?
pub fn task_is_free(task: &TaskInfo) -> bool {
    if task.assigned_to.is_none() { return true; }
    let lease_expired = task.lease_until.map(|t| chrono::Utc::now() > t).unwrap_or(true);
    if !lease_expired { return false; }
    // Fail-closed: only release if PID is confirmed dead on same host
    let same_host = task.owner_host.eq_ignore_ascii_case(&current_hostname());
    if !same_host { return false; }
    task.owner_pid.map(|p| !is_pid_alive(p)).unwrap_or(false)
}

// ---------- Dependency check ----------

/// Are all `depends-on` tasks in a terminal state (done / cancelled / rejected)?
pub fn task_deps_done(task: &TaskInfo, all: &[TaskInfo]) -> bool {
    if task.depends_on.is_empty() { return true; }
    task.depends_on.iter().all(|dep_id| {
        all.iter()
            .find(|t| &t.id == dep_id)
            .map(|t| matches!(t.status.as_str(), "done" | "cancelled" | "rejected"))
            .unwrap_or(false) // dep not found → not done (fail-closed)
    })
}

// ---------- Dispatch selection ----------

fn priority_ord(p: &str) -> u8 {
    match p { "P0" => 0, "P1" => 1, "P2" => 2, _ => 3 }
}

/// Select tasks for dispatch: filter by `target_status`, free claim, per-repo cap.
/// Returns up to `available_slots` tasks sorted by priority (P0 first).
pub fn select_for_dispatch<'a>(
    tasks: &'a [TaskInfo],
    target_status: &str,
    available_slots: usize,
    max_per_repo: usize,
) -> Vec<&'a TaskInfo> {
    if available_slots == 0 { return vec![]; }
    let mut eligible: Vec<&TaskInfo> = tasks
        .iter()
        .filter(|t| t.status == target_status && task_is_free(t))
        .collect();
    eligible.sort_by_key(|t| priority_ord(&t.priority));
    let mut repo_counts: std::collections::HashMap<String, usize> = Default::default();
    let mut selected = Vec::new();
    for task in eligible {
        if selected.len() >= available_slots { break; }
        let count = repo_counts.entry(task.scope.clone()).or_default();
        if *count < max_per_repo {
            selected.push(task);
            *count += 1;
        }
    }
    selected
}
