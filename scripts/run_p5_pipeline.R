# scripts/run_p5_pipeline.R
# Driver for the paper-5 pipeline. Exists because `Rscript -e` does not
# activate renv on this machine, and because the script/store pair must be
# passed explicitly on every call — paper 5 never writes `_targets.yaml`.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/run_p5_pipeline.R
# from the project root, via PowerShell (torch and the RMariaDB connection
# both crash under the Bash tool's Git Bash environment).

source("renv/activate.R")
targets::tar_make(script = "_targets_p5.R", store = "_targets_p5")
