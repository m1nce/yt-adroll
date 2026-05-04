#!/usr/bin/env Rscript
# 00b_discover_candidates.R
#
# Auto-populate data/channels_seeds.csv with candidate channels for the
# pilot. For each (category, query) pair, calls
# search.list?type=video&videoCategoryId=XX&q=...&order=viewCount, extracts
# the unique channel IDs, fetches subscriber counts via channels.list, and
# filters to the 10K-1M subscriber band. Gaming and Sports get multiple
# queries to widen the candidate pool for those categories.
#
# Quota: ~12 search.list calls (100 units each) + ~3-6 channels.list batch
# calls (1 unit each) = ~1,205 units. Leaves ~8,800 units for the rest of
# the day.
#
# Output: data/channels_seeds.csv  (handle_or_url, primary_category)
#         data/channels_candidates_full.csv  (richer; includes filtered-out
#           channels with sub counts, useful for picking manual additions)
#
# After running this:
#   1. Open data/channels_seeds.csv and edit. Drop ones that look off-topic;
#      add @handles for creators you personally want represented.
#   2. Run code/00_resolve_channels.R to verify every entry against the API
#      and produce data/channels_raw.csv.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(readr)
  library(purrr)
  library(tibble)
})

# Allowed YouTube category IDs, their human-readable names, and a generic
# query term. The YouTube search.list endpoint returns 0 items when
# videoCategoryId is supplied without a q parameter, so each category gets
# a broad seed term that nudges the filter into producing results.
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
  "26",         "Howto & Style",    "how to",
  "24",         "Entertainment",    "review",
  "23",         "Comedy",           "comedy",
  "23",         "Comedy",           "sketch comedy",
  "23",         "Comedy",           "standup",
  "23",         "Comedy",           "parody"
)

PUBLISHED_AFTER <- "2024-01-01T00:00:00Z"
SUB_MIN <- 10000L
SUB_MAX <- 1000000L

API_BASE <- "https://www.googleapis.com/youtube/v3"

load_env <- function(path = ".env") {
  if (!file.exists(path)) return(invisible())
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines) & !startsWith(trimws(lines), "#")]
  for (ln in lines) {
    kv <- regmatches(ln, regexec("^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.*)$", ln))[[1]]
    if (length(kv) == 3) {
      val <- kv[3]
      val <- sub('^"(.*)"$', "\\1", val)
      val <- sub("^'(.*)'$", "\\1", val)
      do.call(Sys.setenv, setNames(list(val), kv[2]))
    }
  }
}
load_env()

api_key <- Sys.getenv("YOUTUBE_API_KEY")
if (!nzchar(api_key)) {
  stop("YOUTUBE_API_KEY not set. Copy .env.example to .env and fill it in.")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

yt_get <- function(endpoint, query) {
  query$key <- api_key
  resp <- request(paste0(API_BASE, "/", endpoint)) |>
    req_url_query(!!!query) |>
    req_retry(max_tries = 3, backoff = \(i) min(2 ^ i, 30)) |>
    req_error(is_error = \(r) FALSE) |>
    req_perform()
  if (resp_status(resp) >= 400) {
    body <- tryCatch(resp_body_json(resp), error = \(e) list())
    stop("YouTube API error ", resp_status(resp), ": ",
         body$error$message %||% resp_body_string(resp))
  }
  resp_body_json(resp, simplifyVector = FALSE)
}

discover_in_category <- function(category_id, primary_category, query) {
  cat("Searching category", category_id, "(", primary_category, ")...\n")
  resp <- yt_get("search", list(
    part              = "snippet",
    type              = "video",
    q                 = query,
    videoCategoryId   = category_id,
    order             = "viewCount",
    publishedAfter    = PUBLISHED_AFTER,
    relevanceLanguage = "en",
    regionCode        = "US",
    maxResults        = 50
  ))
  ids <- vapply(resp$items,
                \(it) it$snippet$channelId %||% NA_character_,
                character(1))
  ids <- unique(ids[!is.na(ids)])
  cat("  unique channels surfaced:", length(ids), "\n")
  tibble(channel_id = ids, primary_category = primary_category)
}

candidates <- pmap_dfr(list(CATEGORIES$category_id,
                            CATEGORIES$primary_category,
                            CATEGORIES$query),
                       discover_in_category)

# A channel may surface in more than one category search. Keep the first
# (most-viewed-context) assignment; the resolver step is the source of truth.
candidates <- candidates |>
  group_by(channel_id) |>
  slice(1) |>
  ungroup()

cat("\nUnique candidate channels across all categories:",
    nrow(candidates), "\n")

# Batch channels.list for sub counts and titles.
batch_ids <- function(ids, n = 50) split(ids, ceiling(seq_along(ids) / n))
chan_info <- map_dfr(batch_ids(candidates$channel_id), \(ids) {
  resp <- yt_get("channels", list(
    part = "snippet,statistics",
    id   = paste(ids, collapse = ",")
  ))
  map_dfr(resp$items, \(it) tibble(
    channel_id        = it$id %||% NA_character_,
    channel_title     = it$snippet$title %||% NA_character_,
    custom_url        = it$snippet$customUrl %||% NA_character_,
    subscriber_count  = as.numeric(it$statistics$subscriberCount %||% NA),
    video_count       = as.numeric(it$statistics$videoCount %||% NA),
    hidden_subs       = isTRUE(it$statistics$hiddenSubscriberCount),
    country           = it$snippet$country %||% NA_character_,
    channel_created   = as.Date(substr(it$snippet$publishedAt %||% NA_character_, 1, 10))
  ))
})

full <- candidates |>
  left_join(chan_info, by = "channel_id") |>
  mutate(
    in_band = !hidden_subs &
              !is.na(subscriber_count) &
              subscriber_count >= SUB_MIN &
              subscriber_count <= SUB_MAX,
    window_coverage = case_when(
      is.na(channel_created)                  ~ "unknown",
      channel_created <  as.Date("2019-01-01") ~ "full (pre-2019 channel)",
      channel_created <  as.Date("2020-07-27") ~ "partial pre-policy",
      TRUE                                    ~ "post-policy only"
    )
  )

cat("\nIn 10K-1M band by category:\n")
full |> filter(in_band) |> count(primary_category, sort = TRUE) |> print()

cat("\nIn-band channels by window coverage:\n")
full |> filter(in_band) |>
  count(window_coverage, sort = TRUE) |> print()

cat("\nOut of band (above 1M, below 10K, or hidden):\n")
full |> filter(!in_band) |> count(primary_category, sort = TRUE) |> print()

write_csv(full, "data/channels_candidates_full.csv")

seeds <- full |>
  filter(in_band) |>
  mutate(handle_or_url = if_else(!is.na(custom_url) & nzchar(custom_url),
                                 custom_url, channel_id)) |>
  select(handle_or_url, primary_category) |>
  distinct()

write_csv(seeds, "data/channels_seeds.csv")
cat("\nWrote: data/channels_seeds.csv (",
    nrow(seeds), " in-band candidates)\n", sep = "")
cat("Wrote: data/channels_candidates_full.csv (review this to find ",
    "out-of-band channels you might want anyway, e.g., near the band ",
    "boundaries)\n", sep = "")
