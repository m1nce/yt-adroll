#!/usr/bin/env Rscript
# 00_resolve_channels.R
#
# Resolve a hand-curated list of YouTube channel handles / URLs / IDs into
# a verified channels_raw.csv with:
#   channel_id, channel_title, subscriber_count, primary_category, custom_url
#
# Input:  data/channels_seeds.csv with columns:
#           handle_or_url      one of: @handle, channel URL, or UC... ID
#           primary_category   one of the six allowed categories
#
# Output: data/channels_raw.csv (the input that 01_pull_channels.R expects)
#
# Quota: 1 unit per resolution call. 50 seeds = 50 units. Trivial.
#
# Auth: reads YOUTUBE_API_KEY from .env (or environment).

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(readr)
  library(purrr)
})

ALLOWED_CATEGORIES <- c(
  "Gaming", "People & Blogs", "Education", "Sports",
  "Howto & Style", "Entertainment", "Comedy"
)

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

yt_get <- function(query) {
  query$key <- api_key
  resp <- request(paste0(API_BASE, "/channels")) |>
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

# Parse a free-form input into one of: id=UC..., handle=@..., username=...
parse_target <- function(x) {
  x <- trimws(x)
  if (grepl("^UC[A-Za-z0-9_-]{22}$", x)) {
    return(list(kind = "id", value = x))
  }
  # Channel URL forms
  m <- regmatches(x, regexec("youtube\\.com/(channel|c|user|@[^/?#]+)/?([^/?#]*)?", x))[[1]]
  if (length(m) >= 2 && nchar(m[2]) > 0) {
    seg1 <- m[2]
    seg2 <- if (length(m) >= 3) m[3] else ""
    if (seg1 == "channel" && grepl("^UC", seg2)) return(list(kind = "id", value = seg2))
    if (seg1 == "user")    return(list(kind = "username", value = seg2))
    if (seg1 == "c")       return(list(kind = "handle", value = paste0("@", seg2)))
    if (startsWith(seg1, "@")) return(list(kind = "handle", value = seg1))
  }
  # Bare @handle
  if (startsWith(x, "@")) return(list(kind = "handle", value = x))
  # Bare username
  list(kind = "handle", value = paste0("@", x))
}

resolve_one <- function(input, primary_category) {
  t <- parse_target(input)
  q <- list(part = "snippet,statistics,brandingSettings")
  q[[switch(t$kind, id = "id", handle = "forHandle", username = "forUsername")]] <- t$value
  resp <- yt_get(q)
  items <- resp$items
  if (length(items) == 0) {
    warning("No match for ", input)
    return(tibble(input = input, primary_category = primary_category,
                  channel_id = NA_character_, channel_title = NA_character_,
                  subscriber_count = NA_real_, custom_url = NA_character_,
                  resolved = FALSE))
  }
  it <- items[[1]]
  tibble(
    input             = input,
    primary_category  = primary_category,
    channel_id        = it$id %||% NA_character_,
    channel_title     = it$snippet$title %||% NA_character_,
    subscriber_count  = as.numeric(it$statistics$subscriberCount %||% NA),
    custom_url        = it$snippet$customUrl %||% NA_character_,
    channel_created   = as.Date(substr(it$snippet$publishedAt %||% NA_character_, 1, 10)),
    resolved          = TRUE
  )
}

seeds_path <- "data/channels_seeds.csv"
if (!file.exists(seeds_path)) {
  stop(
    "Missing ", seeds_path, ".\n",
    "Create a CSV with columns: handle_or_url, primary_category. ",
    "See data/channels_seeds_template.csv for the expected schema."
  )
}

seeds <- read_csv(seeds_path, show_col_types = FALSE)
required <- c("handle_or_url", "primary_category")
miss <- setdiff(required, names(seeds))
if (length(miss)) stop("seeds missing columns: ", paste(miss, collapse = ", "))

bad_cat <- setdiff(seeds$primary_category, ALLOWED_CATEGORIES)
if (length(bad_cat)) {
  warning("Seeds with disallowed categories will be dropped: ",
          paste(bad_cat, collapse = ", "))
  seeds <- filter(seeds, primary_category %in% ALLOWED_CATEGORIES)
}

cat("Resolving", nrow(seeds), "seed channels...\n")
resolved <- map2_dfr(seeds$handle_or_url, seeds$primary_category, resolve_one)

ok <- filter(resolved, resolved == TRUE,
             subscriber_count >= 10000, subscriber_count <= 1000000)
out_of_band <- filter(resolved, resolved == TRUE,
                      (subscriber_count < 10000 |
                         subscriber_count > 1000000))
unresolved <- filter(resolved, resolved == FALSE)

cat("\nResolved & in 10K-1M band: ", nrow(ok), "\n")
cat("Resolved but out-of-band:   ", nrow(out_of_band), "\n")
cat("Could not resolve:          ", nrow(unresolved), "\n")

if (nrow(out_of_band) > 0) {
  cat("\nOut-of-band (will not be written to channels_raw.csv):\n")
  print(select(out_of_band, input, channel_title, subscriber_count))
}
if (nrow(unresolved) > 0) {
  cat("\nUnresolved (typo or deleted channel?):\n")
  print(select(unresolved, input))
}

out <- ok |>
  mutate(window_coverage = case_when(
    is.na(channel_created)                   ~ "unknown",
    channel_created <  as.Date("2019-01-01") ~ "full (pre-2019 channel)",
    channel_created <  as.Date("2020-07-27") ~ "partial pre-policy",
    TRUE                                     ~ "post-policy only"
  )) |>
  select(channel_id, channel_title, subscriber_count, primary_category,
         custom_url, channel_created, window_coverage) |>
  arrange(primary_category, desc(subscriber_count))

cat("\nFinal channel counts by category:\n")
print(count(out, primary_category, sort = TRUE))

cat("\nWindow coverage distribution:\n")
print(count(out, window_coverage, sort = TRUE))

write_csv(out, "data/channels_raw.csv")
cat("\nWrote: data/channels_raw.csv (", nrow(out), " rows)\n", sep = "")
