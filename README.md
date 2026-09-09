# awracing

Statistical models of UK All-Weather racing outcomes, built on the
Smartform database in R.

Each paper changes one thing and reports the result against the previous
paper and against the betting market. All five are published at
[gillenpj.github.io/awracing](https://gillenpj.github.io/awracing/).

## Papers

**Paper 1: Replicating Owen (2019) on UK All-Weather Flat handicaps, 2006–2015**
Replicates Alun Owen's conditional-logit win model on a different dataset —
All-Weather rather than Turf, at Kempton, Lingfield, Southwell and
Wolverhampton. Coefficient signs largely agree with his; the model trails the
market on both scoring rules.
[Read online](https://gillenpj.github.io/awracing/paper1/) | [PDF](https://gillenpj.github.io/awracing/paper1/index.pdf)

**Paper 2a: Extended feature set and race-level interactions**
Adds an extended feature set and race-level interactions to the win model.
The official rating is the strongest new predictor, a course-specific draw
bias appears at Kempton and Southwell, and the narrowed loss is not
distinguishable from paper 1's.
[Read online](https://gillenpj.github.io/awracing/paper2a/) | [PDF](https://gillenpj.github.io/awracing/paper2a/index.pdf)

**Paper 2b: Ranking models — the exploded conditional logit and the place market**
Holds the feature set fixed and changes the objective from predicting the
winner to predicting the finishing order. A better winner-picker than paper
2a, still behind the market on ranking, with single-bet place returns about
half the drag of backing every qualifier.
[Read online](https://gillenpj.github.io/awracing/paper2b/) | [PDF](https://gillenpj.github.io/awracing/paper2b/index.pdf)

**Paper 3: Gradient boosted trees**
Holds the features and the objective fixed and changes the function class to
a gradient-boosted tree ensemble under a custom Plackett–Luce objective. Ties
paper 2b on every measure tested, with the market ahead of both on ranking.
[Read online](https://gillenpj.github.io/awracing/paper3/) | [PDF](https://gillenpj.github.io/awracing/paper3/index.pdf)
| [Supplementary: notes on tree-based methods](https://gillenpj.github.io/awracing/paper3/notes-on-tree-based-methods.pdf)

**Paper 4: The marginal value of a model over the market**
Changes no model. Asks whether the model adds anything to the market price
rather than whether it beats it, via a two-stage conditional logit. Nothing
distinguishable against the settled starting price; a great deal against the
pre-race forecast price.
[Read online](https://gillenpj.github.io/awracing/paper4/) | [PDF](https://gillenpj.github.io/awracing/paper4/index.pdf)

**Paper 5: Sequence encoding of run histories**
Replaces the eight hand-built features summarising a horse's own run history
with a recurrent encoder reading its twenty most recent runs directly. Beats
those features on every ranking measure on the held-out test split, and three
models separate cleanly where papers 1–3 could not be told apart. The market
still ranks ahead.
[Read online](https://gillenpj.github.io/awracing/paper5/) | [PDF](https://gillenpj.github.io/awracing/paper5/index.pdf)
| [Supplementary: notes on neural scorers and sequence encoders](https://gillenpj.github.io/awracing/paper5/notes-on-neural-scorers.pdf)

## Stack

R 4.6, `targets`, `renv`, Quarto. Modelling: `mlogit` (papers 1–2b),
`xgboost` with a custom Plackett–Luce objective (paper 3), `torch`
(paper 5). Data: Smartform MySQL database.

## Reproducibility

`targets::tar_make()` from the project root rebuilds papers 1–3 and
re-renders them to HTML and PDF. Papers 4 and 5 have their own pipelines and
stores, so nothing they do can touch the published papers before them:

```r
targets::tar_make(script = "_targets_p4.R", store = "_targets_p4")
Rscript scripts/run_p5_pipeline.R     # or tar_make(script = "_targets_p5.R", store = "_targets_p5")
```

All of it requires a local Smartform database and a `.env` file with
connection credentials (not committed). Paper 5 additionally requires the
**CPU** build of `libtorch`: `renv.lock` pins R packages but not the C++
runtime, so set `CUDA = "cpu"` before installing the backend.
