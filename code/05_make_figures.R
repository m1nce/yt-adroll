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
plot_df <- df |> filter(duration_sec <= 1200L)

cutoffs_df <- tibble(
  period   = factor(levels(df$period), levels = levels(df$period)),
  active   = c(CUTOFF_PRE, CUTOFF_POST),
  inactive = c(CUTOFF_POST, CUTOFF_PRE)
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
zoom      <- 90L
plac_cuts <- c(420L, 540L, 660L)

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
