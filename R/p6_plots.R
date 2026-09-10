# p6_plots.R
# Paper 6 — figures. Targets return ggplot objects; nothing is written to
# disk outside the Quarto render, per the series' `{targets}` convention.

#' Cumulative profit on the test split, by arm
#'
#' One panel per bet type, one line per arm, in race-date order. The vertical
#' scale is stake units, so arms staking different amounts are not directly
#' comparable in level — the shape is what the figure is for: whether a rule's
#' loss accumulates steadily or rests on a few results.
#'
#' @param ledgers The `p6_test_ledgers` target.
#' @param bets Settlement columns to draw.
#' @return A ggplot object.
p6_plot_cumulative_profit <- function(ledgers,
                                      bets = c("win", "place",
                                               "eachway_corrected")) {
  bet_label <- c(win = "win", place = "place",
                 eachway = "each-way (paper 5 terms)",
                 eachway_corrected = "each-way (corrected terms)")

  d <- purrr::imap(ledgers, function(led, key) {
    parts <- strsplit(key, "|", fixed = TRUE)[[1]]
    if (!parts[3] %in% bets || nrow(led) == 0L) return(NULL)
    led |>
      dplyr::arrange(race_date, race_id) |>
      dplyr::mutate(arm = paste(parts[1], parts[2], sep = "/"),
                    bet = parts[3], cum_profit = cumsum(profit))
  }) |>
    purrr::compact() |>
    purrr::list_rbind() |>
    dplyr::mutate(bet = factor(bet_label[bet], levels = bet_label[bets]))

  ggplot2::ggplot(d, ggplot2::aes(race_date, cum_profit, colour = arm)) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey50") +
    ggplot2::geom_step(linewidth = 0.5) +
    ggplot2::facet_wrap(~bet, ncol = 1, scales = "free_y") +
    ggplot2::scale_colour_brewer(palette = "Dark2") +
    ggplot2::labs(x = NULL, y = "cumulative profit (stake units)",
                  colour = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom",
                   panel.grid.minor = ggplot2::element_blank())
}

#' Validation-slice ROI against test-split ROI
#'
#' The nine stage-A selection rules on the validation slice as a rug, against
#' the arms that reached the test split with their 90% intervals. What the
#' search saw, and what survived it. Both axes are out of sample.
#'
#' @param grid_a The `p6_stage_a_grid` target.
#' @param results The `p6_test_results` target.
#' @param bet Settlement column to draw.
#' @return A ggplot object.
p6_plot_val_vs_test <- function(grid_a, results, bet = "win") {
  va <- grid_a |>
    dplyr::filter(bet == !!bet) |>
    dplyr::mutate(combo = paste0(selection, "/", staking))
  te <- results |> dplyr::filter(bet == !!bet)

  ggplot2::ggplot(va, ggplot2::aes(x = roi, y = 0)) +
    ggplot2::geom_vline(xintercept = 0, linewidth = 0.3, colour = "grey50") +
    ggplot2::geom_point(shape = 124, size = 5, colour = "grey40") +
    ggplot2::geom_point(
      data = te, ggplot2::aes(x = roi, y = 0.4, colour = arm), size = 3
    ) +
    ggplot2::geom_errorbar(
      data = te,
      ggplot2::aes(x = roi, y = 0.4, xmin = ci_lo, xmax = ci_hi, colour = arm),
      orientation = "y", width = 0.12, linewidth = 0.4
    ) +
    ggplot2::scale_x_continuous(labels = scales::percent) +
    ggplot2::scale_y_continuous(
      breaks = c(0, 0.4),
      labels = c("validation slice\n(9 selection rules, flat stake)",
                 "test split\n(the arms that reached it)"),
      limits = c(-0.15, 0.6)
    ) +
    ggplot2::scale_colour_brewer(palette = "Dark2") +
    ggplot2::labs(x = "ROI at the real starting price", y = NULL,
                  colour = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom",
                   panel.grid.minor = ggplot2::element_blank(),
                   panel.grid.major.y = ggplot2::element_blank())
}
