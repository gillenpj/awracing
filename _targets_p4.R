# _targets_p4.R
#
# Paper 4 — marginal value of the model over the market.
#
# A SEPARATE pipeline with a SEPARATE store, so nothing here can touch
# papers 1-3. Run it with the script and store passed explicitly rather
# than through `_targets.yaml` (which the paper qmd setup chunks own):
#
#   targets::tar_make(script = "_targets_p4.R", store = "_targets_p4")
#   targets::tar_read(p4_arm_grid, store = "_targets_p4")
#
# Upstream inputs come from the MAIN store, read-only. Papers 2b and 3
# are reused as frozen fitted objects and are never refitted here; the
# `p4_upstream_fingerprint` target records the main store's content
# hashes for those targets so that if an upstream result ever changes,
# every paper-4 target downstream of it invalidates rather than silently
# going stale.

# -- Subprocess environment for `tar_quarto()` ----------------------------
# Identical to the block at the top of `_targets.R`, and load-bearing for
# the same reason: quarto.exe launches a fresh R session that inherits
# environment variables but not `.libPaths()`, so without these it picks
# system Rscript and never sees the renv library. See CLAUDE.md, "Render
# environment bootstrap".
Sys.setenv(R_LIBS   = paste(.libPaths(), collapse = .Platform$path.sep))
Sys.setenv(QUARTO_R = file.path(R.home("bin"), "Rscript.exe"))
if (Sys.getenv("QUARTO_PATH") == "") {
  candidates <- c(
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe",
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs/Quarto/bin/quarto.exe")
  )
  found <- candidates[file.exists(candidates)]
  if (length(found)) Sys.setenv(QUARTO_PATH = found[[1]])
}

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("dplyr", "tidyr", "tibble", "purrr", "stringr", "readr",
               "DBI", "RMariaDB", "mlogit", "splines"),
  format   = "rds"
)

tar_source("R/db.R")
tar_source("R/market_blend_p4.R")
tar_source("R/p4_data_summaries.R")
tar_source("R/p4_report.R")

MAIN_STORE <- "_targets"

list(

  # -- Upstream, from the frozen main store -------------------------------
  tar_target(
    p4_upstream_fingerprint,
    targets::tar_meta(
      names = c("test_predictions_2b", "test_predictions_3",
                "qualifying_runners"),
      fields = c("name", "data"),
      store  = MAIN_STORE
    )
  ),
  tar_target(
    p4_preds_2b,
    {
      p4_upstream_fingerprint
      targets::tar_read(test_predictions_2b, store = MAIN_STORE)
    }
  ),
  tar_target(
    p4_preds_3,
    {
      p4_upstream_fingerprint
      targets::tar_read(test_predictions_3, store = MAIN_STORE)
    }
  ),

  tar_target(
    p4_qualifying_runners,
    {
      p4_upstream_fingerprint
      targets::tar_read(qualifying_runners, store = MAIN_STORE)
    }
  ),
  tar_target(
    p4_qualifying_races,
    targets::tar_read(qualifying_races, store = MAIN_STORE)
  ),
  tar_target(
    p4_races_train,
    targets::tar_read(races_train, store = MAIN_STORE)
  ),

  # -- Data section: the whole 2006-2015 window ---------------------------
  tar_target(
    p4_raw_prices_all,
    read_p4_price_sources(sort(unique(p4_qualifying_races$race_id)))
  ),
  tar_target(
    p4_full_panel,
    build_p4_full_panel(p4_qualifying_runners, p4_qualifying_races,
                        p4_races_train, p4_raw_prices_all)
  ),
  tar_target(
    p4_provenance_facts,
    compute_p4_provenance_facts(
      race_ids       = sort(unique(p4_qualifying_races$race_id)),
      train_race_ids = p4_races_train$race_id,
      qualifying_runners = p4_qualifying_runners
    )
  ),
  tar_target(p4_coverage,    summarise_p4_coverage(p4_full_panel)),
  tar_target(p4_overround,   summarise_p4_overround(p4_full_panel)),
  tar_target(p4_compression, compute_p4_compression(p4_full_panel)),

  # -- P4-1: market probability construction ------------------------------
  tar_target(
    p4_raw_prices,
    read_p4_price_sources(sort(unique(p4_preds_3$race_id)))
  ),
  tar_target(
    p4_price_panel,
    build_p4_price_panel(p4_preds_3, p4_preds_2b, p4_raw_prices)
  ),
  tar_target(
    p4_common,
    select_p4_common_races(p4_price_panel)
  ),
  tar_target(
    p4_probs,
    build_p4_market_probs(p4_price_panel, p4_common$race_ids)
  ),
  tar_target(
    p4_floor_report,
    attr(p4_probs, "floor_binds")
  ),

  # -- Amendment 2: revision, or transcription noise? ---------------------
  # Runs on the WHOLE common race set, before the arms, because it is a
  # question about the price columns rather than about the blend.
  tar_target(
    p4_amendment2,
    run_amendment2_test(p4_probs)
  ),
  tar_target(
    p4_market_correlations,
    market_column_correlations(p4_probs)
  ),

  # -- The chronological test-A / test-B split ----------------------------
  tar_target(
    p4_split,
    split_test_ab(p4_probs)
  ),
  tar_target(
    p4_split_summary,
    summarise_ab_split(p4_split)
  ),
  # test-A is the ONLY thing fitted or scored. test-B is materialised as a
  # race-id list and a row count and nothing else, so that "reserved and
  # untouched" is checkable rather than asserted.
  tar_target(
    p4_test_a,
    p4_split |> dplyr::filter(split_ab == "A")
  ),
  tar_target(
    p4_test_b_reserved,
    p4_split |>
      dplyr::filter(split_ab == "B") |>
      dplyr::distinct(race_id, meeting_date)
  ),

  # -- P4-2: the arm grid -------------------------------------------------
  tar_target(
    p4_arm_grid,
    fit_p4_arm_grid(p4_test_a, sample = "test-A")
  ),

  # -- Follow-up: independent replication on test-B, and the pooled fit ----
  # Test-B's reserved purpose was evaluating blend performance. The null
  # against SP made that moot, so it is spent here instead on an
  # independent replication of b_mod. This consumes the reservation: after
  # this there is no held-out race set left in the paper-4 universe.
  tar_target(
    p4_test_b,
    p4_split |> dplyr::filter(split_ab == "B")
  ),
  tar_target(
    p4_arm_grid_b,
    fit_p4_arm_grid(p4_test_b, sample = "test-B")
  ),
  tar_target(
    p4_arm_grid_pooled,
    fit_p4_arm_grid(p4_split, sample = "pooled")
  ),
  tar_target(
    p4_replication_mod,
    compare_halves(p4_arm_grid, p4_arm_grid_b, term_role = "mod")
  ),
  tar_target(
    p4_replication_mkt,
    compare_halves(p4_arm_grid, p4_arm_grid_b, term_role = "mkt")
  ),
  tar_target(
    p4_attenuation,
    dplyr::bind_rows(
      attenuation_bracket(p4_arm_grid),
      attenuation_bracket(p4_arm_grid_b),
      attenuation_bracket(p4_arm_grid_pooled)
    )
  ),

  # -- Amendment 4: does b_mod survive a flexible market term? ------------
  tar_target(
    p4_flexible_a_2b,
    fit_flexible_market(p4_test_a, "log_p_mkt_A", "log_p_mod_2b", "A1")
  ),
  tar_target(
    p4_flexible_a_3,
    fit_flexible_market(p4_test_a, "log_p_mkt_A", "log_p_mod_3", "A2")
  ),

  # -- P4-3: the report ---------------------------------------------------
  tar_target(
    p4_report_file,
    write_p4_report(
      path            = "papers/04_market_blend/P4_REPORT.md",
      audit           = readRDS("scripts/p4_audit_forecast_price.rds"),
      common          = p4_common,
      floor_report    = p4_floor_report,
      split_summary   = p4_split_summary,
      amendment2      = p4_amendment2,
      correlations    = p4_market_correlations,
      arm_grid        = p4_arm_grid,
      flexible        = list(A1 = p4_flexible_a_2b, A2 = p4_flexible_a_3),
      test_b_reserved = p4_test_b_reserved,
      arm_grid_b      = p4_arm_grid_b,
      arm_grid_pooled = p4_arm_grid_pooled,
      replication_mod = p4_replication_mod,
      replication_mkt = p4_replication_mkt,
      attenuation     = p4_attenuation
    ),
    format = "file"
  ),

  # -- The paper ----------------------------------------------------------
  # quiet = FALSE so quarto's own error output surfaces rather than
  # "System command 'quarto.exe' failed" — the series convention.
  tar_quarto(
    paper_4_market_blend,
    path = "papers/04_market_blend",
    quiet = FALSE,
    extra_files = c(
      "papers/04_market_blend/_01_method.qmd",
      "papers/04_market_blend/_02_data.qmd",
      "papers/04_market_blend/_03_results.qmd",
      "papers/04_market_blend/_04_discussion.qmd",
      "papers/04_market_blend/_05_conclusion.qmd",
      "papers/04_market_blend/_appx_provenance.qmd",
      "papers/04_market_blend/_appx_software.qmd",
      "papers/04_market_blend/_helpers.R",
      "papers/04_market_blend/references.bib",
      "papers/04_market_blend/_quarto.yml"
    )
  )
)
