# Withdrawn — paper 6, "Bet selection: three families of rule"

**Withdrawn 2026-09-10. Do not revise, do not cite, do not carry anything
into the replacement paper.**

This directory holds the complete withdrawn draft: the Quarto sources, the
two earlier voided attempts under `SUPERSEDED/`, the working reports
(`EXPLORATION.md`, `DIAGNOSTICS.md`) and their figures, the run logs, and the
code that produced them:

- `R/p6_*.R` — the ledger, the rule registries, the sweeps, the
  race-characteristic family and the stability guard. Moved out of the
  project's `R/` directory so nothing sources them by accident. Files under
  `R/` are `source()`d into the global environment, so leaving them there
  alongside the replacement paper's code would risk one shadowing the other.
- `verify_p6_ledger.R` — the seven-assertion ledger gate, including the
  assertion that rebuilt the paper-5 validation ledger from
  `historic_runners` independently. It gated only the withdrawn paper's
  betting arithmetic and is not on any live graph.
- `_targets_p6_withdrawn.R` — the withdrawn pipeline. Its store was renamed
  from `_targets_p6` to `_targets_p6_withdrawn` (both gitignored) so the
  replacement paper can take the `_targets_p6.R` / `_targets_p6` names the
  series convention gives paper 6. Nothing was deleted; the store is intact
  under the new name and the pipeline is deterministic if it ever needs
  rebuilding.

The draft's numbers were correct for what they measured. It was withdrawn
because its subject was replaced, not because anything in it was miscomputed.
Two figures from it are re-used in the replacement paper, both independently
recomputed there from paper 5's stored predictions rather than read from
here: the single-bet win ROI on the two halves of paper 5's validation slice.

The full history is on branch `paper-6-explore` and in `main` at commit
`55a48db`.

**One loose end.** `docs/paper6/` on the published site still serves this
withdrawn draft, and `scripts/publish_docs.R` still has its row. Neither has
been changed, because removing a live page is an outward-facing action that
was not requested. Decide what should happen there before the replacement
paper is published.
