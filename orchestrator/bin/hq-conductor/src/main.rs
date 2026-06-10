mod claim;
mod doctor;
mod journal;
mod metrics;
mod session;
mod state;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "hq-conductor", about = "Дирижёр .hq (P6)")]
struct Cli {
    /// Корень .hq (по умолчанию — поиск вверх от cwd)
    #[arg(long, global = true)]
    hq: Option<PathBuf>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Метрики последних тиков §11.8 (S1)
    Metrics(metrics::MetricsArgs),
    /// Recovery-probe: замки, прогоны, воркспейсы (S2, read-only)
    Doctor(doctor::DoctorArgs),
    /// Lease/claim на задачу (S3)
    Claim(claim::ClaimArgs),
    /// Идемпотентный журнал мутаций tick.json (S3)
    Journal(journal::JournalArgs),
    /// Управление сессиями агентов (M1)
    Session(session::SessionArgs),
}

#[tokio::main]
async fn main() {
    if let Err(e) = run().await {
        eprintln!("hq-conductor: {e}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let hq = match cli.hq.or_else(state::find_hq_root) {
        Some(p) => p,
        None => return Err("не найден корень .hq (используй --hq <path>)".into()),
    };
    match cli.cmd {
        Cmd::Metrics(a) => metrics::run(hq, a)?,
        Cmd::Doctor(a) => doctor::run(hq, a).await?,
        Cmd::Claim(a) => claim::run(hq, a)?,
        Cmd::Journal(a) => journal::run(hq, a)?,
        Cmd::Session(a) => session::run(hq, a)?,
    }
    Ok(())
}
