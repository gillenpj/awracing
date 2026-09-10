#!/usr/bin/env Rscript
# publish_docs.R — copy rendered paper outputs into the committed docs/
# GitHub Pages tree.
#
# Run AFTER `tar_make()` (which renders each paper to _output/index.html +
# _output/index.pdf), then commit + push docs/:
#
#     "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/publish_docs.R
#     git add docs/ && git commit -m "Publish: refresh rendered papers" && git push
#
# Why a local script and not a GitHub Action: Pages serves the committed
# main:/docs tree directly (no build workflow), and the {targets} render
# needs the local Smartform MySQL database, so rendering cannot run in CI.
# The only "publish" step is this copy of the gitignored _output/ files
# into the tracked docs/ tree.
#
# Self-contained: uses only base R (no renv packages), so it runs as a
# plain `Rscript scripts/publish_docs.R` without activating renv.
#
# The landing page docs/index.html (one entry per paper, with an HTML link
# and a "-- PDF" link) is maintained by hand; this script does not touch
# it. To publish a NEW paper: add a row to `papers` below, then add its
# entry to docs/index.html.

# Resolve project root from this script's own location (scripts/ under
# root), falling back to the working directory.
local({
  args <- commandArgs(trailingOnly = FALSE)
  fa   <- sub("^--file=", "", args[grepl("^--file=", args)])
  root <<- if (length(fa)) normalizePath(file.path(dirname(fa[1]), ".."))
           else normalizePath(getwd())
})

# paper source dir (under papers/)  ->  docs/ subfolder
papers <- c(
  "01_replication"            = "paper1",
  "02a_extended_win_model"    = "paper2a",
  "02b_ranking_model"         = "paper2b",
  "03_gradient_boosted_trees" = "paper3",
  "04_market_blend"           = "paper4",
  "05_encoder"                = "paper5",
  "06_betting_strategy"       = "paper6"
)

copied  <- character(0)
missing <- character(0)
for (src in names(papers)) {
  out_dir  <- file.path(root, "papers", src, "_output")
  dest_dir <- file.path(root, "docs", papers[[src]])
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  for (f in c("index.html", "index.pdf")) {
    from <- file.path(out_dir, f)
    if (file.exists(from)) {
      file.copy(from, file.path(dest_dir, f), overwrite = TRUE)
      copied <- c(copied, file.path("docs", papers[[src]], f))
    } else {
      missing <- c(missing, from)
    }
  }
}

# Supplementary material — standalone reference documents copied straight
# from notes/, not produced by any paper's render. notes/*.pdf is
# gitignored, so this file exists only on machines that have it locally;
# a fresh clone has no way to reproduce it (see CLAUDE.md's "Project
# structure" note on the note's provenance). Fail loudly rather than
# skipping it, since a silent skip would leave the published copy stale
# with no indication anything was wrong.
#
# Paper 5's supplement is different in kind: it IS reproducible, being
# rendered from committed Quarto source under papers/05_encoder/supplement/.
# Its _output/ is gitignored like every other render, so it is copied here
# the same way, and the same fail-loudly rule applies.
supplements <- list(
  list(
    src   = file.path(root, "notes", "Notes_on_Tree-based_Methods.pdf"),
    dest  = file.path(root, "docs", "paper3", "notes-on-tree-based-methods.pdf"),
    label = file.path("docs", "paper3", "notes-on-tree-based-methods.pdf"),
    hint  = paste(
      "notes/*.pdf is gitignored, so this file must already exist locally",
      "-- it is not reproduced by tar_make() or any other step. See",
      "CLAUDE.md's Project structure note on this file's provenance",
      "before recreating it."
    )
  ),
  list(
    src   = file.path(root, "papers", "05_encoder", "supplement", "_output",
                      "notes_on_neural_scorers.pdf"),
    dest  = file.path(root, "docs", "paper5", "notes-on-neural-scorers.pdf"),
    label = file.path("docs", "paper5", "notes-on-neural-scorers.pdf"),
    hint  = paste(
      "Render it first, from papers/05_encoder/supplement:",
      "quarto render notes_on_neural_scorers.qmd --to pdf.",
      "It has no executable chunks, so it needs neither renv nor the",
      "targets store."
    )
  )
)
for (s in supplements) {
  if (!file.exists(s$src)) {
    stop("Supplementary source file not found: ", s$src, "\n", s$hint,
         call. = FALSE)
  }
  if (!dir.exists(dirname(s$dest))) dir.create(dirname(s$dest), recursive = TRUE)
  file.copy(s$src, s$dest, overwrite = TRUE)
  copied <- c(copied, s$label)
}

if (length(copied)) {
  cat("Published:\n"); cat(paste0("  ", copied), sep = "\n"); cat("\n")
}
if (length(missing)) {
  cat("MISSING (run tar_make() first?):\n")
  cat(paste0("  ", missing), sep = "\n"); cat("\n")
  quit(status = 1L)
}
cat("Next: git add docs/ && git commit && git push\n")
