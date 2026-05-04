# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A coursework project (MGT 159T) measuring the behavioral distortion of YouTube's
mid-roll ad threshold via a regression discontinuity design (RDD) with a
McCrary-style density test. The deliverable is the Plan of Attack writeup at
`plan_of_attack/main_group_project_plan_of_attack.qmd` (rendered to PDF).
The research design is locked in by `project_question/deliverable.md`; do not
re-litigate cutoffs, methods, or category choices unless explicitly asked.

## Pipeline order

The data pipeline is **strictly sequential**. Each step writes a parquet file
the next step reads:

```
code/00b_discover_candidates.R   → data/channels_seeds.csv,
                                   data/channels_candidates_full.csv
[review in marimo]                 python/notebooks/explore_channel_seeds.py
code/00_resolve_channels.R       → data/channels_raw.csv
code/01_pull_channels.R          → data/channels.parquet,
                                   data/channels_pilot.parquet
code/02_pull_videos.R            → data/pilot_videos.parquet
                                   (per-channel cache under data/raw/)
code/03_explore_pilot.R          → figures/, docs/pilot-findings.md
quarto render plan_of_attack/.../*.qmd → PDF
```

`02_pull_videos.R` is **idempotent**: per-channel responses cache under
`data/raw/{channel_id}.parquet`, so reruns spend near-zero quota. The same
script serves the full pull — set
`VIDEO_PULL_INPUT=data/channels.parquet` instead of the pilot subset.

## Commands

```sh
# R scripts. Each requires .env with YOUTUBE_API_KEY.
Rscript code/00b_discover_candidates.R   # ~1,200 quota units
Rscript code/00_resolve_channels.R       # ~190 units (one per seed)
Rscript code/01_pull_channels.R          # offline, just filtering
Rscript code/02_pull_videos.R            # ~80 units per channel
Rscript code/03_explore_pilot.R          # offline

# Marimo notebooks via uv. uv sync once to set up .venv.
uv sync
uv run marimo edit python/notebooks/explore_channel_seeds.py
uv run marimo edit python/notebooks/pilot_video_analysis.py

# Render the Plan of Attack writeup.
quarto render plan_of_attack/main_group_project_plan_of_attack.qmd
```

R packages required: `httr2`, `jsonlite`, `dplyr`, `tidyr`, `purrr`, `readr`,
`tibble`, `arrow`, `lubridate`, `ggplot2`, `scales`. `arrow` is sometimes
finicky on macOS — install via `install.packages("arrow", type = "binary")`
if the source build fails.

## Locked-in design decisions

These were deliberated and recorded in
`/Users/minchan/.claude/plans/mossy-scribbling-music.md`. Do not change them
without first re-reading that plan:

- **Study window:** 2018-01-01 to 2023-12-31 (30 mo pre-policy, 41 mo post).
- **Subscriber band:** 10,000–1,000,000.
- **Allowed categories** (channel-level): Gaming, People & Blogs, Education,
  Howto & Style, Entertainment, Comedy. **Sports is included as a deliberate
  placebo category** (length is structurally determined → should not bunch).
- **Shorts filter is `duration_sec > 61`, not `> 60`.** The 1-second buffer
  catches sub-60s Shorts whose API duration rounds up to 61s. Pilot inspection
  showed 152 videos at 60s and 94 at 61s vs 2–5 per bin from 62s onward.
- **Cutoffs:** 600s (10:00) before 2020-07-27, 480s (8:00) on/after.
- **Period assignment uses `<` not `<=`:** videos uploaded *on* 2020-07-27
  are post-policy.
- **Sampling bias is documented, not fixed:** the discovery method
  (`search.list?order=viewCount&publishedAfter=2024-01-01`) over-selects
  algorithm-savvy recent uploaders and under-covers pre-2019 channels. Both
  biases push estimated bunching upward, so any null result is a strong
  negative signal. Section 2(h) of the PoA names all three biases explicitly.

## Marimo notebook conventions

- Cells must not redefine the same top-level variable. Use `_`-prefixed
  locals for cell-internal state. The shared globals are: `videos_raw`,
  `channels`, `videos`, `df`, `df_no_period`, the UI controls
  (`shorts_toggle`, `channel_select`, `category_select`, `period_radio`,
  `bandwidth_slider`, `channel_picker`), and the constants imported in the
  setup cell.
- `df_no_period` is the channel/category-filtered frame *without* the
  period filter applied. KDE/ECDF overlays, period-specific zooms, and
  the per-channel deep dive read from it so the period radio doesn't
  blank them out. `df` is `df_no_period` + period filter.
- Faceted altair charts can't be layered after faceting. To add a reference
  line to a faceted chart, layer first with shared data, then facet:
  `(bars + rule).facet(...)`.

## Repo conventions

- `data/`, `docs/`, `.agents/`, `.claude/` are all **gitignored**. The
  exception is `data/channels_seeds_template.csv` (kept as schema reference).
- `code/` is R; `python/` is Python (currently just `python/notebooks/`,
  managed by uv via `pyproject.toml` + `uv.lock`).
- `.env` holds `YOUTUBE_API_KEY` and is gitignored. Copy from
  `.env.example`.
- Canonical Section-1 numbers and figures come from `code/03_explore_pilot.R`,
  not the marimo notebook. The notebook is for interactive exploration; the
  R script is the source of truth embedded in the writeup.

## Quarto render gotchas

- Default LuaLaTeX fonts don't include `≤`, `∈`, `≈`. Use ASCII (`<=`,
  `in`, `~`) in prose or wrap in math mode (`$\leq$`, `$\in$`).
- Long unbroken paths in tables can wrap awkwardly. Break with explicit
  prose or shorter tokens.
- The `.qmd` references figures via relative path `../figures/...`; render
  from the repo root, not from inside `plan_of_attack/`.
