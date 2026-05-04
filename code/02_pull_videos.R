#!/usr/bin/env Rscript
# 02_pull_videos.R
#
# Pull video metadata for the pilot channels via YouTube Data API v3.
# Idempotent: per-channel responses are cached under data/raw/{channel_id}.parquet,
# so reruns spend near-zero quota. The same script handles the full pull
# later by switching the input from channels_pilot.parquet to channels.parquet.
#
# Input:  data/channels_pilot.parquet (or data/channels.parquet for full pull)
# Output: data/pilot_videos.parquet  (all videos from those channels)
#
# Quota math: per channel ~ 1 (channels.list) + ceil(N_videos/50) (playlistItems)
#                          + ceil(N_videos/50) (videos.list)
#   => ~80 units per very-active channel; 30 channels well under daily 10K quota.
#
# Auth: reads YOUTUBE_API_KEY from .env (or environment).

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(arrow)
  library(lubridate)
})

# -------- config --------------------------------------------------------------
INPUT_PATH    <- Sys.getenv("VIDEO_PULL_INPUT", "data/channels_pilot.parquet")
OUTPUT_PATH   <- Sys.getenv("VIDEO_PULL_OUTPUT", "data/pilot_videos.parquet")
RAW_DIR       <- "data/raw"
DATE_FROM     <- as.Date("2018-01-01")
DATE_TO       <- as.Date("2023-12-31")
API_BASE      <- "https://www.googleapis.com/youtube/v3"

# -------- env / api key -------------------------------------------------------
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

dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

# -------- API helpers ---------------------------------------------------------
yt_get <- function(endpoint, query) {
  query$key <- api_key
  req <- request(paste0(API_BASE, "/", endpoint)) |>
    req_url_query(!!!query) |>
    req_retry(max_tries = 3, backoff = \(i) min(2 ^ i, 30)) |>
    req_error(is_error = \(resp) FALSE)
  resp <- req_perform(req)
  if (resp_status(resp) >= 400) {
    body <- tryCatch(resp_body_json(resp), error = \(e) list())
    stop("YouTube API error ", resp_status(resp), ": ",
         body$error$message %||% resp_body_string(resp))
  }
  resp_body_json(resp, simplifyVector = FALSE)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# -------- per-channel pull ----------------------------------------------------
get_uploads_playlist <- function(channel_id) {
  resp <- yt_get("channels", list(part = "contentDetails", id = channel_id))
  items <- resp$items
  if (length(items) == 0) return(NA_character_)
  items[[1]]$contentDetails$relatedPlaylists$uploads %||% NA_character_
}

get_video_ids <- function(uploads_playlist_id) {
  ids <- character()
  page_token <- NULL
  repeat {
    q <- list(part = "contentDetails", playlistId = uploads_playlist_id,
              maxResults = 50)
    if (!is.null(page_token)) q$pageToken <- page_token
    resp <- yt_get("playlistItems", q)
    page_ids <- vapply(resp$items,
                       \(it) it$contentDetails$videoId %||% NA_character_,
                       character(1))
    ids <- c(ids, page_ids[!is.na(page_ids)])
    page_token <- resp$nextPageToken
    if (is.null(page_token)) break
  }
  ids
}

iso_duration_to_seconds <- function(iso) {
  # PT#H#M#S -> seconds. Vectorized.
  h <- as.numeric(sub(".*?(\\d+)H.*", "\\1", iso));
  h[!grepl("H", iso)] <- 0
  m <- as.numeric(sub(".*?(\\d+)M.*", "\\1", iso));
  m[!grepl("M", iso)] <- 0
  s <- as.numeric(sub(".*?(\\d+)S.*", "\\1", iso));
  s[!grepl("S", iso)] <- 0
  3600 * h + 60 * m + s
}

get_video_details <- function(video_ids) {
  if (length(video_ids) == 0) return(tibble())
  chunks <- split(video_ids, ceiling(seq_along(video_ids) / 50))
  rows <- map(chunks, \(ids) {
    resp <- yt_get("videos",
                   list(part = "snippet,contentDetails,statistics",
                        id = paste(ids, collapse = ",")))
    map(resp$items, \(it) {
      tibble(
        video_id       = it$id %||% NA_character_,
        channel_id     = it$snippet$channelId %||% NA_character_,
        channel_title  = it$snippet$channelTitle %||% NA_character_,
        category_id    = it$snippet$categoryId %||% NA_character_,
        published_at   = it$snippet$publishedAt %||% NA_character_,
        title          = it$snippet$title %||% NA_character_,
        duration_iso   = it$contentDetails$duration %||% NA_character_,
        view_count     = as.numeric(it$statistics$viewCount %||% NA),
        like_count     = as.numeric(it$statistics$likeCount %||% NA),
        comment_count  = as.numeric(it$statistics$commentCount %||% NA)
      )
    }) |> bind_rows()
  })
  bind_rows(rows)
}

pull_channel <- function(channel_id) {
  cache_file <- file.path(RAW_DIR, paste0(channel_id, ".parquet"))
  if (file.exists(cache_file)) {
    return(read_parquet(cache_file))
  }
  message("Pulling ", channel_id, " ...")
  uploads <- get_uploads_playlist(channel_id)
  if (is.na(uploads)) {
    message("  (no uploads playlist; skipping)")
    out <- tibble()
    write_parquet(out, cache_file)
    return(out)
  }
  vids <- get_video_ids(uploads)
  details <- get_video_details(vids)
  if (nrow(details) > 0) {
    details <- details |>
      mutate(
        published_at = ymd_hms(published_at, quiet = TRUE),
        duration_sec = iso_duration_to_seconds(duration_iso)
      )
  }
  write_parquet(details, cache_file)
  details
}

# -------- run -----------------------------------------------------------------
channels <- read_parquet(INPUT_PATH)
cat("Pulling", nrow(channels), "channels from", INPUT_PATH, "\n")

all_videos <- map(channels$channel_id, pull_channel) |>
  bind_rows()

cat("Raw rows pulled:", nrow(all_videos), "\n")

# Filter to study window. Keep raw cache untouched.
filtered <- all_videos |>
  filter(!is.na(published_at),
         as.Date(published_at) >= DATE_FROM,
         as.Date(published_at) <= DATE_TO)

cat("After 2018-01..2023-12 window:", nrow(filtered), "\n")

# Join channel metadata for downstream analysis (size bucket, etc.)
joined <- filtered |>
  left_join(
    channels |> select(channel_id, subscriber_count, primary_category),
    by = "channel_id"
  )

write_parquet(joined, OUTPUT_PATH)
cat("Wrote:", OUTPUT_PATH, "\n")
