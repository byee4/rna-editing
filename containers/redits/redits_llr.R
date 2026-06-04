#!/usr/bin/env Rscript

# redits_llr.R — apply REDIT-LLR (gxiaolab/REDITs) site-by-site.
#
# Input  (--counts): tab-delimited, header row. First two columns are `chrom` and `pos`;
#         every remaining column is one sample, and each cell is "edited,total"
#         (e.g. "8,40"). Column order defines sample order.
# Groups (--groups): comma-separated condition labels aligned to the sample columns,
#         exactly two distinct labels (REDIT-LLR is a two-group test).
# Output (--output): tab-delimited `chrom  pos  p_value`, one row per input site.
#
# Per the REDIT_LLR.R source, the data matrix is 2xN with row 1 = non-edited (G) counts and
# row 2 = edited (A) counts; the p-value is returned under [['p.value']].

suppressWarnings(suppressMessages({
  src <- Sys.getenv("REDITS_SRC", "/opt/redits-src")
  source(file.path(src, "REDIT_LLR.R"))
}))

parse_args <- function(argv) {
  out <- list(counts = NULL, groups = NULL, output = NULL)
  i <- 1
  while (i <= length(argv)) {
    key <- argv[[i]]
    val <- if (i + 1 <= length(argv)) argv[[i + 1]] else NA
    if (key == "--counts")       out$counts <- val
    else if (key == "--groups")  out$groups <- val
    else if (key == "--output")  out$output <- val
    else if (key %in% c("-h", "--help")) {
      cat("Usage: redits_llr.R --counts FILE --groups g1,g1,g2,g2 --output FILE\n")
      quit(status = 0)
    } else stop(sprintf("Unknown argument: %s", key))
    i <- i + 2
  }
  if (is.null(out$counts) || is.null(out$groups) || is.null(out$output)) {
    stop("--counts, --groups and --output are all required")
  }
  out
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

groups <- trimws(strsplit(args$groups, ",", fixed = TRUE)[[1]])
if (length(unique(groups)) != 2) {
  stop(sprintf("REDIT-LLR needs exactly two groups; got: %s",
               paste(unique(groups), collapse = ", ")))
}

counts <- read.table(args$counts, header = TRUE, sep = "\t",
                     check.names = FALSE, stringsAsFactors = FALSE,
                     colClasses = "character")
if (!all(c("chrom", "pos") %in% colnames(counts)[1:2])) {
  stop("first two columns of --counts must be 'chrom' and 'pos'")
}
sample_cols <- colnames(counts)[-(1:2)]
if (length(sample_cols) != length(groups)) {
  stop(sprintf("groups length (%d) != number of sample columns (%d)",
               length(groups), length(sample_cols)))
}

# "edited,total" -> c(edited, total)
split_cell <- function(cell) as.numeric(strsplit(cell, ",", fixed = TRUE)[[1]])

con <- file(args$output, "w")
on.exit(close(con))
writeLines("chrom\tpos\tp_value", con)

for (r in seq_len(nrow(counts))) {
  edited <- numeric(length(sample_cols))
  total  <- numeric(length(sample_cols))
  for (s in seq_along(sample_cols)) {
    et <- split_cell(counts[r, sample_cols[s]])
    edited[s] <- et[1]
    total[s]  <- et[2]
  }
  non_edited <- total - edited
  mat <- rbind(non_edited, edited)            # row1 = G (non-edited), row2 = A (edited)
  pval <- tryCatch(REDIT_LLR(data = mat, groups = groups)[["p.value"]],
                   error = function(e) NA_real_)
  writeLines(sprintf("%s\t%s\t%.6g", counts[r, "chrom"], counts[r, "pos"], pval), con)
}
