options(stringsAsFactors = FALSE)

root <- normalizePath("C:/Users/hishi/Documents/Codex/2026-09-13/xia", winslash = "/")
source_root <- normalizePath("C:/Users/hishi/Desktop/Paper/new paper process/monte_carlo_evaluation", winslash = "/")
out_root <- file.path(root, "outputs", "scenario_matched_revision")
dirs <- file.path(out_root, c("code", "results", "figures", "tables", "validation", "archive"))
invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))

.libPaths(c(file.path(source_root, "r_library"), .libPaths()))
source(file.path(source_root, "code", "monte_carlo_pipeline.R"), local = .GlobalEnv)

raw_path <- file.path(source_root, "output", "final_500", "replication_results.csv")
old_summary_path <- file.path(root, "outputs", "thesis_draft_outputs", "results_summary.csv")
raw <- read.csv(raw_path, check.names = FALSE)
old_summary <- read.csv(old_summary_path, check.names = FALSE)
twfe_saved <- raw[raw$method == "twfe", c("scenario", "replication", "dgp_seed", "twfe_estimate", "tau_estimate", "true_selection_bias")]
twfe_saved <- twfe_saved[order(twfe_saved$scenario, twfe_saved$replication), ]

pre_times <- 1:12
post_times <- 13:20
pre_mean_t <- mean(pre_times)
post_mean_t <- mean(post_times)
pre_mean_t2 <- mean(pre_times^2)
post_mean_t2 <- mean(post_times^2)

rows <- vector("list", 7L * 500L)
k <- 1L
for (s in seq_len(nrow(scenario_grid))) {
  cfg <- scenario_grid[s, , drop = FALSE]
  correction_type <- if (s == 1L) "none" else if (s %in% c(5L, 6L)) "quadratic_gap" else "linear_gap"
  for (r in 1:500) {
    seed <- 20370000L + 100000L * s + r
    dat <- generate_panel_data(cfg, seed)
    gaps_y <- gap_by_time(dat$Y, dat$treated, dat$time)
    gaps_y0 <- gap_by_time(dat$Y0, dat$treated, dat$time)
    pre_gap <- as.numeric(gaps_y[as.character(pre_times)])
    twfe <- mean(gaps_y[as.character(post_times)]) - mean(pre_gap)
    true_sb <- mean(gaps_y0[as.character(post_times)]) - mean(gaps_y0[as.character(pre_times)])
    beta1 <- beta2 <- NA_real_
    if (correction_type == "none") {
      sb_hat <- 0
      pre_fit_rmse <- 0
    } else {
      fitdat <- data.frame(gap = pre_gap, time = pre_times)
      if (correction_type == "linear_gap") {
        fit <- lm(gap ~ time, data = fitdat)
        beta1 <- unname(coef(fit)["time"])
      } else {
        fit <- lm(gap ~ time + I(time^2), data = fitdat)
        beta1 <- unname(coef(fit)["time"])
        beta2 <- unname(coef(fit)["I(time^2)"])
      }
      pred_pre <- predict(fit, newdata = data.frame(time = pre_times))
      pred_post <- predict(fit, newdata = data.frame(time = post_times))
      sb_hat <- mean(pred_post) - mean(pre_gap)
      pre_fit_rmse <- sqrt(mean((pred_pre - pre_gap)^2))
    }
    tau <- twfe - sb_hat
    rows[[k]] <- data.frame(
      scenario = cfg$scenario,
      replication = r,
      dgp_seed = seed,
      generation_attempt = attr(dat, "generation_attempt"),
      method = "scenario_matched_gap_adjusted_did",
      forecast_method = correction_type,
      true_ATT = TRUE_ATT,
      true_selection_bias = true_sb,
      estimated_selection_bias = sb_hat,
      selection_bias_error = sb_hat - true_sb,
      twfe_estimate = twfe,
      tau_estimate = tau,
      estimation_error = tau - TRUE_ATT,
      absolute_error = abs(tau - TRUE_ATT),
      squared_error = (tau - TRUE_ATT)^2,
      beta_linear = beta1,
      beta_quadratic = beta2,
      pre_gap_fit_rmse = pre_fit_rmse,
      status = "ok",
      stringsAsFactors = FALSE
    )
    k <- k + 1L
  }
}
res <- do.call(rbind, rows)

summarize_group <- function(x) {
  ok <- is.finite(x$tau_estimate)
  z <- x[ok, ]
  n <- nrow(x); ns <- nrow(z)
  err <- z$estimation_error
  sb_err <- z$estimated_selection_bias - z$true_selection_bias
  data.frame(
    scenario = x$scenario[1], method = x$method[1], forecast_method = x$forecast_method[1],
    true_ATT = TRUE_ATT, n_total = n, n_success = ns, n_failed = n - ns,
    failure_rate = (n - ns) / n, mean_estimate = mean(z$tau_estimate),
    monte_carlo_bias = mean(err), absolute_bias = abs(mean(err)),
    mean_absolute_error = mean(abs(err)), relative_bias_pct = 100 * mean(err) / TRUE_ATT,
    rmse = sqrt(mean(err^2)), empirical_sd = sd(z$tau_estimate),
    monte_carlo_standard_error = sd(z$tau_estimate) / sqrt(ns),
    mean_true_selection_bias = mean(z$true_selection_bias),
    mean_estimated_selection_bias = mean(z$estimated_selection_bias),
    selection_bias_mean_error = mean(sb_err),
    selection_bias_absolute_bias = abs(mean(sb_err)),
    selection_bias_mean_absolute_error = mean(abs(sb_err)),
    selection_bias_rmse = sqrt(mean(sb_err^2)),
    selection_bias_monte_carlo_se = sd(sb_err) / sqrt(ns),
    mean_runtime_seconds = NA_real_, total_runtime_seconds = NA_real_,
    variance_population = mean((z$tau_estimate - mean(z$tau_estimate))^2),
    variance_sample = var(z$tau_estimate),
    rmse_mcse = sd(err^2) / sqrt(ns) / (2 * sqrt(mean(err^2))),
    coverage = NA_real_, coverage_status = "not implemented",
    validation_status = "scenario-matched correction regenerated and independently checked",
    stringsAsFactors = FALSE
  )
}
summary_new <- do.call(rbind, lapply(split(res, res$scenario), summarize_group))

paired <- do.call(rbind, lapply(split(res, res$scenario), function(z) {
  e_new <- z$estimation_error
  e_twfe <- z$twfe_estimate - TRUE_ATT
  d_mse <- e_new^2 - e_twfe^2
  d_abs <- abs(e_new) - abs(e_twfe)
  data.frame(
    scenario = z$scenario[1], n = nrow(z),
    mean_error_matched = mean(e_new), mean_error_twfe = mean(e_twfe),
    mse_matched = mean(e_new^2), mse_twfe = mean(e_twfe^2),
    mse_difference_matched_minus_twfe = mean(d_mse),
    mse_difference_mcse = sd(d_mse) / sqrt(nrow(z)),
    mean_absolute_error_difference = mean(d_abs),
    rmse_matched = sqrt(mean(e_new^2)), rmse_twfe = sqrt(mean(e_twfe^2)),
    rmse_reduction_pct = 100 * (sqrt(mean(e_twfe^2)) - sqrt(mean(e_new^2))) / sqrt(mean(e_twfe^2)),
    stringsAsFactors = FALSE
  )
}))

coef_summary <- do.call(rbind, lapply(split(res, res$scenario), function(z) data.frame(
  scenario = z$scenario[1], correction = z$forecast_method[1],
  mean_beta_linear = if (all(is.na(z$beta_linear))) NA_real_ else mean(z$beta_linear, na.rm = TRUE),
  sd_beta_linear = if (all(is.na(z$beta_linear))) NA_real_ else sd(z$beta_linear, na.rm = TRUE),
  mean_beta_quadratic = if (all(is.na(z$beta_quadratic))) NA_real_ else mean(z$beta_quadratic, na.rm = TRUE),
  sd_beta_quadratic = if (all(is.na(z$beta_quadratic))) NA_real_ else sd(z$beta_quadratic, na.rm = TRUE),
  mean_pre_gap_fit_rmse = mean(z$pre_gap_fit_rmse), stringsAsFactors = FALSE
)))

all_summary <- rbind(old_summary[, names(summary_new)], summary_new)
scenario_order <- scenario_grid$scenario
method_order <- c("scenario_matched_gap_adjusted_did", "twfe", "linear_adjusted_did", "synth_adjusted_did", "random_forest_adjusted_did", "gbm_adjusted_did")
all_summary$scenario_num <- match(all_summary$scenario, scenario_order)
all_summary$method_num <- match(all_summary$method, method_order)
all_summary <- all_summary[order(all_summary$scenario_num, all_summary$method_num), setdiff(names(all_summary), c("scenario_num", "method_num"))]
ranking <- do.call(rbind, lapply(split(all_summary, all_summary$scenario), function(z) {
  z$rank_rmse <- rank(z$rmse, ties.method = "min")
  z$rank_absolute_bias <- rank(z$absolute_bias, ties.method = "min")
  z[order(z$rank_rmse, z$rank_absolute_bias), c("scenario", "method", "absolute_bias", "rmse", "variance_population", "rank_rmse", "rank_absolute_bias")]
}))
ranking$scenario_num <- match(ranking$scenario, scenario_order)
ranking <- ranking[order(ranking$scenario_num, ranking$rank_rmse, ranking$rank_absolute_bias), setdiff(names(ranking), "scenario_num")]

# Exact QA against stored final run and algebraic identities.
cmp <- merge(res, twfe_saved, by = c("scenario", "replication", "dgp_seed"), suffixes = c("_new", "_saved"))
lin <- res$forecast_method == "linear_gap"
quad <- res$forecast_method == "quadratic_gap"
qa <- data.frame(
  check = c("row_count_3500", "500_per_scenario", "finite_results", "twfe_matches_saved", "true_sb_matches_saved", "s0_no_correction", "linear_formula_identity", "quadratic_formula_identity", "error_identity", "mse_decomposition"),
  value = c(nrow(res), paste(as.integer(table(res$scenario)), collapse = ";"), sum(is.finite(res$tau_estimate)),
            max(abs(cmp$twfe_estimate_new - cmp$twfe_estimate_saved)), max(abs(cmp$true_selection_bias_new - cmp$true_selection_bias_saved)),
            max(abs(res$estimated_selection_bias[res$forecast_method == "none"])),
            max(abs(res$estimated_selection_bias[lin] - res$beta_linear[lin] * (post_mean_t - pre_mean_t))),
            max(abs(res$estimated_selection_bias[quad] - (res$beta_linear[quad] * (post_mean_t - pre_mean_t) + res$beta_quadratic[quad] * (post_mean_t2 - pre_mean_t2)))),
            max(abs(res$estimation_error + res$selection_bias_error)),
            max(abs(summary_new$rmse^2 - (summary_new$monte_carlo_bias^2 + summary_new$variance_population)))),
  passed = c(nrow(res) == 3500, all(table(res$scenario) == 500), all(is.finite(res$tau_estimate)),
             max(abs(cmp$twfe_estimate_new - cmp$twfe_estimate_saved)) < 1e-10,
             max(abs(cmp$true_selection_bias_new - cmp$true_selection_bias_saved)) < 1e-10,
             max(abs(res$estimated_selection_bias[res$forecast_method == "none"])) < 1e-12,
             max(abs(res$estimated_selection_bias[lin] - res$beta_linear[lin] * 10)) < 1e-10,
             max(abs(res$estimated_selection_bias[quad] - (res$beta_linear[quad] * 10 + res$beta_quadratic[quad] * (670/3)))) < 1e-10,
             max(abs(res$estimation_error + res$selection_bias_error)) < 1e-10,
             max(abs(summary_new$rmse^2 - (summary_new$monte_carlo_bias^2 + summary_new$variance_population))) < 1e-10),
  stringsAsFactors = FALSE
)

write.csv(res, file.path(out_root, "results", "scenario_matched_replication_results.csv"), row.names = FALSE)
saveRDS(res, file.path(out_root, "results", "scenario_matched_replication_results.rds"), compress = "xz")
write.csv(summary_new, file.path(out_root, "results", "scenario_matched_summary.csv"), row.names = FALSE)
write.csv(paired, file.path(out_root, "results", "scenario_matched_vs_twfe_paired.csv"), row.names = FALSE)
write.csv(coef_summary, file.path(out_root, "results", "scenario_matched_coefficients_summary.csv"), row.names = FALSE)
write.csv(all_summary, file.path(out_root, "results", "updated_all_method_summary.csv"), row.names = FALSE)
write.csv(ranking, file.path(out_root, "results", "updated_method_ranking_by_scenario.csv"), row.names = FALSE)
write.csv(qa, file.path(out_root, "validation", "scenario_matched_qa.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(out_root, "validation", "session_info.txt"))
if (!all(qa$passed)) stop("QA failed")

# Publication figures using only base R graphics.
method_order_plot <- c("scenario_matched_gap_adjusted_did", "twfe", "linear_adjusted_did", "synth_adjusted_did", "random_forest_adjusted_did", "gbm_adjusted_did")
method_labels_plot <- c("Matched gap adj.", "TWFE", "Common-slope adj.", "SC adj.", "RF adj.", "GBM adj.")
scenario_labels_plot <- paste0("S", 0:6)
metric_matrix <- function(metric) {
  z <- matrix(NA_real_, nrow = length(method_order_plot), ncol = length(scenario_order))
  for (i in seq_along(method_order_plot)) for (j in seq_along(scenario_order)) {
    z[i, j] <- all_summary[all_summary$method == method_order_plot[i] & all_summary$scenario == scenario_order[j], metric]
  }
  z
}
draw_heatmap <- function(z, title, signed = FALSE) {
  if (signed) {
    lim <- max(abs(z)); breaks <- seq(-lim, lim, length.out = 101)
    pal <- grDevices::colorRampPalette(c("#2166ac", "#f7f7f7", "#b2182b"))(100)
  } else {
    breaks <- seq(0, max(1, z), length.out = 101)
    pal <- grDevices::colorRampPalette(c("#f7fbff", "#6baed6", "#08306b"))(100)
  }
  graphics::image(seq_len(ncol(z)), seq_len(nrow(z)), t(z[nrow(z):1, ]), col = pal, breaks = breaks,
                  axes = FALSE, xlab = "", ylab = "", main = title)
  graphics::axis(1, at = seq_len(ncol(z)), labels = scenario_labels_plot)
  graphics::axis(2, at = seq_len(nrow(z)), labels = rev(method_labels_plot), las = 2, cex.axis = 0.82)
  for (i in seq_len(nrow(z))) for (j in seq_len(ncol(z))) {
    val <- z[i, j]
    graphics::text(j, nrow(z) - i + 1, sprintf("%.3f", val), cex = 0.75,
                   col = if (abs(val) > 0.58) "white" else "#17222d")
  }
  graphics::box(col = "#999999")
}
for (ext in c("pdf", "png")) {
  f <- file.path(out_root, "figures", paste0("updated_bias_rmse_comparison.", ext))
  if (ext == "pdf") grDevices::pdf(f, width = 7.4, height = 7.2, useDingbats = FALSE) else grDevices::png(f, width = 1480, height = 1440, res = 200)
  graphics::par(mfrow = c(2, 1), mar = c(3.2, 9.0, 3.0, 1.0), oma = c(0, 0, 0, 0))
  draw_heatmap(metric_matrix("monte_carlo_bias"), "Signed Monte Carlo bias", TRUE)
  draw_heatmap(metric_matrix("rmse"), "Root mean squared error", FALSE)
  grDevices::dev.off()
}
for (ext in c("pdf", "png")) {
  f <- file.path(out_root, "figures", paste0("scenario_matched_paired_mse.", ext))
  if (ext == "pdf") grDevices::pdf(f, width = 7.2, height = 4.1, useDingbats = FALSE) else grDevices::png(f, width = 1440, height = 820, res = 200)
  yy <- rev(seq_len(nrow(paired)))
  dd <- paired$mse_difference_matched_minus_twfe
  ee <- 1.96 * paired$mse_difference_mcse
  graphics::par(mar = c(5, 5, 2, 1))
  graphics::plot(dd, yy, xlim = range(c(dd - ee, dd + ee, 0)), ylim = c(0.5, 7.5), yaxt = "n", pch = 19,
                 col = "#136f7a", xlab = "Paired MSE difference: matched correction minus TWFE", ylab = "")
  graphics::axis(2, at = yy, labels = scenario_labels_plot, las = 1)
  graphics::abline(v = 0, lty = 2, col = "#555555")
  graphics::segments(dd - ee, yy, dd + ee, yy, col = "#136f7a", lwd = 1.5)
  graphics::segments(dd - ee, yy - 0.08, dd - ee, yy + 0.08, col = "#136f7a")
  graphics::segments(dd + ee, yy - 0.08, dd + ee, yy + 0.08, col = "#136f7a")
  graphics::grid(nx = NA, ny = NULL, col = "#dddddd")
  graphics::points(dd, yy, pch = 19, col = "#136f7a")
  grDevices::dev.off()
}
print(summary_new[, c("scenario", "forecast_method", "mean_estimate", "monte_carlo_bias", "rmse", "variance_population")], row.names = FALSE)
print(paired[, c("scenario", "rmse_matched", "rmse_twfe", "rmse_reduction_pct", "mse_difference_matched_minus_twfe", "mse_difference_mcse")], row.names = FALSE)
print(qa, row.names = FALSE)
