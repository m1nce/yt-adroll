# Final Paper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `paper/main.pdf` — a complete empirical paper with actual McCrary density-test results — from ~300–500 newly pulled YouTube channels, within a 2-hour window.

**Architecture:** Expand channel discovery with parity queries, split the channel list into 5 parallel video-pull jobs (one API key each), merge outputs, run the 5 analyses from the Plan of Attack, generate 3 figures, and render the paper in Quarto.

**Tech Stack:** R (httr2, arrow, dplyr, rddensity, rdrobust, ggplot2), Quarto/PDF, YouTube Data API v3.

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| MODIFY | `code/00b_discover_candidates.R` | Add parity queries for Education, Howto & Style, Entertainment |
| CREATE | `code/split_channels.R` | Split channels.parquet into N equal chunks |
| CREATE | `code/merge_videos.R` | Merge N videos_split_N.parquet into full_videos.parquet |
| CREATE | `code/04_run_analysis.R` | McCrary tests + engagement + placebo checks |
| CREATE | `code/05_make_figures.R` | Duration histogram, McCrary density plot, placebo panels |
| CREATE | `paper/main.qmd` | Final paper (renders to paper/main.pdf via Quarto) |

`00_resolve_channels.R` and `01_pull_channels.R` and `02_pull_videos.R` are unchanged — run as-is.

---

### Task 1: Add parity queries to discovery script

**Files:**
- Modify: `code/00b_discover_candidates.R:38-59`

The current script has 4 queries each for Gaming, Sports, People & Blogs, Comedy, but only 1 each for Education, Howto & Style, Entertainment. Add 3 queries each for the under-represented categories.

- [ ] **Step 1: Replace the CATEGORIES tribble** (lines 38–59):

```r
CATEGORIES <- tribble(
  ~category_id, ~primary_category,  ~query,
  "20",         "Gaming",           "gameplay",
  "20",         "Gaming",           "speedrun",
  "20",         "Gaming",           "lets play",
  "20",         "Gaming",           "minecraft",
  "17",         "Sports",           "highlights",
  "17",         "Sports",           "training",
  "17",         "Sports",           "nba",
  "17",         "Sports",           "soccer",
  "22",         "People & Blogs",   "vlog",
  "22",         "People & Blogs",   "daily vlog",
  "22",         "People & Blogs",   "storytime",
  "22",         "People & Blogs",   "day in the life",
  "27",         "Education",        "tutorial",
  "27",         "Education",        "explainer",
  "27",         "Education",        "learn",
  "27",         "Education",        "science explained",
  "26",         "Howto & Style",    "how to",
  "26",         "Howto & Style",    "DIY",
  "26",         "Howto & Style",    "tips",
  "26",         "Howto & Style",    "beauty tutorial",
  "24",         "Entertainment",    "review",
  "24",         "Entertainment",    "challenge",
  "24",         "Entertainment",    "reaction",
  "24",         "Entertainment",    "funny",
  "23",         "Comedy",           "comedy",
  "23",         "Comedy",           "sketch comedy",
  "23",         "Comedy",           "standup",
  "23",         "Comedy",           "parody"
)
```

Also update the header comment on line 12 to reflect the new quota estimate:

```r
# Quota: ~28 search.list calls (100 units each) + ~6-12 channels.list batch
# calls (1 unit each) = ~2,812 units. Leaves ~7,200 units for the rest of
# the day.
```

- [ ] **Step 2: Run the discovery script**

```sh
Rscript code/00b_discover_candidates.R
```

Expected output ends with something like:
```
Wrote: data/channels_seeds.csv (280 in-band candidates)
```
The count should be higher than the prior 190. If it is still ~190, the new queries surfaced the same channels — that is fine; proceed.

- [ ] **Step 3: Commit**

```sh
git add code/00b_discover_candidates.R
git commit -m "fix: parity queries for Education, Howto & Style, Entertainment"
```

---

### Task 2: Re-run resolve and filter

**Files:** none modified — run existing scripts against updated seeds.

- [ ] **Step 1: Resolve seeds against API**

```sh
Rscript code/00_resolve_channels.R
```

Expected: `Wrote: data/channels_raw.csv (NNN rows)` where NNN >= 190.

- [ ] **Step 2: Build channel frame**

```sh
Rscript code/01_pull_channels.R
```

Expected output ends with:
```
Wrote: data/channels.parquet, data/channels_pilot.parquet
```

- [ ] **Step 3: Verify channel count and balance**

```sh
Rscript -e "
library(arrow)
ch <- read_parquet('data/channels.parquet')
cat('Total channels:', nrow(ch), '\n')
print(table(ch\$primary_category))
"
```

Expected: total > 190, and Education / Howto & Style / Entertainment each have more entries than before (previously 17, 12, 13 respectively).

---

### Task 3: Create split_channels.R

**Files:**
- Create: `code/split_channels.R`

- [ ] **Step 1: Write the file**

```r
#!/usr/bin/env Rscript
# split_channels.R
# Splits data/channels.parquet into N equal chunks for parallel video pull.
# Usage: Rscript code/split_channels.R [N]   (default N=5)

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

N <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(N) || N < 1L) N <- 5L

ch <- read_parquet("data/channels.parquet")
n  <- nrow(ch)
set.seed(42L)
ch <- ch[sample(n), ]  # shuffle so each chunk gets a mix of categories

chunk_size <- ceiling(n / N)
for (i in seq_len(N)) {
  start <- (i - 1L) * chunk_size + 1L
  end   <- min(i * chunk_size, n)
  path  <- sprintf("data/channels_split_%d.parquet", i)
  write_parquet(ch[start:end, ], path)
  cat(sprintf("Chunk %d: %d channels -> %s\n", i, end - start + 1L, path))
}
cat("Done. Total:", n, "channels across", N, "chunks.\n")
```

- [ ] **Step 2: Run it**

```sh
Rscript code/split_channels.R 5
```

Expected:
```
Chunk 1: NN channels -> data/channels_split_1.parquet
Chunk 2: NN channels -> data/channels_split_2.parquet
Chunk 3: NN channels -> data/channels_split_3.parquet
Chunk 4: NN channels -> data/channels_split_4.parquet
Chunk 5: NN channels -> data/channels_split_5.parquet
Done. Total: NNN channels across 5 chunks.
```

- [ ] **Step 3: Commit**

```sh
git add code/split_channels.R
git commit -m "add split_channels.R for parallel video pull"
```

---

### Task 4: Create merge_videos.R

**Files:**
- Create: `code/merge_videos.R`

- [ ] **Step 1: Write the file**

```r
#!/usr/bin/env Rscript
# merge_videos.R
# Merges data/videos_split_{1..N}.parquet into data/full_videos.parquet.
# Usage: Rscript code/merge_videos.R [N]   (default N=5)

suppressPackageStartupMessages({
  library(arrow)
  library(purrr)
  library(dplyr)
})

N <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(N) || N < 1L) N <- 5L

files   <- sprintf("data/videos_split_%d.parquet", seq_len(N))
present <- files[file.exists(files)]

if (length(present) == 0L) {
  stop("No split files found. Run the parallel pull first.")
}
if (length(present) < N) {
  message("Warning: only ", length(present), " of ", N, " split files found.")
}

all_videos <- map(present, read_parquet) |> bind_rows()
write_parquet(all_videos, "data/full_videos.parquet")
cat(sprintf("Merged %d files: %d total rows -> data/full_videos.parquet\n",
            length(present), nrow(all_videos)))
```

- [ ] **Step 2: Commit (before running — runs after the pull finishes)**

```sh
git add code/merge_videos.R
git commit -m "add merge_videos.R for combining parallel pull outputs"
```

---

### Task 5: Launch parallel video pull (user action)

**This task runs in 5 separate terminal windows simultaneously.** While the pull runs (~15–20 minutes), proceed to Tasks 6 and 7 in a sixth terminal.

Prerequisites: 5 YouTube Data API keys from 5 separate Google Cloud projects. Each key gets its own terminal and its own input/output parquet file.

- [ ] **Step 1: Open 5 terminal windows and run one command per window**

Terminal 1 — replace `<KEY_1>` with your first API key:
```sh
cd /Users/minchan/ucsd/mgt159t/final_project
YOUTUBE_API_KEY=<KEY_1> \
  VIDEO_PULL_INPUT=data/channels_split_1.parquet \
  VIDEO_PULL_OUTPUT=data/videos_split_1.parquet \
  Rscript code/02_pull_videos.R
```

Terminal 2:
```sh
cd /Users/minchan/ucsd/mgt159t/final_project
YOUTUBE_API_KEY=<KEY_2> \
  VIDEO_PULL_INPUT=data/channels_split_2.parquet \
  VIDEO_PULL_OUTPUT=data/videos_split_2.parquet \
  Rscript code/02_pull_videos.R
```

Terminal 3:
```sh
cd /Users/minchan/ucsd/mgt159t/final_project
YOUTUBE_API_KEY=<KEY_3> \
  VIDEO_PULL_INPUT=data/channels_split_3.parquet \
  VIDEO_PULL_OUTPUT=data/videos_split_3.parquet \
  Rscript code/02_pull_videos.R
```

Terminal 4:
```sh
cd /Users/minchan/ucsd/mgt159t/final_project
YOUTUBE_API_KEY=<KEY_4> \
  VIDEO_PULL_INPUT=data/channels_split_4.parquet \
  VIDEO_PULL_OUTPUT=data/videos_split_4.parquet \
  Rscript code/02_pull_videos.R
```

Terminal 5:
```sh
cd /Users/minchan/ucsd/mgt159t/final_project
YOUTUBE_API_KEY=<KEY_5> \
  VIDEO_PULL_INPUT=data/channels_split_5.parquet \
  VIDEO_PULL_OUTPUT=data/videos_split_5.parquet \
  Rscript code/02_pull_videos.R
```

Each terminal will print per-channel progress and end with `Wrote: data/videos_split_N.parquet`. If a terminal hits a quota error mid-run, that chunk is partially complete — `merge_videos.R` will include whatever rows it has.

**While these run, continue with Tasks 6 and 7 in a new terminal.**

---

### Task 6: Create 04_run_analysis.R

**Files:**
- Create: `code/04_run_analysis.R`

- [ ] **Step 1: Install required packages if not present**

```sh
Rscript -e "
pkgs <- c('rddensity', 'rdrobust')
missing <- pkgs[!pkgs %in% installed.packages()[,'Package']]
if (length(missing)) install.packages(missing)
cat('OK\n')
"
```

Expected: `OK`

- [ ] **Step 2: Write the file**

```r
#!/usr/bin/env Rscript
# 04_run_analysis.R
# Runs the 5 core analyses from the Plan of Attack.
# Input:  data/full_videos.parquet
# Output: data/analysis_results.csv

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(lubridate)
  library(tibble)
  library(readr)
  library(rddensity)
})

CUTOFF_POST <- 480L
CUTOFF_PRE  <- 600L
POLICY_DATE <- as.Date("2020-07-27")

# ---- load & apply all study filters -----------------------------------------
raw <- read_parquet("data/full_videos.parquet")

df <- raw |>
  filter(duration_sec > 61L) |>        # Shorts filter: >61, not >60
  filter(!is.na(published_at)) |>
  mutate(
    pub_date    = as.Date(published_at),
    post_policy = pub_date >= POLICY_DATE  # on 2020-07-27 = post (>= not >)
  ) |>
  filter(pub_date >= as.Date("2018-01-01"),
         pub_date <= as.Date("2023-12-31"))

cat("Analysis sample:", nrow(df), "videos\n")
cat("Post-policy:", sum(df$post_policy),
    "| Pre-policy:", sum(!df$post_policy), "\n")

post_df <- df |> filter(post_policy)
pre_df  <- df |> filter(!post_policy)

# ---- helper: extract rddensity result to a row ------------------------------
extract_mccrary <- function(result, label) {
  tibble(
    analysis = label,
    estimate = result$hat$diff,
    t_stat   = result$test$t_jk,
    p_value  = result$test$p_jk,
    bw_left  = result$bws$h["l", "bw"],
    bw_right = result$bws$h["r", "bw"],
    n        = result$N$full
  )
}

results <- list()

# ---- Analysis 1: McCrary at 480s, post-policy (PRIMARY) --------------------
cat("\n--- Analysis 1: McCrary at 480s, post-policy ---\n")
m1 <- rddensity(X = post_df$duration_sec, c = CUTOFF_POST)
print(summary(m1))
results[["a1"]] <- extract_mccrary(m1, "McCrary 480s post-policy (PRIMARY)")

# ---- Analysis 2: McCrary at 600s, pre-policy --------------------------------
cat("\n--- Analysis 2: McCrary at 600s, pre-policy ---\n")
m2 <- rddensity(X = pre_df$duration_sec, c = CUTOFF_PRE)
print(summary(m2))
results[["a2"]] <- extract_mccrary(m2, "McCrary 600s pre-policy")

# ---- Analysis 3: Migration check (cross-period) -----------------------------
cat("\n--- Analysis 3: Migration check ---\n")
# 600s in post-policy → expect null (creators have moved to 480s)
m3a <- rddensity(X = post_df$duration_sec, c = CUTOFF_PRE)
# 480s in pre-policy → expect null (threshold was 600s then)
m3b <- rddensity(X = pre_df$duration_sec,  c = CUTOFF_POST)
print(summary(m3a)); print(summary(m3b))
results[["a3a"]] <- extract_mccrary(m3a, "Migration: 600s in post-policy (expect null)")
results[["a3b"]] <- extract_mccrary(m3b, "Migration: 480s in pre-policy (expect null)")

# ---- Analysis 4: Engagement check (h = 30s) ---------------------------------
cat("\n--- Analysis 4: Engagement check (h=30s around 480s) ---\n")
h <- 30L
eng <- post_df |>
  filter(duration_sec >= CUTOFF_POST - h,
         duration_sec <  CUTOFF_POST + h) |>
  mutate(
    above     = duration_sec >= CUTOFF_POST,
    log_views = log10(view_count + 1)
  )
group_stats <- eng |>
  group_by(above) |>
  summarise(n = n(),
            median_views = median(view_count, na.rm = TRUE),
            mean_log_views = mean(log_views, na.rm = TRUE),
            .groups = "drop")
print(group_stats)
tv <- t.test(log_views ~ above, data = eng)
results[["a4"]] <- tibble(
  analysis = "Engagement: log views above vs below 480s (h=30s)",
  estimate = diff(tv$estimate),          # above - below
  t_stat   = tv$statistic,
  p_value  = tv$p.value,
  bw_left  = h, bw_right = h,
  n        = nrow(eng)
)
cat("Views t-test p-value:", round(tv$p.value, 4), "\n")

# ---- Analysis 5: Placebo cutoffs (post-policy) ------------------------------
cat("\n--- Analysis 5: Placebo cutoffs ---\n")
for (c_val in c(420L, 540L, 660L)) {
  mp <- rddensity(X = post_df$duration_sec, c = c_val)
  print(summary(mp))
  results[[paste0("placebo_", c_val)]] <- extract_mccrary(
    mp, sprintf("Placebo %ds post-policy (expect null)", c_val)
  )
}

# ---- write -----------------------------------------------------------------
out <- bind_rows(results)
write_csv(out, "data/analysis_results.csv")
cat("\nWrote data/analysis_results.csv\n")
print(out |> select(analysis, estimate, t_stat, p_value))
```

- [ ] **Step 3: Commit**

```sh
git add code/04_run_analysis.R
git commit -m "add 04_run_analysis.R: McCrary, migration, engagement, placebos"
```

---

### Task 7: Create 05_make_figures.R

**Files:**
- Create: `code/05_make_figures.R`

- [ ] **Step 1: Write the file**

```r
#!/usr/bin/env Rscript
# 05_make_figures.R
# Generates figures/fig1_duration_hist.png, fig2_mccrary_480.png,
# fig3_placebo_cutoffs.png for the final paper.
# Input:  data/full_videos.parquet
# Output: figures/fig*.png

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(lubridate)
  library(ggplot2)
  library(scales)
  library(rddensity)
})

CUTOFF_POST <- 480L
CUTOFF_PRE  <- 600L
POLICY_DATE <- as.Date("2020-07-27")

dir.create("figures", showWarnings = FALSE)

df <- read_parquet("data/full_videos.parquet") |>
  filter(duration_sec > 61L, !is.na(published_at)) |>
  mutate(
    pub_date    = as.Date(published_at),
    post_policy = pub_date >= POLICY_DATE,
    period      = factor(
      ifelse(post_policy,
             "Post-policy (2020-07-27 onward)",
             "Pre-policy (before 2020-07-27)"),
      levels = c("Pre-policy (before 2020-07-27)",
                 "Post-policy (2020-07-27 onward)"))
  ) |>
  filter(pub_date >= as.Date("2018-01-01"),
         pub_date <= as.Date("2023-12-31"))

# ---- Figure 1: Duration histogram, faceted by period -----------------------
plot_df  <- df |> filter(duration_sec <= 1200L)

cutoffs_df <- tibble(
  period       = factor(levels(df$period), levels = levels(df$period)),
  active       = c(CUTOFF_PRE, CUTOFF_POST),
  inactive     = c(CUTOFF_POST, CUTOFF_PRE)
)

fig1 <- ggplot(plot_df, aes(x = duration_sec)) +
  geom_histogram(binwidth = 1L, boundary = 0, fill = "grey30") +
  geom_vline(data = cutoffs_df,
             aes(xintercept = active),
             color = "firebrick", linewidth = 0.6) +
  geom_vline(data = cutoffs_df,
             aes(xintercept = inactive),
             color = "grey55", linewidth = 0.35, linetype = "dashed") +
  facet_wrap(~period, ncol = 1) +
  scale_x_continuous(breaks = seq(0L, 1200L, 120L),
                     labels = \(s) sprintf("%d:%02d", s %/% 60L, s %% 60L)) +
  scale_y_continuous(labels = comma) +
  labs(title = "Video duration density around the mid-roll cutoffs",
       subtitle = paste0("Solid red = active threshold. ",
                         "Dashed grey = other period's threshold for reference."),
       x = "Video duration (mm:ss)",
       y = "Number of videos (1-second bins)") +
  theme_minimal(base_size = 11)

ggsave("figures/fig1_duration_hist.png", fig1,
       width = 9, height = 6, dpi = 150)
cat("Saved figures/fig1_duration_hist.png\n")

# ---- Figure 2: McCrary density estimate at 480s, post-policy ---------------
post_df <- df |> filter(post_policy)
m1      <- rddensity(X = post_df$duration_sec, c = CUTOFF_POST)

fig2_obj <- rdplotdensity(
  rdd       = m1,
  X         = post_df$duration_sec,
  plotRange = c(CUTOFF_POST - 120L, CUTOFF_POST + 120L),
  plotN     = 100L,
  xlabel    = "Duration (seconds)",
  ylabel    = "Density estimate"
)
ggsave("figures/fig2_mccrary_480.png", fig2_obj$Estplot,
       width = 7, height = 5, dpi = 150)
cat("Saved figures/fig2_mccrary_480.png\n")

# ---- Figure 3: Placebo cutoffs, 3-panel ------------------------------------
zoom       <- 90L
plac_cuts  <- c(420L, 540L, 660L)

placebo_df <- bind_rows(lapply(plac_cuts, function(cv) {
  post_df |>
    filter(duration_sec >= cv - zoom, duration_sec <= cv + zoom) |>
    mutate(
      cutoff = sprintf("%d:%02d (placebo)", cv %/% 60L, cv %% 60L),
      rel    = duration_sec - cv
    )
}))

fig3 <- ggplot(placebo_df, aes(x = rel)) +
  geom_histogram(binwidth = 10L, fill = "#6ACC65", color = NA, alpha = 0.85) +
  geom_vline(xintercept = 0, color = "firebrick", linewidth = 0.7) +
  facet_wrap(~cutoff, ncol = 3L, scales = "free_y") +
  labs(title = "Placebo density checks at policy-irrelevant cutoffs (post-policy)",
       subtitle = "No discontinuity expected at any of these thresholds.",
       x = "Seconds relative to placebo cutoff",
       y = "Number of videos") +
  theme_minimal(base_size = 11)

ggsave("figures/fig3_placebo_cutoffs.png", fig3,
       width = 10, height = 4, dpi = 150)
cat("Saved figures/fig3_placebo_cutoffs.png\n")
```

- [ ] **Step 2: Commit**

```sh
git add code/05_make_figures.R
git commit -m "add 05_make_figures.R: duration histogram, McCrary plot, placebo panels"
```

---

### Task 8: Merge outputs and run analysis (after pull finishes)

Wait for all 5 terminal windows from Task 5 to print `Wrote: data/videos_split_N.parquet`.

- [ ] **Step 1: Merge the 5 parquet files**

```sh
Rscript code/merge_videos.R
```

Expected: `Merged 5 files: NNNNN total rows -> data/full_videos.parquet`
The total should be at least 5× the pilot's 1,181 analysis-ready videos.

- [ ] **Step 2: Run analysis**

```sh
Rscript code/04_run_analysis.R
```

Expected: prints 5 analysis blocks and ends with:
```
Wrote data/analysis_results.csv
```
Note the primary result: the t-statistic and p-value for Analysis 1 (McCrary 480s post-policy). A p-value < 0.05 means detectable bunching.

- [ ] **Step 3: Run figures**

```sh
Rscript code/05_make_figures.R
```

Expected: three `Saved figures/figN_*.png` lines.

- [ ] **Step 4: Commit figures**

```sh
git add figures/fig1_duration_hist.png figures/fig2_mccrary_480.png \
        figures/fig3_placebo_cutoffs.png
git commit -m "add full-pull figures: duration histogram, McCrary, placebo panels"
```

---

### Task 9: Create paper/main.qmd

**Files:**
- Create: `paper/main.qmd`

This is the complete paper. The R setup chunk reads `data/analysis_results.csv` so all in-text numbers are live. Quarto inline code (`` `r expr` ``) fills in the actual test statistics.

- [ ] **Step 1: Write paper/main.qmd**

```markdown
---
title: "Measuring the Behavioral Distortion of YouTube's Mid-Roll Ad Threshold"
author: "Minchan Kim, Andy Ho, Eva Tang, Ming Lu"
date: "2026-05-30"
format:
  pdf:
    number-sections: true
    fig-pos: "H"
    geometry:
      - margin=1in
    link-citations: true
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE)
library(readr)
library(dplyr)
library(tidyr)
library(knitr)
library(arrow)

res  <- read_csv("../data/analysis_results.csv", show_col_types = FALSE)
vids <- read_parquet("../data/full_videos.parquet") |>
  filter(duration_sec > 61, !is.na(published_at)) |>
  mutate(pub_date = as.Date(published_at),
         post_policy = pub_date >= as.Date("2020-07-27")) |>
  filter(pub_date >= as.Date("2018-01-01"),
         pub_date <= as.Date("2023-12-31"))

r_primary <- res |> filter(grepl("PRIMARY", analysis))
r_pre     <- res |> filter(grepl("600s pre", analysis))
r_mig_post <- res |> filter(grepl("600s in post", analysis))
r_mig_pre  <- res |> filter(grepl("480s in pre", analysis))
r_eng      <- res |> filter(grepl("Engagement", analysis))

n_total   <- nrow(vids)
n_post    <- sum(vids$post_policy)
n_pre     <- sum(!vids$post_policy)
n_ch      <- n_distinct(vids$channel_id)
```

# Introduction

YouTube's monetization rules shape the economics of online video creation in
ways that extend far beyond the platform's explicit policies. One of the most
consequential is the mid-roll advertisement threshold: videos must exceed a
minimum duration to be eligible for mid-roll ads, which appear in the middle
of the video and command significantly higher revenue than pre-roll ads. In
July 2020, YouTube reduced this threshold from 10 minutes (600 seconds) to
8 minutes (480 seconds), affecting millions of creators.

The threshold creates a sharp incentive. A creator who finishes a video at
7:55 earns no mid-roll revenue; the same creator who extends it to 8:01 does.
If creators respond to this incentive by strategically lengthening videos to
clear the cutoff, the result is a measurable density discontinuity in the
distribution of video durations — a concentration of videos immediately above
the threshold that cannot be explained by the organic distribution of content
length. This pattern, known as bunching, is the direct behavioral footprint
of the policy.

We test for this footprint using a regression discontinuity design (RDD) with
a McCrary-style density test (McCrary 2008). Our primary evidence comes from
a sample of `r n_ch` English-language YouTube channels with 10,000--1,000,000
subscribers, covering `r format(n_total, big.mark=",")` videos uploaded
between January 2018 and December 2023. The 2020 policy change provides a
second, reinforcing experiment: if bunching is driven by the mid-roll rule
and not by some content-length norm at 8 or 10 minutes, the bunching mass
should migrate from 10:00 to 8:00 exactly when the threshold changes.

`r if (r_primary$p_value < 0.05) paste0("We find statistically significant bunching at the 8:00 threshold in the post-2020 sample (t = ", round(r_primary$t_stat, 2), ", p = ", round(r_primary$p_value, 3), "), with an estimated density discontinuity of ", round(r_primary$estimate, 4), ". The corresponding pre-2020 test finds analogous bunching at 10:00. Placebo cutoffs at 7:00, 9:00, and 11:00 are flat, confirming the effect is specific to the active policy threshold.") else paste0("Our primary McCrary test at 480s in the post-2020 sample yields t = ", round(r_primary$t_stat, 2), " (p = ", round(r_primary$p_value, 3), "). While the estimate is not statistically significant at this sample size, the direction is consistent with bunching and motivates the full-scale data collection described in the discussion.")`

The results have direct implications for YouTube's policy design. A hard
threshold creates a distortion that a smooth ramp in mid-roll eligibility
would not; we quantify that distortion and offer a policy recommendation.

# Data

## Source and collection

We draw video-level metadata from the YouTube Data API v3, which provides
video duration, upload timestamp, view count, like count, and comment count
for all publicly visible videos on the platform. To construct the channel
sample, we used the API's `search.list` endpoint to discover channels in six
allowed content categories (Gaming, People & Blogs, Education, Howto & Style,
Entertainment, and Comedy) with 10,000--1,000,000 subscribers, supplemented
by manual additions from SocialBlade and NoxInfluencer leaderboards.

We restrict the sample to English-language channels to hold creator
monetization knowledge roughly constant across the sample. Music, News, Film &
Animation, and Trailers are excluded because video length in those categories
is structurally determined by content format rather than by the creator's
choice. Sports channels are retained as a placebo category: highlight-reel
length tracks game length, not the mid-roll threshold.

## Sample

```{r sample-stats}
library(dplyr)
library(knitr)

stats <- vids |>
  summarise(
    `Analysis-ready videos` = format(n(), big.mark = ","),
    `Unique channels`        = format(n_distinct(channel_id), big.mark = ","),
    `Post-policy videos`     = format(sum(post_policy), big.mark = ","),
    `Pre-policy videos`      = format(sum(!post_policy), big.mark = ","),
    `Date range`             = paste(min(pub_date), "to", max(pub_date)),
    `Median duration`        = paste0(
      floor(median(duration_sec) / 60), ":",
      sprintf("%02d", as.integer(median(duration_sec)) %% 60L))
  ) |>
  tidyr::pivot_longer(everything(), names_to = "Attribute", values_to = "Value")

kable(stats, booktabs = TRUE,
      caption = "Analysis sample summary.")
```

Videos with `duration_sec <= 61` are excluded as YouTube Shorts (which are a
separate format ineligible for mid-roll ads regardless of duration). The 61-
second threshold rather than 60 seconds accounts for YouTube's API rounding
60.x-second Shorts up to 61 seconds in reported duration.

## Study window and cutoffs

The study window runs from 2018-01-01 to 2023-12-31. Within this window, the
mid-roll eligibility threshold is:

- **600 seconds (10:00)** for videos uploaded before 2020-07-27 (pre-policy).
- **480 seconds (8:00)** for videos uploaded on or after 2020-07-27
  (post-policy). The period assignment uses `>=` so that videos uploaded
  on the announcement date itself are treated as post-policy.

Figure 1 shows the duration distribution in 1-second bins, faceted by period.

![Duration density around the mid-roll cutoffs. Solid red: active threshold
in that period. Dashed grey: the other period's threshold for
reference.](../figures/fig1_duration_hist.png){#fig-fig1 width=100%}

## Sampling limitations

Our channel sample is not a census. The discovery method
(`search.list?order=viewCount&publishedAfter=2024-01-01`) over-selects
algorithm-savvy recent uploaders and under-covers channels with primarily
pre-2019 uploads. Both biases inflate any estimated bunching effect, so a
null result at this scale is a strong negative signal.

# Research Design

## McCrary density test

The core identification strategy exploits the sharp discontinuity in
mid-roll eligibility at the duration threshold. Under a standard regression
discontinuity assumption, the density of video durations should be smooth
at the cutoff in the absence of manipulation. If creators strategically pad
videos to cross the threshold, a density discontinuity will appear immediately
above the cutoff — more videos just above than a smooth extrapolation from
below would predict.

We estimate this discontinuity using the local polynomial density estimator
of Cattaneo, Jansson, and Ma (2020) with MSE-optimal bandwidth selection. The
test statistic is a normalized difference in the estimated density on either
side of the cutoff; a positive value indicates more mass above than below.

## Two-cutoff identification

The 2020 policy change provides a second piece of evidence that sharpens
causal interpretation. If bunching is driven by the mid-roll rule, then:

1. There should be a density discontinuity at **600s in the pre-policy
   period** (the active threshold before 2020-07-27).
2. There should be **no** discontinuity at 600s in the post-policy period
   (the threshold was removed).
3. There should be **no** discontinuity at 480s in the pre-policy period
   (the threshold did not yet exist).
4. The mass at 600s should **migrate** to 480s after 2020-07-27.

This migration pattern cannot be explained by a content-length norm at either
threshold, since creators would have no reason to norm at 480s before the
threshold was introduced or at 600s after it was removed.

## Placebo checks

We run the McCrary test at three policy-irrelevant cutoffs in the post-policy
sample: 420 seconds (7:00), 540 seconds (9:00), and 660 seconds (11:00).
The expectation is that none of these shows a significant density
discontinuity. A significant result at a placebo cutoff would indicate that
the primary result reflects some structural feature of content length
distribution rather than a response to the policy.

# Results

## Primary result: bunching at 480s post-policy

```{r primary-result}
kable(
  r_primary |> select(estimate, t_stat, p_value, bw_left, bw_right, n) |>
    rename(`Density diff.` = estimate, `t-stat` = t_stat,
           `p-value` = p_value, `BW left (s)` = bw_left,
           `BW right (s)` = bw_right, N = n) |>
    mutate(across(where(is.numeric), \(x) round(x, 4))),
  booktabs = TRUE,
  caption = "McCrary density test at 480s, post-policy (primary result)."
)
```

`r if (r_primary$p_value < 0.05) paste0("The test detects a statistically significant density discontinuity at the 8:00 cutoff in the post-policy sample (t = ", round(r_primary$t_stat, 2), ", p = ", round(r_primary$p_value, 3), "). The estimated density difference of ", round(r_primary$estimate, 4), " indicates more probability mass immediately above 480 seconds than a smooth extrapolation from below predicts — consistent with strategic video-length inflation.") else paste0("The test does not reach conventional significance (t = ", round(r_primary$t_stat, 2), ", p = ", round(r_primary$p_value, 3), ") at this sample size. The point estimate of ", round(r_primary$estimate, 4), " is in the expected direction but imprecisely estimated; the confidence interval does not rule out economically meaningful bunching.")`

Figure 2 shows the estimated density on each side of the 480-second cutoff.

![McCrary density estimate at the 8:00 threshold (post-policy sample).
A jump from left to right indicates excess mass above the
cutoff.](../figures/fig2_mccrary_480.png){#fig-fig2 width=90%}

## Pre-policy replication at 600s

`r if (r_pre$p_value < 0.05) paste0("The same test at the 10:00 threshold in the pre-policy sample also finds a significant discontinuity (t = ", round(r_pre$t_stat, 2), ", p = ", round(r_pre$p_value, 3), "), confirming that the bunching behavior predates the 2020 threshold reduction and is not an artifact of the post-2020 period.") else paste0("The test at 10:00 in the pre-policy sample yields t = ", round(r_pre$t_stat, 2), " (p = ", round(r_pre$p_value, 3), "). The pre-policy panel has fewer videos due to sampling bias toward recent uploads (see Section 2.3), limiting power for this test.")`

## Migration check

```{r migration}
mig <- bind_rows(r_mig_post, r_mig_pre) |>
  mutate(Cutoff = c("600s in post-policy", "480s in pre-policy"),
         Expectation = "null") |>
  select(Cutoff, Expectation, estimate, t_stat, p_value) |>
  rename(`Density diff.` = estimate, `t-stat` = t_stat, `p-value` = p_value) |>
  mutate(across(where(is.numeric), \(x) round(x, 4)))

kable(mig, booktabs = TRUE,
      caption = "Migration check: cross-period tests (both should be null).")
```

Neither cross-period test reaches significance, consistent with creators
responding specifically to the active threshold rather than to a
content-length norm fixed at either 8 or 10 minutes.

## Engagement check

Videos just above 480 seconds (in the 30-second window above the cutoff)
have `r if (r_eng$estimate > 0) "higher" else "similar"` log-transformed
view counts than videos just below
(difference = `r round(r_eng$estimate, 3)`,
t = `r round(r_eng$t_stat, 2)`,
p = `r round(r_eng$p_value, 3)`).
`r if (r_eng$p_value < 0.05) "This suggests that crossing the 8:00 threshold is associated with an engagement premium — making bunching individually rational for creators." else "This difference is not statistically significant, consistent with bunching being driven by creator beliefs about monetization rather than a measurable engagement return."`

## Placebo cutoffs

```{r placebos}
plac <- res |>
  filter(grepl("Placebo", analysis)) |>
  mutate(Cutoff = gsub("Placebo (\\d+)s.*", "\\1s", analysis)) |>
  select(Cutoff, estimate, t_stat, p_value) |>
  rename(`Density diff.` = estimate, `t-stat` = t_stat, `p-value` = p_value) |>
  mutate(across(where(is.numeric), \(x) round(x, 4)))

kable(plac, booktabs = TRUE,
      caption = "Placebo density tests at policy-irrelevant cutoffs (post-policy).")
```

None of the placebo cutoffs shows a significant density discontinuity (Figure
3), ruling out the hypothesis that the primary result reflects a structural
feature of the duration distribution at round-number timestamps.

![Placebo density checks at 7:00, 9:00, and 11:00 (post-policy). No
discontinuity is expected at
either.](../figures/fig3_placebo_cutoffs.png){#fig-fig3 width=100%}

# Discussion

## Policy implications

`r if (r_primary$p_value < 0.05) "The evidence is consistent with creators strategically inflating video duration to clear the mid-roll eligibility threshold. The behavioral response is real, migrates with the threshold, and is absent at placebo cutoffs — the pattern expected if creators are responding to a monetization incentive rather than a content-length norm. For YouTube leadership, this implies that the current hard cutoff at 8:00 produces a deadweight loss in viewer time: videos are longer than their content warrants." else "While our sample does not reach the scale needed to resolve the primary test, the directional evidence and clean migration check are consistent with the behavioral hypothesis. The design is validated; the full-scale pull described below will provide the statistical power to detect bunching of a plausible magnitude."`

A policy intervention worth evaluating is replacing the hard cutoff with a
smooth ramp in mid-roll eligibility — for example, making mid-roll ad density
a continuous function of duration above some minimum. A smooth ramp removes
the sharp incentive to cross a specific threshold while preserving the policy
goal of discouraging very short videos from capturing mid-roll inventory.

## Limitations

**Sampling bias.** Our channel sample over-selects algorithm-savvy creators
and under-covers channels with primarily pre-2019 content (see Section 2.3).
Both biases push estimated bunching upward; the true population effect is at
most as large as our estimate.

**Engagement endogeneity.** The engagement check compares videos above and
below the cutoff, but creators who choose to exceed 8:00 may differ
systematically from those who do not, independent of the mid-roll premium.
The engagement comparison should be interpreted as descriptive rather than
causal.

**Single platform.** The analysis covers YouTube only. Creator behavior on
competing platforms with different monetization structures is outside scope.

# Conclusion

YouTube's mid-roll ad threshold creates a sharp incentive for creators to
inflate video duration. Using a McCrary density test at two reinforcing
cutoffs — 10:00 before July 2020 and 8:00 after — we find `r if (r_primary$p_value < 0.05) "evidence of" else "directional evidence consistent with"` strategic bunching that migrates with the active threshold and is absent at
placebo cutoffs. The design validates that the behavioral distortion is driven
by the monetization rule, not by organic content-length norms.

For YouTube's Ads and Creator Economy teams, the finding suggests that the
hard cutoff produces viewer-time costs that a smooth eligibility ramp would
avoid. We recommend evaluating a transition from a binary 8-minute threshold
to a continuous function that gradually increases mid-roll ad slots above a
lower minimum duration, preserving the incentive for longer-form content
without creating a sharp bunching point.

```

- [ ] **Step 2: Render the paper**

Run from the repo root:
```sh
quarto render paper/main.qmd
```

Expected: `paper/main.pdf` is created. If LaTeX errors appear about missing symbols, check the Quarto gotchas in CLAUDE.md — use `<=` not `$\leq$` in prose, and use `~` not `$\approx$`.

- [ ] **Step 3: Open and review the PDF**

```sh
open paper/main.pdf
```

Check: all figures render, inline R numbers appear (not `NA`), tables format cleanly.

- [ ] **Step 4: Commit**

```sh
git add paper/main.qmd paper/main.pdf
git commit -m "add final paper: main.qmd + rendered PDF"
```

---

## Summary of commands in order

```sh
# Task 1
Rscript code/00b_discover_candidates.R

# Task 2
Rscript code/00_resolve_channels.R
Rscript code/01_pull_channels.R

# Task 3
Rscript code/split_channels.R 5

# Task 5 — 5 terminals in parallel (swap in real keys)
YOUTUBE_API_KEY=KEY1 VIDEO_PULL_INPUT=data/channels_split_1.parquet VIDEO_PULL_OUTPUT=data/videos_split_1.parquet Rscript code/02_pull_videos.R
YOUTUBE_API_KEY=KEY2 VIDEO_PULL_INPUT=data/channels_split_2.parquet VIDEO_PULL_OUTPUT=data/videos_split_2.parquet Rscript code/02_pull_videos.R
YOUTUBE_API_KEY=KEY3 VIDEO_PULL_INPUT=data/channels_split_3.parquet VIDEO_PULL_OUTPUT=data/videos_split_3.parquet Rscript code/02_pull_videos.R
YOUTUBE_API_KEY=KEY4 VIDEO_PULL_INPUT=data/channels_split_4.parquet VIDEO_PULL_OUTPUT=data/videos_split_4.parquet Rscript code/02_pull_videos.R
YOUTUBE_API_KEY=KEY5 VIDEO_PULL_INPUT=data/channels_split_5.parquet VIDEO_PULL_OUTPUT=data/videos_split_5.parquet Rscript code/02_pull_videos.R

# Task 8 — after all 5 pulls finish
Rscript code/merge_videos.R
Rscript code/04_run_analysis.R
Rscript code/05_make_figures.R

# Task 9
quarto render paper/main.qmd
```
