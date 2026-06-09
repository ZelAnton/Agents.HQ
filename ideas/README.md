# `ideas/` — кросс-репо идеи

Идеи, которые **охватывают ≥2 репозитория**. Идея про один репо живёт в
`../projects/<repo>/ideas/`. Идея целого нового проекта без репо — это карточка
`../projects/<name>/card.md` со `status: no-repo-yet`.

> Не путать с `d:\GitHub\Personal\Ideas\` — там продуктовые roadmap'ы/реквесты и
> конкурентный анализ (исходный материал). Здесь — интеграционные идеи между моими репо.

## Поток

`new` → `accepted` → `promoted` (стала `TASK-####`) / `rejected`.

1. Скопируй `_templates/idea.md` → `IDEA-<YYYYMMDD>-<slug>.md`, заполни `spans-repos`, суть, эффект.
2. Когда идея принята и оформляется в работу — заведи `TASK-####` (в `../tasks/` или
   `../projects/<repo>/tasks/`), проставь в идее `status: promoted` + `promoted-to: TASK-####`,
   перенеси идею в `_archive/`.
3. Отклонённую — `status: rejected` + одна строка почему, в `_archive/`.

Протокол целиком — в [`../README.md`](../README.md).
