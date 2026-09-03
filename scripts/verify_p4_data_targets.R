# verify_p4_data_targets.R
#
# Standing gate tying paper 4's data-section targets to the P4-0 audit.
#
# The audit script `scripts/p4_audit_forecast_price.R` is the standalone
# record of the P4-0 gate. The paper's data section reads live targets in
# the `_targets_p4` store instead, so that no number in the prose is a
# transcription. Two computations of the same quantity can drift apart;
# this asserts they have not.
#
# Run after any change to `R/p4_data_summaries.R` or to the audit script:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_p4_data_targets.R
#
# Read-only.

source("renv/activate.R")
suppressPackageStartupMessages(library(dplyr))

P4_STORE   <- "_targets_p4"
AUDIT_RDS  <- "scripts/p4_audit_forecast_price.rds"

stopifnot("audit rds missing - run scripts/p4_audit_forecast_price.R first" =
            file.exists(AUDIT_RDS))
audit <- readRDS(AUDIT_RDS)

cat("verify_p4_data_targets: start\n")

overround   <- targets::tar_read(p4_overround, store = P4_STORE)
compression <- targets::tar_read(p4_compression, store = P4_STORE)
coverage    <- targets::tar_read(p4_coverage, store = P4_STORE)
common      <- targets::tar_read(p4_common, store = P4_STORE)

# ---- 1. Median overround of the archived forecast book ------------------
# The audit computed each price on its own complete set of races; the
# paper's table 4 puts all three on the races complete in all three, so
# the tie-back uses `by_source_own`, which is the audit's quantity.
target_median <- overround$by_source_own$median[
  overround$by_source_own$source == "Archived forecast"]
cat(sprintf("  [1] archive overround median: target %.6f, audit %.6f\n",
            target_median, audit$median_or_fp))
stopifnot("archive overround median disagrees with the P4-0 audit" =
            abs(target_median - audit$median_or_fp) < 1e-6)

# ---- 2. Within-race compression slope -----------------------------------
target_slope <- compression$fit_summary$slope
audit_slope  <- audit$shape_slopes$slope[audit$shape_slopes$spec == "within_race"]
cat(sprintf("  [2] within-race compression slope: target %.6f, audit %.6f\n",
            target_slope, audit_slope))
stopifnot("compression slope disagrees with the P4-0 audit" =
            abs(target_slope - audit_slope) < 1e-6)

# ---- 3. Archive coverage on the test split ------------------------------
target_cov <- coverage$by_split$archive_pct[coverage$by_split$split == "test"]
audit_cov  <- audit$cov_rows$fp_pct[audit$cov_rows$split == "test"]
cat(sprintf("  [3] archive row coverage, test split: target %.6f, audit %.6f\n",
            target_cov, audit_cov))
stopifnot("test-split archive coverage disagrees with the P4-0 audit" =
            abs(target_cov - audit_cov) < 1e-6)

# ---- 4. The restated condition-4 gate -----------------------------------
# P4-0's condition 4 was restated as "every runner the pipeline uses has a
# usable price". On the archived forecast column over the test universe
# that must be 100%, or the paper's race set is not what it claims.
arch_pct <- common$accounting$pct_complete[
  common$accounting$price_set == "C — archived racecard forecast"]
cat(sprintf("  [4] test-universe races fully priced (archive): %.4f\n", arch_pct))
stopifnot("the restated P4-0 condition 4 no longer holds" = arch_pct == 1)

# ---- 5. The intersection is what the paper says it is -------------------
n_common <- length(common$race_ids)
inter <- common$accounting$races_complete[
  common$accounting$price_set == "intersection (all three)"]
cat(sprintf("  [5] intersection race set: %d races (accounting says %d)\n",
            n_common, inter))
stopifnot("the intersection race count disagrees with its own accounting" =
            n_common == inter)

# ---- 6. Distributional work is training-split only ----------------------
# The overround and compression summaries must never have seen a test race.
full_panel <- targets::tar_read(p4_full_panel, store = P4_STORE)
train_ids  <- full_panel$race_id[full_panel$split == "train"]
stopifnot(
  "compression was computed on races outside the training split" =
    all(compression$points$race_id %in% train_ids),
  "overround was computed on races outside the training split" =
    all(overround$race_level$race_id %in% train_ids)
)
cat(sprintf("  [6] overround and compression use training races only (%d races)\n",
            dplyr::n_distinct(compression$points$race_id)))

# ---- 7. The common-set overround table sits on ONE race set ------------
stopifnot(
  "table 4's three prices are not on a common race set" =
    length(unique(overround$by_source$races)) == 1L,
  "the common overround set is not a subset of the per-price sets" =
    all(overround$by_source$races <= overround$by_source_own$races)
)
cat(sprintf("  [7] all three prices on one set of %d races (own sets: %s)\n",
            overround$by_source$races[1],
            paste(overround$by_source_own$races, collapse = ", ")))

cat("verify_p4_data_targets: ALL CHECKS PASSED\n")
