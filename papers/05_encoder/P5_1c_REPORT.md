# P5-1c — settling the rung 1 confound

Run 2026-09-04 on branch `paper5-encoder`. Two fits: the rung-1 MLP grid on
26 terms (paper 3's information, `stall_normalised` restored), and a linear
scorer on the identical 26.

**The test split is not scored anywhere in this task. Rung 2 is not
started.**

---

## 1. Headline — MLP vs linear on identical features

Same loss, same loop, same slice, same seed, same 26 terms. **The function
class is the only difference.** 1,505 validation races, paired race-level
bootstrap, B = 2000, seed 42, 90% intervals.

| metric | MLP | linear | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00303180 | 0.00299271 | +3.909e-05 | [+1.089e-05, +6.653e-05] | **MLP** |
| Brier_place (lower better) | 0.19700500 | 0.19755511 | −5.502e-04 | [−1.007e-03, −6.723e-05] | **MLP** |

**The MLP's advantage survives once the feature sets match.** Both intervals
exclude zero, both favouring the MLP.

> **Control claim does NOT hold. The nonlinearity is buying something, and
> any rung 3 gain must be read against an already-improved baseline rather
> than against paper 2b.**

## 2. Continuity — MLP vs paper 2b

| metric | MLP (26) | paper 2b (17) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank | 0.00303180 | 0.00298455 | +4.725e-05 | [+1.713e-05, +7.563e-05] | MLP |
| Brier_place | 0.19700500 | 0.19762087 | −6.159e-04 | [−1.102e-03, −9.572e-05] | MLP |

Reading, as before: *MLP favoured — proceed, and record that the control
claim is weakened.*

## 3. What the two contrasts decompose into

The MLP-vs-linear difference (+3.909e-05, −5.502e-04) is nearly the whole of
the MLP-vs-2b difference (+4.725e-05, −6.159e-04). Almost all of the MLP's
advantage over paper 2b is **function class**, not the extra features.

On validation PL loss, where the three arms are directly comparable:

| arm | terms | val PL loss | attributable to |
|---|---|---|---|
| paper 2b, mlogit | 17 | 5.814307 | — |
| linear in torch | 26 | 5.811575 | **+0.00273** — the nine extra features |
| MLP | 26 | 5.798597 | **+0.01298** — the nonlinearity |

The nonlinearity is worth about **4.8 times** what the extra features are.

**This sits awkwardly against paper 3.** Paper 3 changed the function class
from a linear score to a gradient-boosted tree and found a tie on every
measure — the basis for "the function class was not the binding constraint,
so the feature set is the next lever". Here a different nonlinear function
class, on the same objective and essentially the same information, beats the
linear score on both ranking metrics. Either the MLP is finding structure
the tree ensemble did not, or something about this comparison is more
favourable to the nonlinear arm than paper 3's was. I have not established
which, and it should not be waved past.

## 4. The caveat that qualifies all of the above

**The two arms did not get the same selection budget, and the MLP's winner
looks like a noisy dip rather than a converged optimum.**

| | selection opportunities | best epoch | behaviour at the optimum |
|---|---|---|---|
| MLP | 9 configs × 60 epochs = **540** | **3** of 60 | loss at epoch 60 is 5.947, far worse than the 5.799 selected |
| linear | 1 config × 200 epochs = **200** | 85 of 200 | plateaus at ~5.8124 and stays there |

The MLP's selected point is epoch 3 of a run that then degrades by 0.15. The
linear arm's is a genuine plateau. Picking the minimum of 540 noisy
evaluations on 1,505 races will, on its own, find a lower number than
picking the minimum of 200 — some part of the 0.013 gap is that, not the
function class.

This does not change the pre-registered reading, which is written on the
bootstrap intervals and those exclude zero. It does change how much weight
the verdict carries. **A fair like-for-like test would give both arms the
same budget** — one configuration each, or the same epoch grid — and I have
not run it. If the control claim matters for how rung 3 is read, that test
is worth one more fit before rung 2.

Every one of the nine MLP configurations peaks between epochs 1 and 10:

| config | widths | lr | best val PL loss | best epoch | loss at epoch 60 |
|---|---|---|---|---|---|
| 6 | 256-128 | 3e-04 | **5.798597** | 3 | 5.946856 |
| 2 | 128-64 | 1e-03 | 5.805054 | 3 | 5.998077 |
| 8 | 64-32 | 1e-03 | 5.805308 | 3 | 5.888264 |
| 3 | 128-64 | 3e-04 | 5.806882 | 6 | 5.881366 |
| 7 | 64-32 | 3e-03 | 5.807255 | 2 | 5.965831 |
| 9 | 64-32 | 3e-04 | 5.807342 | 10 | 5.857776 |
| 5 | 256-128 | 1e-03 | 5.810039 | 3 | 6.259688 |
| 4 | 256-128 | 3e-03 | 5.815154 | 1 | 6.828270 |
| 1 | 128-64 | 3e-03 | 5.818877 | 1 | 6.173904 |

Two of the nine (configs 4 and 1) are worse than the linear arm's 5.811575.
The grid is not uniformly beating linear; its best member is.

## 5. The control's 26 terms

`stall_normalised` restored, as instructed — it is in paper 3's 24 and was
dropped from the P5-1b list in error, not by design. The control now carries
paper 3's information.

**Paper 2b's 17:** `pos_lag1_zero`, `pos_lag1_nonzero`, `pos_lag2_zero`,
`pos_lag2_nonzero`, `age_diff`, `days_LTO_log`, `trainerSR`, `sireSR`,
`jockeySR`, `entire`, `gelding`, `cheekpieces`, `rel_weight`, `or_relative`,
`or_missing`, `trainer_aw_premium`, `has_wins`.

**Going-affinity block:** `going_runs_prior`, `going_sr_shrunk`,
`going_sr_delta`, `going_ordinal`.

**Draw and course:** `stall_normalised`, `course_Kempton`,
`course_Lingfield`, `course_Southwell`, `course_Wolverhampton`.

Asserted in the pipeline as `length(...) == 26L`. The nine configurations
were the same declared grid as P5-1b, unchanged, selected on validation PL
loss and nothing else.

## 6. The two data points noted, neither actioned

**`beaten_dist` reaches 430 lengths.** Not a plausible winning distance in a
British race — the beaten-distance column is cumulative lengths behind the
winner, and 430 is beyond any real result. It was not among the four
channels flagged for cleaning in P5-1b, so it is untouched. **It should be
dealt with before rung 3**, which is the first rung that reads the
sequences. The other channels are now bounded: `finish_pos` ≤ 35, `class`
1–7 or −1, `field_size` ≤ 40, `days_since_prev` ≤ 1000.

**`beaten_missing` is 99.96% zero.** Kept, as instructed, and it will carry
essentially nothing for the encoder — a channel that is constant on 634,558
of 634,803 real slots cannot inform much. It is retained only because a
genuinely missing beaten distance would otherwise be indistinguishable from
the −1 fill.

## 7. Rollback verification

`git diff main --stat`:

```
 .gitignore |  4 ++++
 renv.lock  | 18 ++++++++++++++++++
 2 files changed, 22 insertions(+)
```

Unchanged from P5-1b — both additions only, and no new tracked file. Nothing
on this branch is committed; the paper-5 code and reports remain untracked
working-tree state. No file used by papers 1-4 was modified; `docs/`, the
landing page and CLAUDE.md are untouched.

**Main store untouched:**

```
targets::tar_outdated(store = "_targets", script = "_targets.R")
→ character(0)
```

## 8. Where this stops

Reported, and stopping. Rung 2 is not started.

The question rung 1 was built to answer now has an answer: **on identical
features, the MLP beats the linear scorer, so the control claim does not
hold.** A rung 3 gain cannot be attributed to sequence representation by
comparison with paper 2b; it has to be measured against this MLP.

What that implies for the ladder, and it is your call:

1. **Rung 3's comparator changes.** The encoder should be judged against the
   26-term MLP, not against paper 2b or paper 3. Otherwise a gain that is
   really the nonlinearity gets attributed to the sequence.
2. **The selection-budget asymmetry in §4 is worth one fit** before that,
   because if the MLP's edge is partly the 540-versus-200 search, the
   baseline rung 3 must beat is lower than 5.7986 and the whole ladder
   shifts.
3. **Paper 3's "function class is not the binding constraint" needs
   revisiting** in the write-up whatever happens next. This result does not
   overturn it — different function class, different comparison — but it is
   in tension with it, and the paper should say so rather than leave a
   reader to notice.
