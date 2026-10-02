#!/usr/bin/env Rscript

# Add-on analysis for the completed 500-replication Monte Carlo run.
# Every plotted estimator is reconstructed explicitly as:
#   adjusted estimator = TWFE estimate - estimated selection bias.
# This script reads the existing replication-level output and creates only:
#   1) estimation_95ci_results.csv
#   2) estimation_95ci_forest_plot.png
# It does not rewrite any pre-existing Monte Carlo output.

options(stringsAsFactors = FALSE, scipen = 999)

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript so the project root can be resolved.")
}

script_path <- normalizePath(sub("^--file=", "", file_arg), winslash = "/", mustWork = TRUE)
project_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
final_dir <- file.path(project_root, "output", "final_500")
figure_dir <- file.path(final_dir, "figures")
input_file <- file.path(final_dir, "replication_results.csv")
ci_output_file <- file.path(final_dir, "estimation_95ci_results.csv")
forest_output_file <- file.path(figure_dir, "estimation_95ci_forest_plot.png")

if (!file.exists(input_file)) {
  stop("Missing input file: ", input_file)
}
if (!dir.exists(figure_dir)) {
  stop("Missing existing figures directory: ", figure_dir)
}

method_labels <- c(
  linear_adjusted_did = "Linear adjusted DID",
  synth_adjusted_did = "Synthetic control adjusted DID",
  random_forest_adjusted_did = "Random forest adjusted DID",
  gbm_adjusted_did = "Gradient boosting adjusted DID"
)
method_colors <- c(
  linear_adjusted_did = "#1FA187",
  synth_adjusted_did = "#FDE725",
  random_forest_adjusted_did = "#F8961E",
  gbm_adjusted_did = "#C51B7D"
)

raw <- read.csv(input_file, check.names = FALSE)
required_columns <- c(
  "scenario", "replication", "method", "true_ATT",
  "twfe_estimate", "estimated_selection_bias", "tau_estimate", "status"
)
missing_columns <- setdiff(required_columns, names(raw))
if (length(missing_columns) > 0L) {
  stop("Input is missing columns: ", paste(missing_columns, collapse = ", "))
}

method_order <- names(method_labels)
ok <- raw$status == "ok" &
  raw$method %in% method_order &
  is.finite(raw$twfe_estimate) &
  is.finite(raw$estimated_selection_bias) &
  is.finite(raw$true_ATT)
dat <- raw[ok, required_columns]
if (nrow(dat) == 0L) {
  stop("No successful finite selection-bias-adjusted estimates were found.")
}

dat$adjusted_estimator <- dat$twfe_estimate - dat$estimated_selection_bias
if (any(!is.finite(dat$adjusted_estimator))) {
  stop("A reconstructed adjusted estimator is non-finite.")
}

scenario_order <- unique(raw$scenario)

# The pipeline stores this same adjusted quantity in tau_estimate.  Keep this
# identity as a hard QA check, while using the explicit reconstruction below.
stored_adjusted_identity_max_error <- max(abs(dat$adjusted_estimator - dat$tau_estimate))
if (!is.finite(stored_adjusted_identity_max_error) ||
    stored_adjusted_identity_max_error >= 1e-10) {
  stop(
    "Stored tau_estimate does not match TWFE - estimated selection bias; max error = ",
    format(stored_adjusted_identity_max_error, scientific = TRUE)
  )
}

summarise_cell <- function(d) {
  n <- nrow(d)
  if (n < 2L) {
    stop("At least two successful replications are required for every scenario-method cell.")
  }
  true_values <- unique(d$true_ATT)
  if (length(true_values) != 1L) {
    stop("true_ATT is not constant within a scenario-method cell.")
  }
  mean_twfe <- mean(d$twfe_estimate)
  mean_estimated_selection_bias <- mean(d$estimated_selection_bias)
  estimate_mean <- mean(d$adjusted_estimator)
  estimate_sd <- stats::sd(d$adjusted_estimator)
  mcse <- estimate_sd / sqrt(n)
  t_critical <- stats::qt(0.975, df = n - 1L)
  ci_lower <- estimate_mean - t_critical * mcse
  ci_upper <- estimate_mean + t_critical * mcse
  empirical_quantiles <- as.numeric(stats::quantile(
    d$adjusted_estimator,
    probs = c(0.025, 0.975),
    names = FALSE,
    type = 7
  ))

  data.frame(
    scenario = d$scenario[1L],
    method = d$method[1L],
    method_label = unname(method_labels[d$method[1L]]),
    n_success = n,
    true_ATT = true_values,
    estimator_definition = "twfe_estimate - estimated_selection_bias",
    mean_twfe_before_adjustment = mean_twfe,
    mean_estimated_selection_bias = mean_estimated_selection_bias,
    mean_adjusted_estimate = estimate_mean,
    adjusted_estimator_bias = estimate_mean - true_values,
    adjusted_estimator_empirical_sd = estimate_sd,
    monte_carlo_standard_error = mcse,
    t_critical_95 = t_critical,
    adjusted_estimator_ci95_lower = ci_lower,
    adjusted_estimator_ci95_upper = ci_upper,
    adjusted_estimator_empirical_p025 = empirical_quantiles[1L],
    adjusted_estimator_empirical_p975 = empirical_quantiles[2L],
    true_att_in_mean_ci = ci_lower <= true_values & true_values <= ci_upper,
    stringsAsFactors = FALSE
  )
}

cell_key <- interaction(dat$scenario, dat$method, drop = TRUE, lex.order = TRUE)
ci_rows <- lapply(split(dat, cell_key), summarise_cell)
ci_results <- do.call(rbind, ci_rows)
row.names(ci_results) <- NULL

ci_results$scenario <- factor(ci_results$scenario, levels = scenario_order)
ci_results$method <- factor(ci_results$method, levels = method_order)
ci_results <- ci_results[order(ci_results$scenario, ci_results$method), ]
ci_results$scenario <- as.character(ci_results$scenario)
ci_results$method <- as.character(ci_results$method)
row.names(ci_results) <- NULL

expected_cells <- length(scenario_order) * length(method_order)
if (nrow(ci_results) != expected_cells) {
  stop("Expected ", expected_cells, " scenario-method cells but found ", nrow(ci_results), ".")
}
if (anyDuplicated(ci_results[c("scenario", "method")])) {
  stop("Duplicate scenario-method cells found in CI output.")
}
numeric_check <- c(
  "true_ATT", "mean_twfe_before_adjustment", "mean_estimated_selection_bias",
  "mean_adjusted_estimate", "adjusted_estimator_bias",
  "adjusted_estimator_empirical_sd", "monte_carlo_standard_error",
  "t_critical_95", "adjusted_estimator_ci95_lower",
  "adjusted_estimator_ci95_upper", "adjusted_estimator_empirical_p025",
  "adjusted_estimator_empirical_p975"
)
if (any(!is.finite(as.matrix(ci_results[numeric_check])))) {
  stop("CI output contains a non-finite numeric value.")
}
if (any(ci_results$adjusted_estimator_ci95_lower > ci_results$mean_adjusted_estimate) ||
    any(ci_results$mean_adjusted_estimate > ci_results$adjusted_estimator_ci95_upper)) {
  stop("A mean estimate lies outside its own confidence interval.")
}

ci_temp <- tempfile(fileext = ".csv")
utils::write.csv(ci_results, ci_temp, row.names = FALSE, na = "")
if (!file.copy(ci_temp, ci_output_file, overwrite = TRUE)) {
  stop("Could not create CI results file: ", ci_output_file)
}
unlink(ci_temp)

x_values <- c(
  ci_results$adjusted_estimator_ci95_lower,
  ci_results$adjusted_estimator_ci95_upper,
  ci_results$true_ATT
)
x_span <- diff(range(x_values))
if (!is.finite(x_span) || x_span == 0) {
  x_span <- 1
}
x_limits <- range(x_values) + c(-0.06, 0.06) * x_span

forest_temp <- tempfile(fileext = ".png")
grDevices::png(
  filename = forest_temp,
  width = 2400,
  height = 2500,
  res = 200,
  bg = "white"
)
graphics::par(
  mfrow = c(4, 2),
  mar = c(2.2, 10.3, 3.1, 1.0),
  oma = c(5.1, 0.5, 5.2, 0.5),
  las = 1,
  family = "sans"
)

for (scenario_name in scenario_order) {
  panel <- ci_results[ci_results$scenario == scenario_name, ]
  panel <- panel[match(method_order, panel$method), ]
  y <- rev(seq_along(method_order))

  graphics::plot(
    NA_real_, NA_real_,
    xlim = x_limits,
    ylim = c(0.5, length(method_order) + 0.5),
    xlab = "",
    ylab = "",
    yaxt = "n",
    main = scenario_name,
    bty = "n",
    cex.main = 0.95,
    cex.lab = 0.9
  )
  graphics::abline(v = panel$true_ATT[1L], col = "#B2182B", lty = 2, lwd = 2)
  graphics::abline(h = y, col = "#E8E8E8", lty = 3)
  graphics::segments(
    x0 = panel$adjusted_estimator_ci95_lower,
    y0 = y,
    x1 = panel$adjusted_estimator_ci95_upper,
    y1 = y,
    col = unname(method_colors[panel$method]),
    lwd = 3
  )
  cap_height <- 0.10
  graphics::segments(
    x0 = panel$adjusted_estimator_ci95_lower,
    y0 = y - cap_height,
    x1 = panel$adjusted_estimator_ci95_lower,
    y1 = y + cap_height,
    col = unname(method_colors[panel$method]),
    lwd = 2
  )
  graphics::segments(
    x0 = panel$adjusted_estimator_ci95_upper,
    y0 = y - cap_height,
    x1 = panel$adjusted_estimator_ci95_upper,
    y1 = y + cap_height,
    col = unname(method_colors[panel$method]),
    lwd = 2
  )
  graphics::points(
    x = panel$mean_adjusted_estimate,
    y = y,
    pch = 19,
    cex = 1.15,
    col = unname(method_colors[panel$method])
  )
  graphics::axis(
    side = 2,
    at = y,
    labels = unname(method_labels[panel$method]),
    tick = FALSE,
    cex.axis = 0.72,
    line = -0.5
  )
  graphics::box(col = "#BDBDBD")
}

# Eighth panel: compact interpretation and legend.
graphics::plot.new()
graphics::legend(
  "center",
  legend = c(unname(method_labels), "True ATT = 2"),
  col = c(unname(method_colors), "#B2182B"),
  pch = c(rep(19, length(method_labels)), NA),
  lty = c(rep(1, length(method_labels)), 2),
  lwd = c(rep(3, length(method_labels)), 2),
  pt.cex = 1.1,
  cex = 0.9,
  bty = "n",
  title = "Methods and reference"
)

graphics::mtext(
  "Selection-Bias-Adjusted ATT Estimates and 95% Confidence Intervals",
  side = 3,
  outer = TRUE,
  line = 2.7,
  cex = 1.45,
  font = 2
)
graphics::mtext(
  "Adjusted estimator = TWFE estimate - estimated selection bias. Each point is the mean of 500 replications.",
  side = 3,
  outer = TRUE,
  line = 1.35,
  cex = 0.93
)
graphics::mtext(
  "ATT estimate",
  side = 1,
  outer = TRUE,
  line = 3.35,
  cex = 0.95
)
graphics::mtext(
  "95% CI = mean adjusted estimate +/- t(0.975, 499) x Monte Carlo SE. Dashed red line: true ATT = 2.",
  side = 1,
  outer = TRUE,
  line = 1.45,
  cex = 0.85
)
grDevices::dev.off()

if (!file.copy(forest_temp, forest_output_file, overwrite = TRUE)) {
  stop("Could not create forest plot: ", forest_output_file)
}
unlink(forest_temp)

cat("Created:", ci_output_file, "\n")
cat("Created:", forest_output_file, "\n")
cat("Rows:", nrow(ci_results), "\n")
cat("Adjusted-estimator identity max error:",
    format(stored_adjusted_identity_max_error, scientific = TRUE), "\n")
cat("Scenario-method mean CIs containing the true ATT:",
    sum(ci_results$true_att_in_mean_ci), "of", nrow(ci_results), "\n")
