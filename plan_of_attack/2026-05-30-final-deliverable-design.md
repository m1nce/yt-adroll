# Final Deliverable Design — YouTube Mid-Roll Ad Threshold Study

**Date:** 2026-05-30  
**Deadline:** 2 hours from session start  
**Course:** MGT 159T

---

## Deliverable

A brand-new empirical paper rendered as a PDF from `paper/main.qmd`. Approximately 6 pages + figures. The Plan of Attack (`plan_of_attack/main_group_project_plan_of_attack.qmd`) is background context only — the paper stands alone.

---

## Phase 1 — Data Pipeline (~30 min)

### Step 1: Expand channel discovery (~5 min)

Re-run `code/00b_discover_candidates.R` with parity multi-queries across all 6 allowed categories (Gaming, People & Blogs, Education, Howto & Style, Entertainment, Comedy), matching the fix specified in PoA §4. Realistic yield after subscriber-band filtering: **250–500 channels** (up from 190). Optionally, add a second pass with `publishedBefore=2019-12-31` to improve pre-policy coverage (another ~2,000 units, time-permitting).

Then re-run:
- `code/00_resolve_channels.R` → `data/channels_raw.csv`
- `code/01_pull_channels.R` → updated `data/channels.parquet`

Quota cost: ~2,000 units on one existing key.

Required R packages (in addition to those in CLAUDE.md): `rddensity`, `rdrobust`.

### Step 2: Split channels for parallel pull

A helper script `code/split_channels.R` splits `data/channels.parquet` into 5 equal-sized chunks:
`data/channels_split_{1..5}.parquet`

### Step 3: Parallel video pull (~20 min wall-clock)

User creates 5 Google Cloud projects and obtains 5 API keys. Run 5 terminal instances simultaneously:

```sh
YOUTUBE_API_KEY=<key_N> \
  VIDEO_PULL_INPUT=data/channels_split_N.parquet \
  VIDEO_PULL_OUTPUT=data/videos_split_N.parquet \
  Rscript code/02_pull_videos.R
```

Existing per-channel cache in `data/raw/` means the 35 pilot channels cost 0 quota on re-run.

Quota per key: ~(actual_count)/5 × 80 units (each key stays under the 10,000/day limit as long as total channels ≤ 625).

### Step 4: Merge outputs

A helper script `code/merge_videos.R` reads `data/videos_split_{1..5}.parquet` and writes `data/full_videos.parquet`.

---

## Phase 2 — Analysis (~15 min)

**`code/04_run_analysis.R`** — runs against `data/full_videos.parquet`:

| # | Analysis | Implementation | Output |
|---|---|---|---|
| 1 | McCrary at 480s, post-policy | `rddensity(duration_sec, c=480)` on post-2020-07-27 | test stat, p-value, bandwidth, point estimate |
| 2 | McCrary at 600s, pre-policy | `rddensity(duration_sec, c=600)` on pre-2020-07-27 | same |
| 3 | Migration check | Cross-period: 600s in post (should be null), 480s in pre (should be null) | same |
| 4 | Engagement check | `log(view+1)` comparison [450s,480s) vs [480s,510s) post-policy; t-test + medians | group means, t-stat, p-value |
| 5 | Placebo cutoffs | McCrary at 420s, 540s, 660s (all should be flat) | test stats + p-values |

All results written to `data/analysis_results.csv` for inline citation in the paper.

**`code/05_make_figures.R`** — produces:
- `figures/fig1_duration_hist.png` — pre/post duration histogram with cutoff lines (regenerated at full scale)
- `figures/fig2_mccrary_480.png` — McCrary density plot at 480s post-policy
- `figures/fig3_placebo_cutoffs.png` — placebo cutoffs side-by-side

---

## Phase 3 — Paper (~70 min)

**File:** `paper/main.qmd` → renders to `paper/main.pdf`

| Section | Length | Key content |
|---|---|---|
| Introduction | ~1 page | The 8-min threshold as policy lever; why distortion matters; headline finding |
| Data | ~1 page | API source, [actual channel count] channels, 10K–1M subs, 2018–2023. Summary stats table. Figure 1. |
| Research Design | ~1.5 pages | McCrary rationale, two cutoffs, identifying assumptions, migration check, placebos |
| Results | ~1.5 pages | McCrary output at 480s + 600s with Figure 2. Migration check. Engagement premium. Placebo table. |
| Discussion & Limitations | ~0.5 pages | Three sampling biases (PoA §2h), power caveats, policy implications |
| Conclusion | ~0.25 pages | One-paragraph summary + management recommendation |

Prose is adapted from the PoA (structure and arguments already written); Results section is new.

---

## Key design constraints (do not change without re-reading PoA)

- Shorts filter: `duration_sec > 61` (not `> 60`)
- Period assignment: `published_at >= 2020-07-27` is post-policy (`<` not `<=` for pre)
- Cutoffs: 600s pre-policy, 480s post-policy
- Subscriber band: 10,000–1,000,000
- Sports is included as a placebo category (not excluded)
- Sampling biases push estimates upward; null result = strong negative signal
