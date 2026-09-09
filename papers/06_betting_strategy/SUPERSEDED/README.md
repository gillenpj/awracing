# Superseded — the first paper-6 draft

**Void. Kept for reference only, not rendered and not published.**

This is the first attempt at paper 6, complete through a scored test split
and a full draft. It is superseded because its search set was wrong.

## What was wrong

The rules were searched on **training-split** predictions from paper 5's
full-training-split refit. The encoder was fitted on those races, so its
probabilities there are in sample. Two consequences, both fatal to the
paper's question:

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

## What replaced it

The redo searches the **validation slice** — paper 5's 1,505 held-out races,
scored by the fitting-partition fit, which never saw them — and declares
selection and staking in two separate stages, each a one-difference
contrast, behind an eligibility gate that counts bets placed rather than
races selected.

## What carried over unchanged

The ledger, `scripts/verify_p6_ledger.R` and its six assertions,
`p6_eachway_returns()` and the corrected each-way terms ladder, the
fair-book columns, the margin decomposition, `p6_assert_one_difference()`,
the pipeline and store arrangement, the upstream fingerprint, and the
settlement appendix. Those were sound and are reused rather than rebuilt.

The numbers in these files were correct for what they measured. The test
figures for S1/K0 and S4/K0 in `P6_TEST_REPORT.md` are computed by the same
ledger the redo uses and are reproduced by it.
