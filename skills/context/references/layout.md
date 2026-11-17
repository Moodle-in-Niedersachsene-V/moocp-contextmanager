# Layout of the context area

Read this before you create a file or restructure a unit. Fixed names are English. The teacher's own folders (school year, class, subject) keep their names.

## Levels

Every level has an `index.md`. It only points: to the levels below it and to the files of its own level, one line each on what is there. Old layout: `CONTEXT.md` is the index when `index.md` is missing; `context_start` reads it for the root.

- Root: `index.md`, `habits.md`, optional `glossary.md`, `decisions/`, `subjects/<subject>/` (subject-wide habits and standards), and the school-year folders.
- School year, class, subject folders: their own `index.md`. Habits go on the most general level they apply to.
- Unit or course folder: `index.md`, `plan.md` (or `plan/`, see below), `journal/`.

## Files

- `habits.md`: how the teacher works, for example how the teacher addresses students or builds questions. Also the write mode (see SKILL.md).
- `glossary.md`: terms with their meaning in the teacher's teaching.
- `decisions/`: one short file per decision. It states the situation, the choice, and the reason. Only for surprising decisions with a real alternative. The reason comes only from a source; otherwise write `Reason: not recorded` and ask the teacher (Hard rule in SKILL.md).
- `plan.md`: the target state of the unit, ordered by weeks or course sections. It never grows by date. Above 100 lines, split it: `plan/index.md` holds an overview and one file per week or section.
- `journal/YYYY-MM-DD.md`: one file per day. Entries are appended with `context_append`, never replaced.

## Plan content

- Only the target state. History goes to the journal.
- Each section carries its state (`draft`, `approved`, `implemented`), its deviations, and its remaining work.
- The top of the plan has an `Open` list. It points only to sections with remaining work, so the next session sees where to continue without reading everything.
- A `why` line next to an ordinary plan item. Surprising choices go to `decisions/`.
- Do not repeat what the Moodle course already shows, unless the reason is not visible there.

## Old layout (Coursepilot)

Old files stay readable as they are: `CONTEXT.md`, `status.md`, `journal-*.md`. New writes use the new layout. To restructure a unit: copy only the facts the old files state into the new files (reasons, dates and sources included; anything missing is `Reason: not recorded` and goes to the teacher, see the Hard rule in SKILL.md). Then move the old ones into `archive/` with `context_archive`. Journals stay where they are. Then fix every reference to the moved files that `context_archive` reports in its `references:` part, in the same step (see SKILL.md, Signposts and archive).
