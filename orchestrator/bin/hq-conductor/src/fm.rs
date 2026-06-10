//! Общие хелперы для плоского YAML-frontmatter задач/сессий.
//! Простой парсер «ключ: значение» (не полный YAML) — достаточно для frontmatter
//! без вложенности. Используется claim.rs и session.rs (единый источник, без дрейфа).
//!
//! ВАЖНО (контракт): frontmatter должен быть **машинным** и плоским. Парсер по дизайну
//! НЕ сохраняет standalone-комментарии (`# ...`), пустые строки и порядок при round-trip
//! (`fm_set` дописывает новые ключи в конец). Все штатные писатели (add-task.ps1, planner,
//! conductor) генерируют чистый плоский FM, поэтому потери нет. Не класть в claim-/session-
//! файлы многострочные значения или ручные комментарии — они не переживут первый claim/heartbeat.

/// Парсит frontmatter: пары (key, value) + позиция начала тела (сразу после закрывающего `---`).
/// Комментарии (строки, начинающиеся с `#`) и пустые строки пропускаются. Значение —
/// всё после первого `:` (пути/URL/таймстемпы с `:` сохраняются целиком).
/// Возвращаемый `body_start` — байтовый offset в ОРИГИНАЛЬНОМ `content` (с учётом BOM).
/// CRLF переносится в тело как есть; `\r` в строках FM срезается `.trim()`.
pub fn parse_fm(content: &str) -> (Vec<(String, String)>, usize) {
    // Защитно: срезаем UTF-8 BOM, если редактор его добавил (иначе starts_with("---") = false
    // и весь frontmatter молча проигнорируется).
    let bom_len = if content.starts_with('\u{feff}') { '\u{feff}'.len_utf8() } else { 0 };
    let body = &content[bom_len..];
    let after_open = match body.strip_prefix("---") {
        Some(s) => s,
        None => return (vec![], 0),
    };
    let close = match after_open.find("\n---") {
        Some(i) => i,
        None => return (vec![], 0),
    };
    let fm_text = &after_open[..close];
    // body_start = BOM + len("---") + close + len("\n---")
    let body_start = bom_len + (body.len() - after_open.len()) + close + 4;

    let pairs: Vec<(String, String)> = fm_text
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                return None;
            }
            let (k, v) = line.split_once(':')?;
            Some((k.trim().to_owned(), v.trim().to_owned()))
        })
        .collect();

    (pairs, body_start.min(content.len()))
}

/// Рендерит frontmatter + тело обратно в строку.
pub fn render_fm(pairs: &[(String, String)], body: &str) -> String {
    let mut s = String::from("---\n");
    for (k, v) in pairs {
        s.push_str(k);
        s.push_str(": ");
        s.push_str(v);
        s.push('\n');
    }
    s.push_str("---");
    s.push_str(body);
    s
}

pub fn fm_get(pairs: &[(String, String)], key: &str) -> Option<String> {
    pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone())
}

pub fn fm_set(pairs: &mut Vec<(String, String)>, key: &str, val: &str) {
    if let Some(pos) = pairs.iter().position(|(k, _)| k == key) {
        pairs[pos].1 = val.to_owned();
    } else {
        pairs.push((key.to_owned(), val.to_owned()));
    }
}

pub fn fm_remove(pairs: &mut Vec<(String, String)>, key: &str) {
    pairs.retain(|(k, _)| k != key);
}
