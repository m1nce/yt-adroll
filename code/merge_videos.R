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
