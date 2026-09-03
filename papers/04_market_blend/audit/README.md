# Paper 4 — P4-0 audit working files

The evidence base behind
[`_appx_provenance.qmd`](../_appx_provenance.qmd) (Appendix A of paper 4).
These are one-off analysis scripts, kept because the appendix's claims
rest on them, not because anything in the pipeline runs them.

Nothing here is on the `{targets}` graph. All are read-only against the
Smartform database and the main `_targets` store, and all are run from
the project root:

    "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" papers/04_market_blend/audit/<script>.R

| File | What it established |
|---|---|
| `p4_schema_probe.R` | Where the price columns live, their types, and the value ladders. |
| `p4_audit_followup.R` | Whether the archived forecast price is revised: daily-feed vs archive agreement, the INT_MIN sentinel rows, degenerate books. |
| `p4_audit_followup2.R` | Row write-timing relative to the meeting date, the direction of the feed-to-archive divergence, and overround over the declared vs final field. |
| `p4_audit_followup3.R` | Costing the pre-race `daily_runners` price as the substitute: coverage, overround and shape against SP. |

The P4-0 gate itself is **not** here. It is
`scripts/p4_audit_forecast_price.R`, which stays under `scripts/` because
`scripts/verify_p4_data_targets.R` and `_targets_p4.R`'s report target
both read the `.rds` it writes.

The findings were later re-grounded in the Smartform manual rather than
in the inferred write timestamps these scripts measure. Appendix A is the
current reading, and where it differs from a conclusion stated in one of
these files, the appendix is right.
