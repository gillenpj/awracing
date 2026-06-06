# Mixed discrete choice models and race-level features

Material cut from paper 1's `_appx_derivation.qmd` because paper 1's
headline model is the plain conditional logit with horse-level features
only. The race-level-feature mechanism below is where paper 2's
"extended feature set" plugs in — keep this here until paper 2 needs
it; then drop it into `papers/02_*/_appx_derivation.qmd` (or a methods
section). Equations and prose are intact and ready to paste.

---

## Mixed discrete choice models

Both multinomial and conditional logistic regression are instances of
discrete choice models. In practice, a *mixed* or hybrid formulation is
sometimes used, in which the linear predictor includes both pure
alternative-specific features, pure individual-specific features, and
interactions between the two; see Train (2009) for a comprehensive
treatment.

In the racing context, recall that individual $i$ is a race and
alternative $j$ is a horse. We distinguish two types of feature:

- **Horse-level features** $h_{ijl}$: the $l$-th feature of horse $j$
  in race $i$ (e.g. speed figure, weight carried, days since last
  race). These vary across horses within a race.
- **Race-level features** $r_{il}$: the $l$-th feature of race $i$
  (e.g. going, distance, prize money). These are the same for every
  horse in a given race.

Pure race-level features cannot enter the model directly: since
$r_{il}$ does not carry a $j$ index, it is the same for every horse in
race $i$ and cancels between numerator and denominator in the softmax,
leaving all probabilities unchanged. However, interactions between
race-level and horse-level features,
$$
x_{ijl} = r_{il} \cdot h_{ijl},
$$
do vary across horses within a race and can enter the model. For
example, if $r_{i1}$ is an indicator for firm going and $h_{ij1}$ is
horse $j$'s historical win rate on firm ground, then
$x_{ij1} = r_{i1} \cdot h_{ij1}$ measures how well each horse in the
field is suited to today's conditions.

---

**Reference**: Train, K. E. (2009). *Discrete Choice Methods with
Simulation* (2nd ed.). Cambridge University Press.
