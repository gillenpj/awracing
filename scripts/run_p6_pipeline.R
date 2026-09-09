# scripts/run_p6_pipeline.R
# Driver for the paper-6 pipeline. Exists for the same two reasons paper 5's
# does: `Rscript -e` does not activate renv on this machine, and the
# script/store pair must be passed explicitly on every call — paper 6 never
# writes `_targets.yaml`.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/run_p6_pipeline.R
# from the project root, via PowerShell (torch and the RMariaDB connection
# both crash under the Bash tool's Git Bash environment).
#
# An optional argument names the target to build up to, so the declaration can
# be frozen and committed before any test target exists:
#   Rscript scripts/run_p6_pipeline.R p6_declared_rules_file

source("renv/activate.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0L) {
  targets::tar_make(script = "_targets_p6.R", store = "_targets_p6")
} else {
  targets::tar_make(names = tidyselect::any_of(args),
                    script = "_targets_p6.R", store = "_targets_p6")
}
