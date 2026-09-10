# Superseded paper-6 drafts

**Both void as papers. Kept for reference only, not rendered and not
published. Do not cite their numbers.**

Paper 6 has been attempted twice as a hypothesis-testing paper and both
attempts are here. The current work is not a third attempt at that paper: it
is an **exploratory ROI sweep** (`../EXPLORATION.md`), with no declaration
rule, no bar to clear and no interval gating what reaches the test split. Its
purpose is to generate ideas to return to when betting goes live.

| directory | what it was | why it is here |
|---|---|---|
| `attempt1_training_split/` | Declaration paper, searched on training-split predictions | Search set was in sample |
| `attempt2_declaration/` | Declaration paper, searched on the validation slice | Question changed; the search space was also degenerate |

---

## `attempt1_training_split/` — the search set was in sample

Complete through a scored test split and a full draft. Superseded because the
rules were searched on **training-split** predictions from paper 5's
full-training-split refit. The encoder was fitted on those races, so its
probabilities there are in sample. Two consequences, both fatal:

1. The declaration ranked candidates by how hard they leaned on that
   memorisation. Under the incumbent rule the training win ROI was +39.8%
   against −12.19% on test, while the model-free control returned −12.7% on
   training against −6.4% on test — the inflation is entirely on the
   model-reading arms.
2. It therefore preferred the non-flat staking arms, which stake zero where
   the model probability does not exceed the price. Out of sample that
   happens far more often, so the declared win rule staked 33 units across
   2,183 test races and its interval was 54 points wide. **No alternative
   selection rule at a flat stake ever reached the test split, so the
   paper's own question was never asked.**

## `attempt2_declaration/` — sound execution, degenerate search space

Searched the validation slice — paper 5's 1,505 held-out races, scored by the
fitting-partition fit, which never saw them — and declared selection and
staking in two separate one-difference stages behind an eligibility gate
counting bets placed. Both stages declared the incumbent (S1/K0) for all
three bet types. The arithmetic is correct: `../DIAGNOSTICS.md` rebuilt the
validation ledger from `historic_runners` independently and it matched to
every digit, and that rebuild is now assertion 7 of
`scripts/verify_p6_ledger.R`.

It is superseded for two reasons.

**The question changed.** Paper 6 is no longer asking whether a declared rule
beats the incumbent at a stated bar. It is asking, exploratorily, whether
test-split ROI can be moved at all by a different betting rule — which needs
a wide sweep read against the test split, not a single declared arm.

**The search space was degenerate, which `../DIAGNOSTICS.md` established.**
Seven of the nine selection arms were one horse-picking function
(`p6_top_rated()`) behind seven race-level filters, and they agreed on the
backed horse in **100.0%** of races where any two of them bet. The nine-arm
space contained three horse-pickers, not nine. Worse for the comparison, the
winning arm's interquartile backed price [6.00, 9.00] did not overlap any
other arm's, while eight of nine crowded into a median price of 2.5–4.5 — so
the incumbent's 15-point validation margin was structurally the return of the
6–9 price band against the 2.5–4.5 band on 1,505 races in 2011–2012, not a
contest between comparable rules.

The exploration replaces the nine arms with a cross-product of five genuinely
distinct pickers and a full filter grid, and reports mean backed price on
every row so a rule's price band is never invisible again.

## What carried over unchanged into the exploration

The ledger (`R/p6_ledger.R`), `p6_eachway_returns()` and the corrected
each-way terms ladder, the fair-book columns, the pipeline and store
arrangement (`_targets_p6.R` / `_targets_p6`), the upstream fingerprint, and
the settlement appendix material. Those were sound and are reused rather than
rebuilt. `scripts/verify_p6_ledger.R` carried over and gained assertion 7,
which closes the validation path both drafts ran on unchecked.
