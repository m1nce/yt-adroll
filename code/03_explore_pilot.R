#!/usr/bin/env Rscript
# 03_explore_pilot.R
#
# Compute everything Section 1 of the Plan of Attack asks for, plus the
# Figure 1 candidate (duration histogram with cutoff lines, faceted by
# pre / post 2020-07-27 policy switch).
#
# Input:  data/pilot_videos.parquet
# Output: figures/fig1_duration_hist.png    (Figure 1 candidate)
#         figures/duration_hist_zoom480.png (zoomed near 480s)
#         figures/duration_hist_zoom600.png (zoomed near 600s)
#         docs/pilot-findings.md            (notes for Section 1; gitignored)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(arrow)
  library(ggplot2)
  library(scales)
  library(lubridate)
})

POLICY_DATE <- as.Date("2020-07-27")
CUTOFF_PRE  <- 600  # 10:00
CUTOFF_POST <- 480  # 8:00
# YouTube Shorts are <=60s and do not run mid-roll ads. Set the filter
# threshold at 61 (i.e., keep duration_sec >= 62) to also exclude Shorts
# whose API duration rounds up to 61s — pilot inspection at 60-90s 1s bins
# showed 152 videos at 60s and 94 at 61s versus 2-5 per bin at 62s+, with
# the 61s sample dominated by #shorts-tagged vertical content.
SHORTS_MAX_SEC <- 61L

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
dir.create("docs",    recursive = TRUE, showWarnings = FALSE)

videos_raw <- read_parquet("data/pilot_videos.parquet")

n_raw <- nrow(videos_raw)
videos <- videos_raw |> filter(duration_sec > SHORTS_MAX_SEC)
n_shorts_dropped <- n_raw - nrow(videos)

cat("Rows (raw):           ", n_raw, "\n")
cat("Rows (post-Shorts):   ", nrow(videos), "  (",
    round(100 * n_shorts_dropped / n_raw, 1), "% dropped as Shorts)\n", sep = "")
cat("Date range:",
    as.character(min(as.Date(videos$published_at), na.rm = TRUE)), "to",
    as.character(max(as.Date(videos$published_at), na.rm = TRUE)), "\n")
cat("Unique channels:", n_distinct(videos$channel_id), "\n")
cat("Unique YouTube category IDs:", n_distinct(videos$category_id), "\n")

# -------- summary stats -------------------------------------------------------
key_vars <- c("duration_sec", "view_count", "like_count", "comment_count")
summary_tbl <- videos |>
  summarise(across(all_of(key_vars),
    list(n_nonNA = ~ sum(!is.na(.x)),
         pct_NA  = ~ mean(is.na(.x)) * 100,
         min     = ~ min(.x, na.rm = TRUE),
         p25     = ~ quantile(.x, 0.25, na.rm = TRUE),
         median  = ~ median(.x, na.rm = TRUE),
         p75     = ~ quantile(.x, 0.75, na.rm = TRUE),
         p99     = ~ quantile(.x, 0.99, na.rm = TRUE),
         max     = ~ max(.x, na.rm = TRUE)),
    .names = "{.col}__{.fn}")) |>
  pivot_longer(everything(), names_to = c("var", "stat"),
               names_sep = "__", values_to = "value") |>
  pivot_wider(names_from = stat, values_from = value)

cat("\nSummary stats:\n")
print(summary_tbl)

# -------- data quality flags --------------------------------------------------
qc <- tibble(
  flag = c(
    "duration_sec missing",
    "duration_sec == 0",
    "duration_sec > 12h",
    "view_count missing",
    "comment_count missing (comments off)",
    "duplicate video_id"
  ),
  n = c(
    sum(is.na(videos$duration_sec)),
    sum(videos$duration_sec == 0, na.rm = TRUE),
    sum(videos$duration_sec > 12 * 3600, na.rm = TRUE),
    sum(is.na(videos$view_count)),
    sum(is.na(videos$comment_count)),
    sum(duplicated(videos$video_id))
  )
)
cat("\nQC flags:\n"); print(qc)

# -------- Figure 1 candidate --------------------------------------------------
plot_df <- videos |>
  filter(!is.na(duration_sec), duration_sec > 0, duration_sec <= 1200) |>
  mutate(
    period = if_else(as.Date(published_at) < POLICY_DATE,
                     "Pre-policy (before 2020-07-27)",
                     "Post-policy (2020-07-27 onward)"),
    period = factor(period, levels = c(
      "Pre-policy (before 2020-07-27)",
      "Post-policy (2020-07-27 onward)"))
  )

cutoffs_df <- tibble(
  period = factor(c("Pre-policy (before 2020-07-27)",
                    "Post-policy (2020-07-27 onward)"),
                  levels = levels(plot_df$period)),
  active_cutoff = c(CUTOFF_PRE, CUTOFF_POST)
)

p_main <- ggplot(plot_df, aes(x = duration_sec)) +
  geom_histogram(binwidth = 1, boundary = 0, fill = "grey30") +
  geom_vline(data = cutoffs_df,
             aes(xintercept = active_cutoff),
             color = "firebrick", linewidth = 0.6) +
  geom_vline(xintercept = c(CUTOFF_PRE, CUTOFF_POST),
             color = "grey50", linetype = "dashed", linewidth = 0.3) +
  facet_wrap(~ period, ncol = 1) +
  scale_x_continuous(breaks = seq(0, 1200, 120),
                     labels = \(s) sprintf("%d:%02d", s %/% 60, s %% 60)) +
  scale_y_continuous(labels = comma) +
  labs(
    title = "Video duration density around the mid-roll cutoffs (pilot sample)",
    subtitle = paste0("Solid red = active threshold in that period. ",
                      "Dashed = the other period's threshold for reference."),
    x = "Video duration (mm:ss)",
    y = "Number of videos (1-second bins)"
  ) +
  theme_minimal(base_size = 11)

ggsave("figures/fig1_duration_hist.png", p_main,
       width = 9, height = 6, dpi = 300)

# Zoomed views
p_post_zoom <- ggplot(filter(plot_df, period == "Post-policy (2020-07-27 onward)",
                             duration_sec >= 360, duration_sec <= 600),
                      aes(x = duration_sec)) +
  geom_histogram(binwidth = 1, boundary = 0, fill = "grey30") +
  geom_vline(xintercept = CUTOFF_POST, color = "firebrick", linewidth = 0.6) +
  scale_x_continuous(breaks = seq(360, 600, 30),
                     labels = \(s) sprintf("%d:%02d", s %/% 60, s %% 60)) +
  labs(title = "Zoom: 6:00-10:00 in the post-policy period",
       subtitle = "Bunching mass should sit immediately above 8:00.",
       x = "Duration", y = "Videos") +
  theme_minimal(base_size = 11)
ggsave("figures/duration_hist_zoom480.png", p_post_zoom,
       width = 8, height = 4, dpi = 300)

p_pre_zoom <- ggplot(filter(plot_df, period == "Pre-policy (before 2020-07-27)",
                            duration_sec >= 480, duration_sec <= 720),
                     aes(x = duration_sec)) +
  geom_histogram(binwidth = 1, boundary = 0, fill = "grey30") +
  geom_vline(xintercept = CUTOFF_PRE, color = "firebrick", linewidth = 0.6) +
  scale_x_continuous(breaks = seq(480, 720, 30),
                     labels = \(s) sprintf("%d:%02d", s %/% 60, s %% 60)) +
  labs(title = "Zoom: 8:00-12:00 in the pre-policy period",
       subtitle = "Bunching mass should sit immediately above 10:00.",
       x = "Duration", y = "Videos") +
  theme_minimal(base_size = 11)
ggsave("figures/duration_hist_zoom600.png", p_pre_zoom,
       width = 8, height = 4, dpi = 300)

# -------- write a notes file for Section 1 ------------------------------------
notes_lines <- c(
  "# Pilot exploration findings",
  "",
  paste0("_Generated by code/03_explore_pilot.R on ", Sys.Date(), "._"),
  "",
  "## Scope",
  "",
  paste0("- Rows: ", nrow(videos)),
  paste0("- Unique channels: ", n_distinct(videos$channel_id)),
  paste0("- Date range: ",
         min(as.Date(videos$published_at), na.rm = TRUE), " to ",
         max(as.Date(videos$published_at), na.rm = TRUE)),
  "",
  "## Summary stats (key variables)",
  "",
  paste(capture.output(print(summary_tbl, n = Inf)), collapse = "\n"),
  "",
  "## Data quality flags",
  "",
  paste(capture.output(print(qc, n = Inf)), collapse = "\n"),
  "",
  "## Figures",
  "",
  "- figures/fig1_duration_hist.png  (Figure 1 candidate)",
  "- figures/duration_hist_zoom480.png",
  "- figures/duration_hist_zoom600.png"
)
writeLines(notes_lines, "docs/pilot-findings.md")
cat("\nWrote: docs/pilot-findings.md\n")
