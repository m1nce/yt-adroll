#!/usr/bin/env Rscript
# 01_pull_channels.R
#
# Build the channel sample frame for the YouTube mid-roll RDD.
#
# Input:  data/channels_raw.csv  (manually curated from SocialBlade /
#         NoxInfluencer leaderboards). Required columns:
#             channel_id        YouTube UC... channel ID
#             channel_title     human-readable channel name
#             subscriber_count  integer
#             primary_category  one of the six allowed categories below
#
# Output: data/channels.parquet  (full filtered frame)
#         data/channels_pilot.parquet  (~5 channels per category)
#
# Pilot scope: ~30 channels stratified across the six allowed categories.
# Full scope (later): the full filtered frame, ~1,500 channels.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(arrow)
})

set.seed(20260503)  # for reproducible pilot stratification

ALLOWED_CATEGORIES <- c(
  "Gaming", "People & Blogs", "Education", "Sports",
  "Howto & Style", "Entertainment", "Comedy"
)

SUB_MIN <- 10000L
SUB_MAX <- 1000000L
PILOT_PER_CATEGORY <- 5L

raw_path <- "data/channels_raw.csv"
if (!file.exists(raw_path)) {
  stop(
    "Missing ", raw_path, ".\n",
    "Curate a CSV of candidate channels (10K-1M subs, six allowed ",
    "categories) from SocialBlade or NoxInfluencer and place it there. ",
    "Required columns: channel_id, channel_title, subscriber_count, ",
    "primary_category."
  )
}

raw <- read_csv(raw_path, show_col_types = FALSE)

required_cols <- c("channel_id", "channel_title", "subscriber_count",
                   "primary_category")
missing_cols <- setdiff(required_cols, names(raw))
if (length(missing_cols) > 0) {
  stop("channels_raw.csv missing columns: ",
       paste(missing_cols, collapse = ", "))
}

filtered <- raw |>
  filter(
    !is.na(channel_id),
    nchar(channel_id) > 0,
    subscriber_count >= SUB_MIN,
    subscriber_count <= SUB_MAX,
    primary_category %in% ALLOWED_CATEGORIES
  ) |>
  distinct(channel_id, .keep_all = TRUE)

cat("Raw channels:        ", nrow(raw), "\n")
cat("After filtering:     ", nrow(filtered), "\n")
cat("By category:\n")
print(count(filtered, primary_category, sort = TRUE))

write_parquet(filtered, "data/channels.parquet")

pilot <- filtered |>
  group_by(primary_category) |>
  slice_sample(n = PILOT_PER_CATEGORY) |>
  ungroup()

cat("\nPilot channels:      ", nrow(pilot), "\n")
write_parquet(pilot, "data/channels_pilot.parquet")

cat("\nWrote: data/channels.parquet, data/channels_pilot.parquet\n")
