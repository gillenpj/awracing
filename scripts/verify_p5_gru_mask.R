# scripts/verify_p5_gru_mask.R
# Standing gate on paper 5's sequence encoder (`R/p5_gru.R`).
#
# Asserts that the GRU never reads padding, and that the state it reads is
# the right one. The three properties are described in
# `p5_check_gru_masking()`; the third is the one a pure invariance check
# would miss, because an off-by-one in the gather index leaves both
# invariances intact while summarising the wrong run.
#
# Run after any change to `R/p5_gru.R`:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_p5_gru_mask.R
# from the project root, via PowerShell.

source("renv/activate.R")

suppressMessages({
  library(torch)
})
source("R/p5_mlp.R")
source("R/p5_sequences.R")
source("R/p5_backend.R")
source("R/p5_gru.R")

cat("backend:\n")
print(as.data.frame(p5_capture_backend()))
cat("\n")

for (seed in c(42L, 7L, 2024L)) {
  cat("---- seed", seed, "----\n")
  out <- p5_check_gru_masking(seed = seed)
  print(as.data.frame(out))
  cat("\n")
}

cat("ALL ASSERTIONS PASSED\n")
