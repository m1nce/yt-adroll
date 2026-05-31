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
