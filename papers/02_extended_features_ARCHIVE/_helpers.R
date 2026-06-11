# _helpers.R
# Plotting helpers used inside the paper-2 .qmd files. Two functions:
#   - summarise_win_rate(): tibble of n, n_wins, win_rate, se per bin
#   - plot_win_rate():      ggplot of the summary with errorbars and a
#                           reference line at the overall (or user-supplied)
#                           win rate.
# Carried over verbatim from papers/01_replication/_helpers.R so paper 2
# renders as a self-contained project. Not sourced by the pipeline.

#' Summarise win rate by a feature
#'
#' Bins or groups a column of `data` by `feature` and returns the count,
#' win count, win rate, and standard error per bin. Bins with `n < min_n`
#' have their `win_rate` and `se` set to NA so the caller does not plot
#' noisy estimates.
#'
#' @param data    Tibble containing a `won` column (0/1 integer) and the
#'   `feature` column.
#' @param feature Character scalar; the name of the column in `data` to
#'   summarise over.
#' @param bins    One of:
#'   * `NULL` — use the feature directly as a factor. For numeric features,
#'     levels are ordered numerically (e.g. 2, 3, ..., 15) rather than
#'     lexicographically. Errors if the feature is numeric with more than
#'     20 unique non-NA values; supply explicit bins instead.
#'   * a single integer `N` — `N` quantile bins via `ggplot2::cut_number()`.
#'   * a numeric vector — used as `breaks` for `cut(include.lowest = TRUE,
#'     right = FALSE)`.
#' @param min_n   Minimum bin size below which `win_rate` and `se` are NA.
#'   Defaults to 30.
#' @return A tibble with columns `feature`, `feature_bin`, `n`, `n_wins`,
#'   `win_rate`, `se`.
summarise_win_rate <- function(data, feature, bins = NULL, min_n = 30) {
  if (!feature %in% names(data)) {
    stop("Feature '", feature, "' not found in data.", call. = FALSE)
  }
  if (!"won" %in% names(data)) {
    stop("Column 'won' not found in data.", call. = FALSE)
  }

  x <- data[[feature]]

  if (is.null(bins) && is.numeric(x)) {
    n_unique <- dplyr::n_distinct(x, na.rm = TRUE)
    if (n_unique > 20) {
      stop(
        "Feature '", feature, "' is numeric with ", n_unique,
        " unique non-NA values (> 20). Supply `bins` as either a single ",
        "integer (for quantile bins) or a numeric vector of breaks.",
        call. = FALSE
      )
    }
  }

  if (is.null(bins)) {
    if (is.numeric(x)) {
      lvls <- sort(unique(x[!is.na(x)]))
      x_bin <- factor(x, levels = lvls)
    } else {
      x_bin <- factor(x)
    }
  } else if (is.numeric(bins) && length(bins) == 1) {
    x_bin <- ggplot2::cut_number(x, n = bins)
  } else if (is.numeric(bins) && length(bins) > 1) {
    x_bin <- cut(x, breaks = bins, include.lowest = TRUE, right = FALSE)
  } else {
    stop(
      "`bins` must be NULL, a single integer, or a numeric vector of breaks.",
      call. = FALSE
    )
  }

  x_bin <- forcats::fct_na_value_to_level(x_bin, level = "(missing)")

  tibble::tibble(feature_bin = x_bin, won = data[["won"]]) |>
    dplyr::group_by(feature_bin) |>
    dplyr::summarise(
      n      = dplyr::n(),
      n_wins = sum(won),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      feature  = feature,
      win_rate = dplyr::if_else(n < min_n, NA_real_, n_wins / n),
      se       = dplyr::if_else(
        n < min_n,
        NA_real_,
        sqrt((n_wins / n) * (1 - n_wins / n) / n)
      )
    ) |>
    dplyr::select(feature, feature_bin, n, n_wins, win_rate, se)
}

#' Plot a win-rate summary
#'
#' Renders the output of `summarise_win_rate()` as a column chart of win
#' rate per bin with error bars and per-bin counts above each bar. A
#' dashed reference line marks the overall win rate of the data shown.
#'
#' @param summary        Tibble returned by `summarise_win_rate()`.
#' @param reference_line One of: "auto" (overall win rate), a numeric
#'   value, or NULL / NA for no line.
#' @param title          Plot title.
#' @param subtitle       Plot subtitle.
#' @return A ggplot object.
plot_win_rate <- function(summary,
                          reference_line = "auto",
                          title = NULL,
                          subtitle = NULL) {

  yref <- if (is.null(reference_line)) {
    NULL
  } else if (length(reference_line) == 1 && is.na(reference_line)) {
    NULL
  } else if (is.numeric(reference_line)) {
    reference_line
  } else if (identical(reference_line, "auto")) {
    sum(summary$n_wins) / sum(summary$n)
  } else {
    stop(
      "`reference_line` must be \"auto\", a numeric value, NULL, or NA; ",
      "got: ", deparse(reference_line),
      call. = FALSE
    )
  }

  caption_text <- paste0("n = ", scales::comma(sum(summary$n)))

  p <- ggplot2::ggplot(
    summary,
    ggplot2::aes(x = feature_bin, y = win_rate)
  ) +
    ggplot2::geom_col(fill = "steelblue", colour = "white") +
    ggplot2::geom_errorbar(
      ggplot2::aes(
        ymin = pmax(0, win_rate - se),
        ymax = win_rate + se
      ),
      width = 0.2,
      colour = "grey30"
    ) +
    ggplot2::geom_text(
      ggplot2::aes(y = win_rate + se, label = scales::comma(n)),
      vjust = -0.5,
      size  = 3
    ) +
    ggplot2::scale_y_continuous(
      labels = scales::percent_format(accuracy = 0.1)
    ) +
    ggplot2::labs(
      x        = NULL,
      y        = "Win rate",
      title    = title,
      subtitle = subtitle,
      caption  = caption_text
    ) +
    ggplot2::theme_minimal()

  if (!is.null(yref)) {
    p <- p + ggplot2::geom_hline(
      yintercept = yref,
      linetype   = "dashed",
      colour     = "grey40"
    )
  }

  p
}
