use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Args)]
pub struct JournalArgs {
    /// Директория прогона (_runs/<run_id>/)
    #[arg(long)]
    pub run_dir: PathBuf,
    #[command(subcommand)]
    pub action: JournalAction,
}

#[derive(Subcommand)]
pub enum JournalAction {
    /// Записать намерение мутации (applied=false) → печатает ID
    Record {
        #[arg(long)]
        r#type: String,
        #[arg(long)]
        target: String,
        /// Дополнительные детали (JSON-строка)
        #[arg(long)]
        details: Option<String>,
    },
    /// Пометить мутацию как выполненную (applied=true)
    MarkApplied {
        #[arg(long)]
        id: String,
    },
    /// Показать все мутации прогона
    List,
    /// Показать невыполненные (applied=false) — для идемпотентного replay
    Replay,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Mutation {
    pub id: String,
    pub r#type: String,
    pub target: String,
    pub applied: bool,
    #[serde(default, skip_serializing_if = "serde_json::Value::is_null")]
    pub details: serde_json::Value,
}

fn tick_path(run_dir: &Path) -> PathBuf {
    run_dir.join("tick.json")
}

use std::path::Path;

/// Загружает tick.json как serde_json::Value. Если нет — создаёт минимальный.
fn load_tick(run_dir: &Path) -> serde_json::Value {
    let path = tick_path(run_dir);
    if path.exists() {
        if let Ok(text) = std::fs::read_to_string(&path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                return v;
            }
        }
    }
    let run_id = run_dir
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");
    serde_json::json!({
        "run_id": run_id,
        "started": "",
        "mode": "live",
        "scanned": [],
        "skipped": [],
        "triaged": [],
        "planned": [],
        "errors": [],
        "mutations": []
    })
}

/// Атомарная запись tick.json.
fn save_tick(run_dir: &Path, v: &serde_json::Value) -> Result<(), Box<dyn std::error::Error>> {
    let path = tick_path(run_dir);
    std::fs::create_dir_all(run_dir)?;
    let json = serde_json::to_string_pretty(v)?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, &json)?;
    std::fs::rename(&tmp, &path)?;
    Ok(())
}

fn get_mutations(v: &serde_json::Value) -> Vec<Mutation> {
    v.get("mutations")
        .and_then(|m| serde_json::from_value(m.clone()).ok())
        .unwrap_or_default()
}

fn next_id(mutations: &[Mutation]) -> String {
    format!("mut-{:03}", mutations.len() + 1)
}

pub fn run(_hq: PathBuf, args: JournalArgs) -> Result<(), Box<dyn std::error::Error>> {
    let run_dir = &args.run_dir;
    match args.action {
        JournalAction::Record { r#type, target, details } => {
            let mut tick = load_tick(run_dir);
            let mut mutations = get_mutations(&tick);
            let id = next_id(&mutations);
            let details_val = details
                .as_deref()
                .map(|s| serde_json::from_str(s)
                    .unwrap_or_else(|_| serde_json::Value::String(s.to_owned())))
                .unwrap_or(serde_json::Value::Null);
            mutations.push(Mutation { id: id.clone(), r#type, target, applied: false, details: details_val });
            tick["mutations"] = serde_json::to_value(&mutations)?;
            save_tick(run_dir, &tick)?;
            // Выводим только ID — caller может использовать его для mark-applied
            println!("{id}");
        }

        JournalAction::MarkApplied { id } => {
            let mut tick = load_tick(run_dir);
            let mut mutations = get_mutations(&tick);
            let m = mutations.iter_mut()
                .find(|m| m.id == id)
                .ok_or_else(|| format!("mutation not found: {id}"))?;
            m.applied = true;
            tick["mutations"] = serde_json::to_value(&mutations)?;
            save_tick(run_dir, &tick)?;
            println!("marked applied: {id}");
        }

        JournalAction::List => {
            let tick = load_tick(run_dir);
            let mutations = get_mutations(&tick);
            if mutations.is_empty() {
                println!("(нет мутаций)");
            } else {
                println!("{:<12} {:<14} {:<32} applied", "ID", "type", "target");
                for m in &mutations {
                    println!("{:<12} {:<14} {:<32} {}", m.id, m.r#type, m.target, m.applied);
                }
            }
        }

        JournalAction::Replay => {
            let tick = load_tick(run_dir);
            let mutations = get_mutations(&tick);
            let pending: Vec<&Mutation> = mutations.iter().filter(|m| !m.applied).collect();
            if pending.is_empty() {
                println!("(нет ожидающих мутаций — прогон идемпотентен)");
            } else {
                println!("Ожидают исполнения ({}):", pending.len());
                for m in pending {
                    println!("  {} {} {}", m.id, m.r#type, m.target);
                }
            }
        }
    }
    Ok(())
}
