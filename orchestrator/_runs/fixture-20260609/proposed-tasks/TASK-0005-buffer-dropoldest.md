---
id: TASK-0005
type: task
title: ProcessKit-rs — политика буфера DropOldest (src/buffer.rs)
date: 2026-06-09
scope: ProcessKit-rs
status: queued
priority: P2
repos: [ProcessKit-rs]
depends-on: []
parallel-safe-with: [TASK-0008, TASK-0009]
assigned-to: null
origin: T-fixture-sample#00 (ФИКСТУРА — пример, не реальная задача)
---

## Цель
Добавить в буфер стриминга (`src/buffer.rs`) аддитивный enum-вариант политики переполнения
`DropOldest`, не меняя дефолтное поведение.

## Объём (scope)
- Только `src/buffer.rs`.

## Что сделать
1. Ввести/расширить публичный enum политики буфера новым вариантом `DropOldest` (дефолт — текущий drop-newest).
2. Реализовать логику `DropOldest`: при переполнении ронять самые старые строки, сохраняя хвост.
3. Дефолтный режим не менять; сигнатуры существующих типов/методов не трогать (только добавлять).

## Критерии готовности (DoD)
- [ ] Вариант `DropOldest` работает; дефолт не изменён.
- [ ] `cargo build`, `cargo clippy --all-targets` зелёные.

## Зависимости
Билдер `Command::buffer_policy(...)` — отдельная подзадача (TASK-0006), строго после этой (нужен enum).

> Это **пример** из валидационного прогона на синтетической фикстуре. Не реальная задача очереди.
