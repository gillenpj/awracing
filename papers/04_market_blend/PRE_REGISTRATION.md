# Paper 4 — pre-registered coefficient expectations

Recorded 2026-08-28, **before** any blend was fitted, per amendment 3 of
the P4 brief.
Written at the point where P4-0 was complete and the P4-1 construction was
built and gated, but `fit_p4_arm_grid()` had not been run.

Anchors for interpretation, **not** thresholds. Nothing in the
construction, the race set, the split or the specifications is to be
adjusted to move an observed value toward an expected one.

## The construction

    V_ij = b_mkt * log(P_mkt_ij) + b_mod * log(P_mod_ij)

Conditional logit, race as chooser, both coefficients free, no intercept
(it cancels in the softmax). `b_mod` is the output.

`b_mkt` is not pinned at 1. Pinning would assert the market is perfectly
calibrated and push any residual miscalibration into `b_mod`, inflating
it. Left free, `b_mkt` also estimates the market's favourite–longshot
power-law exponent directly.

## Expectations

| Quantity | Expected | Reasoning |
|---|---|---|
| `b_mkt` on arm A (pre-race feed forecast) | ≈ **1.8** | The reciprocal of the 0.554 within-race slope of log p_forecast on log p_SP measured in P4-0 item 4. If the blend is mainly *de-compressing* the morning book back toward the SP shape, this is where `b_mkt` lands. |
| `b_mkt` on arm B (starting price) | ≈ **1.0 – 1.1** | If UK SP is close to calibrated. This is the favourite–longshot exponent. Levey reports ≈ 1.10 for US pari-mutuel odds; UK SP is a bookmaker market, not a pool, so a difference is expected and is not evidence of an error. |

No expectation is pre-registered for `b_mod` on any arm, for `b_mkt` on
arm C, or for the amendment-2 or amendment-4 outcomes. Those are the
open questions.

## Reading rules fixed in advance

**Amendment 2 — archive vs feed.** A conditional logit carrying both
`log(p_archive)` and `log(p_feed)` on the common race set, tested against
the feed-only model.

- Archive coefficient **distinguishable from zero** → genuine revision.
  The archive is contaminated, and arm C is a contamination estimate.
- Archive coefficient **indistinguishable from zero** → the divergence is
  transcription noise. The archive is the better-measured column, and arm
  A carries an errors-in-variables attenuation that *inflates* `b_mod`.

**A-versus-B on `b_mod`.** Comparable magnitudes mean the model's
contribution survives market convergence. A collapse from A to B means
the edge lives only in the timing gap between the morning price and the
off. State which pattern the numbers show; do not interpret further.

**Amendment 4 — flexible market term on arm A.** If `b_mod` collapses
once the market term is free to bend (natural spline in `log P_mkt`, or
`log P_mkt` interacted with field size), then `b_mod` on arm A was
residual recalibration of a field-size-dependent margin, not information.

## Fixed before fitting

- Race set: the intersection over all three price columns. Every arm
  fits the same races; a paired comparison of `b_mod` across arms is void
  otherwise.
- Split: chronological 50/50 of that common set into test-A (earlier,
  fitted and reported) and test-B (later, reserved and **not scored**).
- Model probabilities: reused from the frozen store. Neither paper 2b nor
  paper 3 is refitted.
- Probability floor: 1e-6 on market and model alike, applied before
  `log()`. Expected to bind on nothing; the count is reported either way.
