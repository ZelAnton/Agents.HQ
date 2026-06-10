use crate::state::{self, Paths};
use clap::Args;
use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Args)]
pub struct MetricsArgs {
    /// Количество последних прогонов в окне
    #[arg(long, default_value = "20")]
    pub window: usize,
    /// Вывести JSON вместо текста
    #[arg(long)]
    pub json: bool,
    /// Записать STATUS.md (или указанный путь)
    #[arg(long)]
    pub out: Option<PathBuf>,
}

#[derive(Serialize, Default, Clone)]
pub struct Metrics {
    pub window_runs: usize,
    /// Среднее задач на тик (знаменатель — только тики с задачами)
    pub tasks_per_tick: Option<f64>,
    /// % тасков с gate_tests=true
    pub tests_green_pct: Option<f64>,
    /// % тиков с непустым conflicts_resolved
    pub conflict_pct: Option<f64>,
    /// % конфликтных тиков, которые авто-resolve-нули → auto-landed
    pub conflict_auto_resolved_pct: Option<f64>,
    /// % тиков с land-action=escalated (от тиков с land-result)
    pub escalation_pct: Option<f64>,
    /// % тиков с land-action=reverted
    pub revert_pct: Option<f64>,
    /// % тиков с land-action=auto-landed
    pub auto_land_pct: Option<f64>,
    /// Среднее время тика в секундах (только где есть tick.json + mtime)
    pub avg_task_sec: Option<f64>,
    /// Токены/тик — null до S5
    pub tokens_per_tick: Option<f64>,
}

struct RunStats {
    task_count: usize,
    tasks_green: usize,
    had_conflict: bool,
    conflict_auto_resolved: bool,
    land_action: Option<String>,
    elapsed_sec: Option<f64>,
}

fn pct(count: usize, total: usize) -> Option<f64> {
    if total == 0 { None } else { Some(count as f64 / total as f64 * 100.0) }
}

fn fmt_pct(v: Option<f64>) -> String {
    match v {
        None => "null".to_owned(),
        Some(x) => format!("{:.1}%", x),
    }
}

fn fmt_num(v: Option<f64>, unit: &str) -> String {
    match v {
        None => "null".to_owned(),
        Some(x) => format!("{:.1}{}", x, unit),
    }
}

/// Собирает статистику одного прогона из его директории.
/// Возвращает None если директория не содержит осмысленных данных.
fn collect_run(dir: &Path) -> Option<RunStats> {
    let files = state::walk_files(dir);
    let mut task_count = 0usize;
    let mut tasks_green = 0usize;
    let mut had_conflict = false;
    let mut land_action: Option<String> = None;
    let mut started_ms: Option<u128> = None;
    let mut last_ms: Option<u128> = None;

    for path in &files {
        let fname = path.file_name().and_then(|f| f.to_str()).unwrap_or("");

        if fname == "summary.json" {
            if let Ok(text) = std::fs::read_to_string(path) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                    // exec-summary: поле gate_tests без поля integrated
                    if v.get("gate_tests").is_some() && v.get("integrated").is_none() {
                        task_count += 1;
                        if v["gate_tests"].as_bool().unwrap_or(false) {
                            tasks_green += 1;
                        }
                    }
                    // integ-summary: поле integrated + conflicts_resolved
                    if v.get("integrated").is_some() {
                        if let Some(cr) = v.get("conflicts_resolved").and_then(|v| v.as_array()) {
                            if !cr.is_empty() {
                                had_conflict = true;
                            }
                        }
                    }
                }
            }
        }

        if fname == "land-result.json" {
            if let Ok(text) = std::fs::read_to_string(path) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(a) = v["action"].as_str() {
                        land_action = Some(a.to_owned());
                    }
                }
            }
        }

        // tick.json — источник started для elapsed
        if fname == "tick.json" {
            if let Ok(text) = std::fs::read_to_string(path) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(s) = v["started"].as_str() {
                        if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(s) {
                            started_ms = Some(dt.timestamp_millis() as u128);
                        }
                    }
                }
            }
        }

        // Отслеживать последнее mtime для elapsed
        if let Ok(meta) = std::fs::metadata(path) {
            if let Ok(mt) = meta.modified() {
                let ms = mt
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis();
                last_ms = Some(last_ms.map_or(ms, |prev: u128| prev.max(ms)));
            }
        }
    }

    if task_count == 0 && land_action.is_none() {
        return None;
    }

    let elapsed_sec = started_ms.zip(last_ms).map(|(s, l)| {
        if l > s { (l - s) as f64 / 1000.0 } else { 0.0 }
    });

    // Конфликт авто-разрешён только если were conflicts AND land action was auto-landed
    let conflict_auto_resolved = had_conflict && land_action.as_deref() == Some("auto-landed");

    Some(RunStats { task_count, tasks_green, had_conflict, conflict_auto_resolved, land_action, elapsed_sec })
}

/// Вычисляет §11.8 метрики по `window` последних прогонов.
pub fn compute(hq: &Path, window: usize) -> Metrics {
    let paths = Paths::new(hq.to_path_buf());
    let run_dirs = state::list_run_dirs(&paths.runs, window);
    let stats: Vec<RunStats> = run_dirs.iter().filter_map(|d| collect_run(d)).collect();

    let total = stats.len();
    if total == 0 {
        return Metrics { window_runs: 0, ..Default::default() };
    }

    let total_tasks: usize = stats.iter().map(|s| s.task_count).sum();
    let total_green: usize = stats.iter().map(|s| s.tasks_green).sum();
    let total_task_runs: usize = stats.iter().filter(|s| s.task_count > 0).count();

    let runs_with_conflict = stats.iter().filter(|s| s.had_conflict).count();
    let runs_conflict_auto = stats.iter().filter(|s| s.conflict_auto_resolved).count();
    let runs_with_land = stats.iter().filter(|s| s.land_action.is_some()).count();
    let runs_escalated = stats.iter().filter(|s| s.land_action.as_deref() == Some("escalated")).count();
    let runs_reverted = stats.iter().filter(|s| s.land_action.as_deref() == Some("reverted")).count();
    let runs_landed = stats.iter().filter(|s| s.land_action.as_deref() == Some("auto-landed")).count();

    let elapsed_vals: Vec<f64> = stats.iter().filter_map(|s| s.elapsed_sec).collect();
    let avg_task_sec = if elapsed_vals.is_empty() {
        None
    } else {
        Some(elapsed_vals.iter().sum::<f64>() / elapsed_vals.len() as f64)
    };

    Metrics {
        window_runs: total,
        tasks_per_tick: if total_task_runs == 0 { None } else { Some(total_tasks as f64 / total_task_runs as f64) },
        tests_green_pct: pct(total_green, total_tasks),
        conflict_pct: pct(runs_with_conflict, total),
        // Знаменатель = тики с конфликтами; 0 → null (честный fail-closed)
        conflict_auto_resolved_pct: pct(runs_conflict_auto, runs_with_conflict),
        // Знаменатель = тики с land-result; 0 → null
        escalation_pct: pct(runs_escalated, runs_with_land),
        revert_pct: pct(runs_reverted, runs_with_land),
        auto_land_pct: pct(runs_landed, runs_with_land),
        avg_task_sec,
        tokens_per_tick: None, // usage не персистируется до S5
    }
}

/// Заменяет (или дописывает) markdown-секцию, начинающуюся со строки `header_prefix`
/// (например `## Метрики`), на `new_section` (его первая строка — полный заголовок).
/// Идемпотентна: повторный вызов на своём же выводе даёт тот же результат. Сохраняет
/// разделитель (пустую строку) перед следующей секцией. Корректно обрабатывает заголовок
/// в самом начале файла (без ведущего `\n`).
///
/// ИНВАРИАНТ: `new_section` НЕ должен содержать строк, начинающихся с `## `, кроме самого
/// заголовка — иначе следующий вызов воспримет внутренний `## ` за границу секции и
/// продублирует хвост (идемпотентность сломается). Все штатные вызовы (метрики: строки `- `;
/// сессии: строки таблицы `| |`) этому удовлетворяют.
pub fn replace_section(content: &str, header_prefix: &str, new_section: &str) -> String {
    let start = if content.starts_with(header_prefix) {
        Some(0)
    } else {
        content.find(&format!("\n{header_prefix}")).map(|i| i + 1)
    };
    let Some(start) = start else {
        // не найдено → дописать в конец с пустой строкой-разделителем
        return format!("{}\n\n{}\n", content.trim_end(), new_section.trim_end());
    };
    // Найти начало следующей секции (строка, начинающаяся с "## ") после текущего заголовка.
    let search_from = start + header_prefix.len();
    let next = content[search_from..].find("\n## ").map(|i| search_from + i);
    let mut out = String::new();
    out.push_str(&content[..start]); // всё до заголовка (его \n-разделитель уже здесь)
    out.push_str(new_section.trim_end());
    out.push('\n');
    if let Some(n) = next {
        out.push('\n'); // пустая строка-разделитель перед следующей секцией
        out.push_str(content[n..].trim_start_matches('\n'));
    }
    out
}

/// Заменяет секцию `## Метрики` в содержимом STATUS.
pub fn render_status(content: &str, m: &Metrics, window: usize) -> String {
    let section = format!(
        "## Метрики последних тиков (окно: {} прогонов)\n\
         - задач/тик: {} · % зелёных тестов: {} · конфликты: {} (авто-разрешено: {})\n\
         - % эскалаций: {} · % откатов: {} · доля авто-land: {} · токены/тик: null",
        window,
        fmt_num(m.tasks_per_tick, ""),
        fmt_pct(m.tests_green_pct),
        fmt_pct(m.conflict_pct),
        fmt_pct(m.conflict_auto_resolved_pct),
        fmt_pct(m.escalation_pct),
        fmt_pct(m.revert_pct),
        fmt_pct(m.auto_land_pct),
    );
    replace_section(content, "## Метрики", &section)
}

/// Атомарная запись: write to .tmp, rename.
fn write_atomic(path: &Path, content: &str) -> std::io::Result<()> {
    let tmp = path.with_extension("md.tmp");
    std::fs::write(&tmp, content)?;
    std::fs::rename(&tmp, path)
}

pub fn run(hq: PathBuf, args: MetricsArgs) -> Result<(), Box<dyn std::error::Error>> {
    let m = compute(&hq, args.window);
    let paths = Paths::new(hq.clone());

    if args.json {
        println!("{}", serde_json::to_string_pretty(&m)?);
        return Ok(());
    }

    if let Some(out_path) = &args.out {
        let out_path = if out_path.as_os_str() == "STATUS.md" {
            paths.status.clone()
        } else {
            out_path.clone()
        };
        // Читаем шаблон или текущий файл
        let template = std::fs::read_to_string(&paths.status_template)
            .or_else(|_| std::fs::read_to_string(&out_path))
            .unwrap_or_default();
        let rendered = render_status(&template, &m, args.window);
        write_atomic(&out_path, &rendered)?;
        eprintln!("hq-conductor metrics: записано в {}", out_path.display());
        return Ok(());
    }

    // Human-readable stdout
    println!("=== Метрики (окно {} прогонов) ===", args.window);
    println!("  window_runs:                {}", m.window_runs);
    println!("  tasks_per_tick:             {}", fmt_num(m.tasks_per_tick, ""));
    println!("  tests_green_pct:            {}", fmt_pct(m.tests_green_pct));
    println!("  conflict_pct:               {}", fmt_pct(m.conflict_pct));
    println!("  conflict_auto_resolved_pct: {}", fmt_pct(m.conflict_auto_resolved_pct));
    println!("  escalation_pct:             {}", fmt_pct(m.escalation_pct));
    println!("  revert_pct:                 {}", fmt_pct(m.revert_pct));
    println!("  auto_land_pct:              {}", fmt_pct(m.auto_land_pct));
    println!("  avg_task_sec:               {}", fmt_num(m.avg_task_sec, "s"));
    println!("  tokens_per_tick:            null (S5+)");
    Ok(())
}
