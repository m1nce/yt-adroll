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

# ---- helper: extract rddensity result to a tidy row -------------------------
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
# 600s in post-policy -> expect null (creators moved to 480s)
m3a <- rddensity(X = post_df$duration_sec, c = CUTOFF_PRE)
# 480s in pre-policy -> expect null (threshold was 600s then)
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
            median_views   = median(view_count, na.rm = TRUE),
            mean_log_views = mean(log_views,    na.rm = TRUE),
            .groups = "drop")
print(group_stats)
tv <- t.test(log_views ~ above, data = eng)
results[["a4"]] <- tibble(
  analysis = "Engagement: log views above vs below 480s (h=30s)",
  estimate = diff(tv$estimate),    # above minus below
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

# ---- write ------------------------------------------------------------------
out <- bind_rows(results)
write_csv(out, "data/analysis_results.csv")
cat("\nWrote data/analysis_results.csv\n")
print(out |> select(analysis, estimate, t_stat, p_value))
