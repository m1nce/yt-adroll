# MGT 159T Final Project — YouTube Mid-Roll Ad Threshold RDD

A coursework project (UCSD MGT 159T) measuring the behavioral distortion of
YouTube's mid-roll ad eligibility threshold via a regression discontinuity
design (RDD) with a McCrary-style density test.

## Research Question

Has YouTube's minimum-length rule for mid-roll ads caused creators to
strategically lengthen their videos to cross the eligibility threshold
(10:00 before July 27, 2020; 8:00 after), and if so, how large is the
distortion?

**Method:** Regression discontinuity design with the McCrary density test as
the primary specification, plus a difference-in-differences robustness check
around the 2020 policy switch.

## Repository Layout

| Path | Contents |
|---|---|
| `code/` | R pipeline scripts (`00b` → `03`). Channel discovery, channel/video pulls from the YouTube Data API, and pilot exploration. |
| `python/` | uv-managed Python project for marimo exploratory notebooks. |
| `python/notebooks/` | `explore_channel_seeds.py`, `pilot_video_analysis.py` — interactive marimo notebooks. |
| `plan_of_attack/` | Group plan-of-attack writeup (`.qmd` source + rendered PDF). |
| `project_question/` | Assignment prompt, dataset description, and the locked-in research-proposal deliverable. |
| `figures/` | PNGs produced by `code/03_explore_pilot.R` and embedded in the writeup. |
| `data/` | Gitignored. Holds API pulls and per-channel parquet caches. Schema reference at `data/channels_seeds_template.csv` is kept. |
| `docs/` | Gitignored. Working specs and supporting notes. |
| `.env.example` | Template for `.env`, which holds `YOUTUBE_API_KEY` (gitignored). |
| `CLAUDE.md` | Guidance for Claude Code agents working in this repo. |

## Pipeline

The data pipeline is **strictly sequential** — each step writes a parquet/CSV
file the next step reads:

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
quarto render plan_of_attack/main_group_project_plan_of_attack.qmd → PDF
```

`02_pull_videos.R` is **idempotent**: per-channel responses cache under
`data/raw/{channel_id}.parquet`, so reruns spend near-zero quota. The same
script also serves the full pull — set
`VIDEO_PULL_INPUT=data/channels.parquet` instead of the pilot subset.

## Setup

1. Copy `.env.example` to `.env` and fill in `YOUTUBE_API_KEY` (YouTube Data
   API v3 key).
2. R packages: `httr2`, `jsonlite`, `dplyr`, `tidyr`, `purrr`, `readr`,
   `tibble`, `arrow`, `lubridate`, `ggplot2`, `scales`. On macOS, install
   `arrow` via `install.packages("arrow", type = "binary")` if the source
   build fails.
3. Python: `uv sync` from `python/` to create `.venv` from `pyproject.toml`
   and `uv.lock`.

## Commands

```sh
# R pipeline (each step requires .env with YOUTUBE_API_KEY)
Rscript code/00b_discover_candidates.R   # ~1,200 quota units
Rscript code/00_resolve_channels.R       # ~190 units (one per seed)
Rscript code/01_pull_channels.R          # offline filtering
Rscript code/02_pull_videos.R            # ~80 units per channel
Rscript code/03_explore_pilot.R          # offline; writes figures/ and docs/

# Marimo notebooks
uv sync
uv run marimo edit python/notebooks/explore_channel_seeds.py
uv run marimo edit python/notebooks/pilot_video_analysis.py

# Render the writeup (run from the repo root, not from inside plan_of_attack/)
quarto render plan_of_attack/main_group_project_plan_of_attack.qmd
```

## Data

- **Source:** YouTube Data API v3, with channel discovery seeded by a
  `search.list?order=viewCount` sweep across the allowed categories.
- **Study window:** 2018-01-01 to 2023-12-31 (30 months pre-policy, 41
  months post).
- **Subscriber band:** 10,000–1,000,000.
- **Allowed categories** (channel-level): Gaming, People & Blogs, Education,
  Howto & Style, Entertainment, Comedy. **Sports is included as a deliberate
  placebo** — its length is structurally determined and should not bunch.
- **Shorts filter:** `duration_sec > 61` (the 1-second buffer catches sub-60s
  Shorts whose API duration rounds up to 61s).
- **Running variable:** `duration_sec`.

## Design Summary

- **Cutoff 1:** 10:00 (600s) before 2020-07-27.
- **Cutoff 2:** 8:00 (480s) on/after 2020-07-27. Period assignment uses
  `<` not `<=`, so videos uploaded *on* 2020-07-27 are post-policy.
- **Primary outcome:** density discontinuity at each cutoff (manipulation /
  strategic padding).
- **Secondary outcomes:** views, likes, comments above vs. below each cutoff.
- **Placebos:** density tests at 7:00 and 9:00, plus the Sports category.

The full proposal lives in `project_question/deliverable.md`. The rendered
plan of attack is at
`plan_of_attack/main_group_project_plan_of_attack.pdf`.
