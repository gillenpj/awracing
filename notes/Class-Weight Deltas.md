Idea: Class and weight deltas to contextualise form
Problem
A horse winning at Class 5 carrying 9 stone is not comparable to one winning at Class 2 carrying 11 stone without normalisation. Owen's features (age_diff, sireSR, etc.) are timeless; they don't account for whether the horse was stepping up or down. When assessing form today, we need to know: was the last run at a similar level, and was the weight load similar?
Method
Class delta feature: class_delta = class_today − class_LTO
Negative = horse was running higher class last time (more impressive)
Positive = horse drops in class (less impressive, or tactical)
Zero = same class as LTO
Weight delta feature: weight_delta = weight_today_lbs − weight_LTO_lbs
Positive = carrying more weight today (more burden)
Negative = carrying less (easier)
Interaction with form: Multiply position1 (finishing position in previous race, 1–4) by class_delta
A 1st place LTO is worth more if class_delta ≤ 0 (same class or up in class)
A 1st place LTO at a lower class (class_delta > 0) is less predictive of today's win
Rationale
The handicapper sets weight and class entry based on OR. A horse beating its OR by 2 lengths at Class 5 with 9 stone is genuine form. The same horse moved to Class 3 at 10 stone should be viewed differently — it's stepping up. These deltas capture that context within the feature space.
Implementation
Data shape: Within extract_runners_for_races() in R/extract_runners.R, compute for each runner in each race:
runners_augmented <- runners |>
  group_by(runner_id) |>
  arrange(race_id, race_date) |>
  mutate(
    class_LTO = lag(class),
    weight_LTO = lag(weight_pounds),
    position_LTO = lag(finish_position),  # or coalesce(amended_position, finish_position)
    # Deltas
    class_delta = class - class_LTO,
    weight_delta_lbs = weight_pounds - weight_LTO,
    # Interactions
    position_LTO_x_class_delta = position_LTO * class_delta
  ) |>
  ungroup()
mlogit fitting: Add to Owen's formula:
fit_extended <- mlogit(
  won ~ age_diff + sireSR + trainerSR + daysLTO +
        position1 + position2 + position3 +
        entire + gelding + cheekpieces +
        # New features:
        class_delta + weight_delta_lbs +
        I(position_LTO * class_delta),
  data = h_data,
  ...
)
Handling NA: Horses with no prior race in the window (8.2% per CLAUDE.md) will have NA for class_delta etc. Impute with 0 (no prior context) or drop these rows as a sensitivity check.
Expected outcome
class_delta should be negative and significant: stepping up in class reduces win odds.
weight_delta_lbs should be negative: carrying more weight reduces win odds (roughly −0.01 per pound in turf handicaps; AW unknown).
position_LTO × class_delta interaction should show that recent wins are less predictive if the horse was running at lower class.
R² and log-likelihood improve relative to Owen's baseline.
Existing features (sireSR, daysLTO, position1) may attenuate slightly (less unique variance if class/weight capture some prior-form signal).
Pitfalls
Endogenous class entry. Trainers choose which class to run in. So class_delta is not randomly assigned; a horse running at lower class may be temporarily out of form or recovering from injury (selection bias). Causal interpretation of the class_delta coefficient is not valid, only predictive.
Handicap already prices this in. The weight is meant to equalise chances across classes. If the handicap is perfect, class_delta should be zero coefficient. Nonzero coefficient signals the handicap is biased. That's interesting but don't overinterpret as causal.
Multicollinearity with position1 / sireSR. Class_delta may correlate with recent form if horses are only moved between classes after poor runs. Check VIF; if high, consider dropping the main effect of class_delta and keeping only the interaction.
Sensitivity to class ordering. Smartform uses class 1–5 (1 = highest). Confirm the sign: class_delta = 1 means moving to lower class (worse), so coefficient should be negative.
Extensions
If distance or going varies between LTO and today, add distance_delta and/or going_delta (from soft to good, etc.)
Weight as a ratio instead of absolute delta: weight_delta_pct = (weight_today − weight_LTO) / weight_LTO
Standardise within-race: weight_delta_vs_field = weight_today − mean_weight_today − (weight_LTO − mean_weight_LTO). This filters out between-race weight inflation.
