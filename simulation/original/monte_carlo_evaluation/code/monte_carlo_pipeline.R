# ============================================================
# Monte Carlo evaluation for forecasting-based DiD correction
#
# This project is intentionally self-contained and never writes to the
# existing simulation_output directory. It reproduces the seven-scenario DGP
# and retains the original model specifications:
#   - conventional TWFE point estimate;
#   - linear forecast with unit fixed effects and a common linear time trend;
#   - aggregate-treated synthetic control using Synth;
#   - random forest with 500 trees;
#   - GBM with 800 trees, depth 3, shrinkage 0.01, and bag fraction 0.7.
#
# Selection bias is aligned with the TWFE estimand:
#   average post-treatment untreated gap - average pre-treatment gap.
# ============================================================

get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grepl("^--file=", args)]
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  }
  normalizePath(getwd())
}

PROJECT_ROOT <- normalizePath(file.path(get_script_dir(), ".."), mustWork = FALSE)
OUTPUT_ROOT <- file.path(PROJECT_ROOT, "output")
LOG_ROOT <- file.path(PROJECT_ROOT, "logs")

dir.create(OUTPUT_ROOT, recursive = TRUE, showWarnings = FALSE)
dir.create(LOG_ROOT, recursive = TRUE, showWarnings = FALSE)

REQUIRED_PACKAGES <- c("randomForest", "gbm", "Synth")

check_dependencies <- function() {
  missing <- REQUIRED_PACKAGES[
    !vapply(REQUIRED_PACKAGES, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing) > 0) {
    stop(
      paste0(
        "Missing required R packages: ", paste(missing, collapse = ", "),
        ". Install them before running: install.packages(c(",
        paste(sprintf("'%s'", missing), collapse = ", "), "))"
      ),
      call. = FALSE
    )
  }
}

# -------------------------
# 1. DGP configuration
# -------------------------

N_UNITS <- 200L
N_PERIODS <- 20L
N_PRE_PERIODS <- 12L
TRUE_ATT <- 2

scenario_grid <- data.frame(
  scenario = c(
    "S0_parallel_trends",
    "S1_linear_weak",
    "S2_linear_moderate",
    "S3_linear_strong",
    "S4_quadratic_moderate",
    "S5_quadratic_strong",
    "S6_linear_high_noise"
  ),
  trend_type = c(
    "linear", "linear", "linear", "linear",
    "quadratic", "quadratic", "linear"
  ),
  theta_mean = rep(0, 7),
  theta_sd = c(0, 0.02, 0.05, 0.10, 0.0025, 0.0050, 0.05),
  delta0 = rep(-0.40, 7),
  delta1 = c(0, 10, 10, 10, 200, 200, 10),
  sigma_alpha = rep(1, 7),
  gamma_slope = rep(0.10, 7),
  sigma_epsilon = c(1, 1, 1, 1, 1, 1, 3),
  stringsAsFactors = FALSE
)

inverse_logit <- function(x) stats::plogis(x)

trend_function <- function(time, trend_type) {
  if (identical(trend_type, "linear")) return(time)
  if (identical(trend_type, "quadratic")) return(time^2)
  stop("trend_type must be either 'linear' or 'quadratic'.")
}

generate_panel_data <- function(cfg, seed, max_attempts = 100L) {
  for (attempt in seq_len(max_attempts)) {
    set.seed(seed + (attempt - 1L) * 10000000L)

    X1 <- stats::rnorm(N_UNITS)
    X2 <- stats::rbinom(N_UNITS, size = 1, prob = 0.50)
    X3 <- stats::runif(N_UNITS, min = -1, max = 1)

    alpha_unobserved <- stats::rnorm(N_UNITS, sd = cfg$sigma_alpha)
    alpha_i <- 0.60 * X1 - 0.40 * X2 + 0.30 * X3 + alpha_unobserved

    if (cfg$theta_sd == 0) {
      theta_i <- rep(cfg$theta_mean, N_UNITS)
    } else {
      theta_i <- stats::rnorm(
        N_UNITS,
        mean = cfg$theta_mean,
        sd = cfg$theta_sd
      )
    }

    p_i <- inverse_logit(cfg$delta0 + cfg$delta1 * theta_i)
    D_i <- stats::rbinom(N_UNITS, size = 1, prob = p_i)

    if (length(unique(D_i)) < 2) next

    panel <- expand.grid(
      time = seq_len(N_PERIODS),
      id = seq_len(N_UNITS)
    )
    panel <- panel[order(panel$id, panel$time), ]

    panel$X1 <- X1[panel$id]
    panel$X2 <- X2[panel$id]
    panel$X3 <- X3[panel$id]
    panel$alpha_i <- alpha_i[panel$id]
    panel$theta_i <- theta_i[panel$id]
    panel$p_i <- p_i[panel$id]
    panel$treated <- D_i[panel$id]

    panel$gamma_t <- cfg$gamma_slope * panel$time
    panel$f_t <- trend_function(panel$time, cfg$trend_type)
    panel$epsilon_it <- stats::rnorm(nrow(panel), sd = cfg$sigma_epsilon)
    panel$Y0 <- panel$alpha_i + panel$gamma_t +
      panel$theta_i * panel$f_t + panel$epsilon_it

    panel$post <- as.integer(panel$time > N_PRE_PERIODS)
    panel$did <- panel$treated * panel$post
    panel$Y <- panel$Y0 + TRUE_ATT * panel$did
    panel$scenario <- cfg$scenario

    attr(panel, "generation_attempt") <- attempt
    return(panel)
  }

  stop("Could not generate both treated and control units after retrying.")
}

# -------------------------
# 2. Common estimand helpers
# -------------------------

gap_by_time <- function(outcome, treated, time) {
  times <- sort(unique(time))
  values <- vapply(times, function(tt) {
    idx <- time == tt
    mean(outcome[idx & treated == 1]) - mean(outcome[idx & treated == 0])
  }, numeric(1))
  names(values) <- as.character(times)
  values
}

average_pre_observed_gap <- function(data) {
  gaps <- gap_by_time(data$Y, data$treated, data$time)
  mean(gaps[as.character(sort(unique(data$time[data$post == 0])))])
}

true_selection_bias <- function(data) {
  gaps <- gap_by_time(data$Y0, data$treated, data$time)
  pre_times <- as.character(sort(unique(data$time[data$post == 0])))
  post_times <- as.character(sort(unique(data$time[data$post == 1])))
  mean(gaps[post_times]) - mean(gaps[pre_times])
}

twfe_point_estimate <- function(data) {
  # For this balanced panel with common treatment timing, the TWFE coefficient
  # is exactly the post-minus-pre change in the treated-control mean gap.
  gaps <- gap_by_time(data$Y, data$treated, data$time)
  pre_times <- as.character(sort(unique(data$time[data$post == 0])))
  post_times <- as.character(sort(unique(data$time[data$post == 1])))
  mean(gaps[post_times]) - mean(gaps[pre_times])
}

selection_bias_from_prediction <- function(data, y0_hat) {
  predicted_gaps <- gap_by_time(y0_hat, data$treated, data$time)
  post_times <- as.character(sort(unique(data$time[data$post == 1])))
  mean(predicted_gaps[post_times]) - average_pre_observed_gap(data)
}

# -------------------------
# 3. Forecasting estimators
# -------------------------

linear_forecast <- function(data) {
  # Exact within-estimator representation of Y ~ time | id. X1-X3 are
  # time-invariant and therefore collinear with the unit fixed effects.
  pre <- data$post == 0
  pre_id <- data$id[pre]
  pre_time <- data$time[pre]
  pre_y <- data$Y[pre]

  id_mean_y <- tapply(pre_y, pre_id, mean)
  id_mean_time <- tapply(pre_time, pre_id, mean)
  centered_time <- pre_time - id_mean_time[as.character(pre_id)]
  centered_y <- pre_y - id_mean_y[as.character(pre_id)]
  beta_time <- sum(centered_time * centered_y) / sum(centered_time^2)
  unit_intercepts <- id_mean_y - beta_time * id_mean_time

  as.numeric(unit_intercepts[as.character(data$id)] + beta_time * data$time)
}

synth_forecast <- function(data) {
  treated_path <- stats::aggregate(
    Y ~ time,
    data = data[data$treated == 1, c("time", "Y")],
    FUN = mean
  )
  treated_path$id <- 999999L

  control_path <- data[data$treated == 0, c("id", "time", "Y")]
  synth_df <- rbind(
    control_path,
    treated_path[, c("id", "time", "Y")]
  )

  pre_times <- sort(unique(data$time[data$post == 0]))
  all_times <- sort(unique(data$time))

  dp <- Synth::dataprep(
    foo = synth_df,
    predictors = "Y",
    predictors.op = "mean",
    dependent = "Y",
    unit.variable = "id",
    time.variable = "time",
    treatment.identifier = 999999L,
    controls.identifier = sort(unique(control_path$id)),
    time.predictors.prior = pre_times,
    time.optimize.ssr = pre_times,
    time.plot = all_times
  )

  invisible(utils::capture.output(
    sy <- Synth::synth(data.prep.obj = dp)
  ))

  synth_treated_hat <- as.numeric(dp$Y0plot %*% sy$solution.w)
  control_mean <- stats::aggregate(
    Y ~ time,
    data = control_path,
    FUN = mean
  )

  # Construct unit-level values whose treated-control mean gap equals the
  # aggregate synthetic-control gap at every time. Only the gap is required
  # for the selection-bias estimand.
  synth_by_time <- setNames(synth_treated_hat, all_times)
  control_by_time <- setNames(control_mean$Y, control_mean$time)
  if (any(!is.finite(synth_by_time)) || any(!is.finite(control_by_time))) {
    stop("Synthetic-control prediction contains non-finite values.")
  }

  predicted_gap <- synth_by_time - control_by_time[names(synth_by_time)]
  list(
    predicted_gap = predicted_gap,
    donor_weights = as.numeric(sy$solution.w)
  )
}

rf_forecast <- function(data, seed) {
  feature_cols <- c("id_num", "time", "treated", "X1", "X2", "X3")
  train <- data[data$post == 0, ]
  train$id_num <- train$id
  pred <- data
  pred$id_num <- pred$id

  formula_rf <- stats::as.formula(
    paste0("Y ~ ", paste(feature_cols, collapse = " + "))
  )

  set.seed(seed)
  fit <- randomForest::randomForest(
    formula = formula_rf,
    data = train[, c("Y", feature_cols)],
    ntree = 500,
    mtry = max(1, floor(sqrt(length(feature_cols)))),
    importance = FALSE
  )
  as.numeric(stats::predict(fit, newdata = pred))
}

gbm_forecast <- function(data, seed) {
  feature_cols <- c("time", "treated", "X1", "X2", "X3", "id")
  train <- data[data$post == 0, c("Y", feature_cols)]
  formula_gbm <- stats::as.formula(
    paste0("Y ~ ", paste(feature_cols, collapse = " + "))
  )

  set.seed(seed)
  fit <- gbm::gbm(
    formula = formula_gbm,
    data = train,
    distribution = "gaussian",
    n.trees = 800,
    interaction.depth = 3,
    shrinkage = 0.01,
    n.minobsinnode = 10,
    bag.fraction = 0.7,
    train.fraction = 1.0,
    cv.folds = 0,
    verbose = FALSE
  )
  as.numeric(stats::predict(fit, newdata = data, n.trees = 800))
}

# -------------------------
# 4. One-replication evaluation
# -------------------------

make_result_row <- function(
    run_label,
    scenario,
    replication,
    dgp_seed,
    generation_attempt,
    method,
    forecast_method,
    true_sb,
    sb_hat,
    twfe_estimate,
    tau_estimate,
    runtime_seconds,
    status = "ok",
    message = "") {

  estimation_error <- tau_estimate - TRUE_ATT
  sb_error <- sb_hat - true_sb

  data.frame(
    run_label = run_label,
    scenario = scenario,
    replication = replication,
    dgp_seed = dgp_seed,
    generation_attempt = generation_attempt,
    method = method,
    forecast_method = forecast_method,
    true_ATT = TRUE_ATT,
    true_selection_bias = true_sb,
    estimated_selection_bias = sb_hat,
    selection_bias_error = sb_error,
    twfe_estimate = twfe_estimate,
    tau_estimate = tau_estimate,
    estimation_error = estimation_error,
    absolute_error = abs(estimation_error),
    squared_error = estimation_error^2,
    runtime_seconds = runtime_seconds,
    status = status,
    message = message,
    stringsAsFactors = FALSE
  )
}

make_failed_row <- function(
    run_label,
    scenario,
    replication,
    dgp_seed,
    generation_attempt,
    method,
    forecast_method,
    true_sb,
    twfe_estimate,
    runtime_seconds,
    message) {

  make_result_row(
    run_label = run_label,
    scenario = scenario,
    replication = replication,
    dgp_seed = dgp_seed,
    generation_attempt = generation_attempt,
    method = method,
    forecast_method = forecast_method,
    true_sb = true_sb,
    sb_hat = NA_real_,
    twfe_estimate = twfe_estimate,
    tau_estimate = NA_real_,
    runtime_seconds = runtime_seconds,
    status = "failed",
    message = message
  )
}

evaluate_forecast_method <- function(
    run_label,
    data,
    replication,
    dgp_seed,
    generation_attempt,
    method,
    forecast_method,
    true_sb,
    twfe_estimate,
    method_seed) {

  started <- proc.time()[["elapsed"]]

  tryCatch({
    if (identical(forecast_method, "linear")) {
      prediction <- linear_forecast(data)
      sb_hat <- selection_bias_from_prediction(data, prediction)
    } else if (identical(forecast_method, "synth")) {
      synth_result <- synth_forecast(data)
      pre_times <- as.character(sort(unique(data$time[data$post == 0])))
      post_times <- as.character(sort(unique(data$time[data$post == 1])))
      sb_hat <- mean(synth_result$predicted_gap[post_times]) -
        average_pre_observed_gap(data)
    } else if (identical(forecast_method, "random_forest")) {
      prediction <- rf_forecast(data, method_seed)
      sb_hat <- selection_bias_from_prediction(data, prediction)
    } else if (identical(forecast_method, "gbm")) {
      prediction <- gbm_forecast(data, method_seed)
      sb_hat <- selection_bias_from_prediction(data, prediction)
    } else {
      stop("Unknown forecast method: ", forecast_method)
    }

    tau_adjusted <- twfe_estimate - sb_hat
    elapsed <- proc.time()[["elapsed"]] - started

    make_result_row(
      run_label = run_label,
      scenario = data$scenario[1],
      replication = replication,
      dgp_seed = dgp_seed,
      generation_attempt = generation_attempt,
      method = method,
      forecast_method = forecast_method,
      true_sb = true_sb,
      sb_hat = sb_hat,
      twfe_estimate = twfe_estimate,
      tau_estimate = tau_adjusted,
      runtime_seconds = elapsed
    )
  }, error = function(e) {
    elapsed <- proc.time()[["elapsed"]] - started
    make_failed_row(
      run_label = run_label,
      scenario = data$scenario[1],
      replication = replication,
      dgp_seed = dgp_seed,
      generation_attempt = generation_attempt,
      method = method,
      forecast_method = forecast_method,
      true_sb = true_sb,
      twfe_estimate = twfe_estimate,
      runtime_seconds = elapsed,
      message = conditionMessage(e)
    )
  })
}

evaluate_replication <- function(task, run_label) {
  cfg <- scenario_grid[task$scenario_index, , drop = FALSE]
  data <- generate_panel_data(cfg, seed = task$dgp_seed)
  generation_attempt <- attr(data, "generation_attempt")

  true_sb <- true_selection_bias(data)
  twfe_estimate <- twfe_point_estimate(data)

  twfe_row <- make_result_row(
    run_label = run_label,
    scenario = cfg$scenario,
    replication = task$replication,
    dgp_seed = task$dgp_seed,
    generation_attempt = generation_attempt,
    method = "twfe",
    forecast_method = NA_character_,
    true_sb = true_sb,
    sb_hat = NA_real_,
    twfe_estimate = twfe_estimate,
    tau_estimate = twfe_estimate,
    runtime_seconds = 0
  )

  specs <- data.frame(
    method = c(
      "linear_adjusted_did",
      "synth_adjusted_did",
      "random_forest_adjusted_did",
      "gbm_adjusted_did"
    ),
    forecast_method = c("linear", "synth", "random_forest", "gbm"),
    seed_offset = c(1000000L, 2000000L, 3000000L, 4000000L),
    stringsAsFactors = FALSE
  )

  forecast_rows <- lapply(seq_len(nrow(specs)), function(j) {
    evaluate_forecast_method(
      run_label = run_label,
      data = data,
      replication = task$replication,
      dgp_seed = task$dgp_seed,
      generation_attempt = generation_attempt,
      method = specs$method[j],
      forecast_method = specs$forecast_method[j],
      true_sb = true_sb,
      twfe_estimate = twfe_estimate,
      method_seed = task$dgp_seed + specs$seed_offset[j]
    )
  })

  do.call(rbind, c(list(twfe_row), forecast_rows))
}

task_failure_rows <- function(task, run_label, message) {
  methods <- c(
    "twfe",
    "linear_adjusted_did",
    "synth_adjusted_did",
    "random_forest_adjusted_did",
    "gbm_adjusted_did"
  )
  forecasts <- c(NA, "linear", "synth", "random_forest", "gbm")

  do.call(rbind, lapply(seq_along(methods), function(j) {
    make_failed_row(
      run_label = run_label,
      scenario = scenario_grid$scenario[task$scenario_index],
      replication = task$replication,
      dgp_seed = task$dgp_seed,
      generation_attempt = NA_integer_,
      method = methods[j],
      forecast_method = forecasts[j],
      true_sb = NA_real_,
      twfe_estimate = NA_real_,
      runtime_seconds = NA_real_,
      message = message
    )
  }))
}

safe_evaluate_task <- function(task, run_label) {
  tryCatch(
    evaluate_replication(task, run_label),
    error = function(e) task_failure_rows(task, run_label, conditionMessage(e))
  )
}

# -------------------------
# 5. Summary statistics and QA
# -------------------------

summarize_one_group <- function(group) {
  ok <- group$status == "ok" & is.finite(group$tau_estimate)
  errors <- group$estimation_error[ok]
  estimates <- group$tau_estimate[ok]
  sb_ok <- ok & is.finite(group$selection_bias_error)
  sb_errors <- group$selection_bias_error[sb_ok]

  n_success <- sum(ok)
  n_total <- nrow(group)

  safe_mean <- function(x) if (length(x) == 0) NA_real_ else mean(x)
  safe_sd <- function(x) if (length(x) <= 1) NA_real_ else stats::sd(x)
  safe_rmse <- function(x) if (length(x) == 0) NA_real_ else sqrt(mean(x^2))

  mc_bias <- safe_mean(errors)

  data.frame(
    scenario = group$scenario[1],
    method = group$method[1],
    forecast_method = group$forecast_method[1],
    true_ATT = TRUE_ATT,
    n_total = n_total,
    n_success = n_success,
    n_failed = n_total - n_success,
    failure_rate = (n_total - n_success) / n_total,
    mean_estimate = safe_mean(estimates),
    monte_carlo_bias = mc_bias,
    absolute_bias = abs(mc_bias),
    mean_absolute_error = safe_mean(abs(errors)),
    relative_bias_pct = 100 * mc_bias / TRUE_ATT,
    rmse = safe_rmse(errors),
    empirical_sd = safe_sd(estimates),
    monte_carlo_standard_error = safe_sd(errors) / sqrt(n_success),
    mean_true_selection_bias = safe_mean(group$true_selection_bias[ok]),
    mean_estimated_selection_bias = safe_mean(group$estimated_selection_bias[sb_ok]),
    selection_bias_mean_error = safe_mean(sb_errors),
    selection_bias_absolute_bias = abs(safe_mean(sb_errors)),
    selection_bias_mean_absolute_error = safe_mean(abs(sb_errors)),
    selection_bias_rmse = safe_rmse(sb_errors),
    selection_bias_monte_carlo_se = safe_sd(sb_errors) / sqrt(sum(sb_ok)),
    mean_runtime_seconds = safe_mean(group$runtime_seconds[ok]),
    total_runtime_seconds = sum(group$runtime_seconds, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

make_summary <- function(results) {
  keys <- interaction(results$scenario, results$method, drop = TRUE)
  groups <- split(results, keys)
  summary <- do.call(rbind, lapply(groups, summarize_one_group))
  row.names(summary) <- NULL
  summary[order(summary$scenario, summary$method), ]
}

run_quality_checks <- function(results, repetitions, summary) {
  expected_rows <- nrow(scenario_grid) * repetitions * 5L
  key <- paste(results$scenario, results$replication, results$method, sep = "|")
  duplicate_keys <- sum(duplicated(key))

  ok <- results$status == "ok"
  finite_success <- all(
    is.finite(results$tau_estimate[ok]) &
      is.finite(results$estimation_error[ok])
  )

  twfe <- results[results$method == "twfe" & ok, ]
  twfe_identity_max_error <- if (nrow(twfe) == 0) {
    Inf
  } else {
    max(abs(twfe$estimation_error - twfe$true_selection_bias))
  }

  adjusted <- results[results$method != "twfe" & ok, ]
  adjusted_identity_max_error <- if (nrow(adjusted) == 0) {
    Inf
  } else {
    max(abs(
      adjusted$tau_estimate -
        (adjusted$twfe_estimate - adjusted$estimated_selection_bias)
    ))
  }

  counts <- table(results$scenario, results$method)
  complete_coverage <- all(counts == repetitions)
  max_failure_rate <- max(summary$failure_rate)

  checks <- data.frame(
    check = c(
      "expected_row_count",
      "no_duplicate_keys",
      "complete_scenario_method_coverage",
      "finite_successful_estimates",
      "twfe_error_equals_true_selection_bias",
      "adjusted_did_identity",
      "maximum_failure_rate_at_most_10pct"
    ),
    observed = c(
      sprintf("%d of %d", nrow(results), expected_rows),
      as.character(duplicate_keys),
      as.character(complete_coverage),
      as.character(finite_success),
      format(twfe_identity_max_error, scientific = TRUE),
      format(adjusted_identity_max_error, scientific = TRUE),
      format(max_failure_rate, digits = 6)
    ),
    passed = c(
      nrow(results) == expected_rows,
      duplicate_keys == 0,
      complete_coverage,
      finite_success,
      is.finite(twfe_identity_max_error) && twfe_identity_max_error < 1e-10,
      is.finite(adjusted_identity_max_error) && adjusted_identity_max_error < 1e-10,
      is.finite(max_failure_rate) && max_failure_rate <= 0.10
    ),
    stringsAsFactors = FALSE
  )

  checks
}

# -------------------------
# 6. Base-R figures
# -------------------------

method_order <- c(
  "twfe",
  "linear_adjusted_did",
  "synth_adjusted_did",
  "random_forest_adjusted_did",
  "gbm_adjusted_did"
)

method_labels <- c(
  twfe = "TWFE",
  linear_adjusted_did = "Linear adjusted",
  synth_adjusted_did = "Synth adjusted",
  random_forest_adjusted_did = "RF adjusted",
  gbm_adjusted_did = "GBM adjusted"
)

method_colors <- c("#555555", "#2C7BB6", "#1A9641", "#FDAE61", "#D7191C")

summary_matrix <- function(summary, value_col) {
  scenarios <- scenario_grid$scenario
  active_methods <- method_order[method_order %in% unique(summary$method)]
  out <- matrix(
    NA_real_,
    nrow = length(active_methods),
    ncol = length(scenarios),
    dimnames = list(method_labels[active_methods], scenarios)
  )
  for (i in seq_len(nrow(summary))) {
    out[method_labels[summary$method[i]], summary$scenario[i]] <-
      summary[[value_col]][i]
  }
  out
}

plot_bar_metric <- function(summary, value_col, ylab, title, path, zero_line = FALSE) {
  mat <- summary_matrix(summary, value_col)
  grDevices::png(path, width = 1800, height = 1000, res = 160)
  old <- graphics::par(mar = c(10, 5, 4, 2) + 0.1)
  on.exit({graphics::par(old); grDevices::dev.off()}, add = TRUE)
  graphics::barplot(
    mat,
    beside = TRUE,
    col = method_colors,
    las = 2,
    ylab = ylab,
    main = title,
    names.arg = colnames(mat),
    cex.names = 0.8
  )
  if (zero_line) graphics::abline(h = 0, lty = 2)
  graphics::legend(
    "topright",
    legend = rownames(mat),
    fill = method_colors,
    cex = 0.8,
    bty = "n"
  )
}

plot_heatmap_metric <- function(summary, value_col, title, path) {
  mat <- summary_matrix(summary, value_col)
  z <- t(mat)
  finite_values <- z[is.finite(z)]
  if (length(finite_values) == 0) return(invisible(NULL))
  limits <- range(finite_values)
  if (diff(limits) == 0) limits <- limits + c(-0.5, 0.5)

  palette <- grDevices::colorRampPalette(c("#F7FBFF", "#6BAED6", "#08306B"))(100)
  grDevices::png(path, width = 1600, height = 900, res = 160)
  old <- graphics::par(mar = c(10, 14, 4, 2) + 0.1)
  on.exit({graphics::par(old); grDevices::dev.off()}, add = TRUE)
  graphics::image(
    x = seq_len(nrow(z)),
    y = seq_len(ncol(z)),
    z = z,
    col = palette,
    zlim = limits,
    axes = FALSE,
    xlab = "Scenario",
    ylab = "",
    main = title
  )
  graphics::axis(1, at = seq_len(nrow(z)), labels = rownames(z), las = 2, cex.axis = 0.8)
  graphics::axis(2, at = seq_len(ncol(z)), labels = colnames(z), las = 2, cex.axis = 0.8)
  graphics::mtext("Method", side = 2, line = 11)
  for (i in seq_len(nrow(z))) {
    for (j in seq_len(ncol(z))) {
      if (is.finite(z[i, j])) {
        graphics::text(i, j, labels = sprintf("%.3f", z[i, j]), cex = 0.72)
      }
    }
  }
}

make_figures <- function(summary, figure_dir) {
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  plot_bar_metric(
    summary,
    "monte_carlo_bias",
    "Monte Carlo bias",
    "Monte Carlo Bias by Scenario and Method",
    file.path(figure_dir, "monte_carlo_bias_by_method.png"),
    zero_line = TRUE
  )
  plot_bar_metric(
    summary,
    "rmse",
    "RMSE",
    "Estimator RMSE by Scenario and Method",
    file.path(figure_dir, "rmse_by_method.png")
  )
  plot_heatmap_metric(
    summary,
    "absolute_bias",
    "Absolute Monte Carlo Bias",
    file.path(figure_dir, "absolute_bias_heatmap.png")
  )
  plot_heatmap_metric(
    summary,
    "rmse",
    "Estimator RMSE",
    file.path(figure_dir, "rmse_heatmap.png")
  )

  forecast_summary <- summary[summary$method != "twfe", ]
  plot_heatmap_metric(
    forecast_summary,
    "selection_bias_rmse",
    "Selection-Bias Estimation RMSE",
    file.path(figure_dir, "selection_bias_rmse_heatmap.png")
  )
}

# -------------------------
# 7. Batched, restartable runner
# -------------------------

worker_exports <- c(
  "scenario_grid", "N_UNITS", "N_PERIODS", "N_PRE_PERIODS", "TRUE_ATT",
  "inverse_logit", "trend_function", "generate_panel_data", "gap_by_time",
  "average_pre_observed_gap", "true_selection_bias", "twfe_point_estimate",
  "selection_bias_from_prediction", "linear_forecast", "synth_forecast",
  "rf_forecast", "gbm_forecast", "make_result_row", "make_failed_row",
  "evaluate_forecast_method", "evaluate_replication", "task_failure_rows",
  "safe_evaluate_task"
)

run_simulation <- function(
    run_label,
    repetitions,
    cores = max(1L, min(4L, parallel::detectCores() - 1L)),
    batch_size = 10L,
    base_seed = 20270000L) {

  check_dependencies()

  run_dir <- file.path(OUTPUT_ROOT, run_label)
  checkpoint_dir <- file.path(run_dir, "checkpoints")
  figure_dir <- file.path(run_dir, "figures")
  dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

  metadata <- data.frame(
    run_label = run_label,
    repetitions = repetitions,
    scenarios = nrow(scenario_grid),
    methods = 5L,
    cores = cores,
    batch_size = batch_size,
    base_seed = base_seed,
    started_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  utils::write.csv(metadata, file.path(run_dir, "run_metadata.csv"), row.names = FALSE)

  tasks <- list()
  counter <- 1L
  for (s in seq_len(nrow(scenario_grid))) {
    for (r in seq_len(repetitions)) {
      tasks[[counter]] <- list(
        scenario_index = s,
        replication = r,
        dgp_seed = base_seed + 100000L * s + r
      )
      counter <- counter + 1L
    }
  }

  batch_id <- ceiling(vapply(tasks, `[[`, integer(1), "replication") / batch_size)
  batches <- split(tasks, batch_id)

  cl <- NULL
  if (cores > 1L) {
    cl <- parallel::makeCluster(cores)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterExport(cl, worker_exports, envir = globalenv())
  }

  run_started <- proc.time()[["elapsed"]]

  for (b in seq_along(batches)) {
    checkpoint_path <- file.path(
      checkpoint_dir,
      sprintf("batch_%04d.rds", as.integer(names(batches)[b]))
    )
    if (file.exists(checkpoint_path)) {
      cat("Skipping completed checkpoint:", basename(checkpoint_path), "\n")
      next
    }

    cat(
      sprintf(
        "[%s] Running batch %s of %d (%d tasks)\n",
        format(Sys.time(), "%H:%M:%S"),
        names(batches)[b],
        length(batches),
        length(batches[[b]])
      )
    )

    if (is.null(cl)) {
      rows <- lapply(
        batches[[b]],
        function(task) safe_evaluate_task(task, run_label)
      )
    } else {
      rows <- parallel::parLapply(
        cl,
        batches[[b]],
        function(task, label) safe_evaluate_task(task, label),
        label = run_label
      )
    }

    batch_results <- do.call(rbind, rows)
    saveRDS(batch_results, checkpoint_path, compress = TRUE)
  }

  checkpoint_files <- sort(list.files(checkpoint_dir, pattern = "\\.rds$", full.names = TRUE))
  results <- do.call(rbind, lapply(checkpoint_files, readRDS))
  row.names(results) <- NULL
  results <- results[order(results$scenario, results$replication, results$method), ]

  summary <- make_summary(results)
  qa <- run_quality_checks(results, repetitions, summary)

  utils::write.csv(results, file.path(run_dir, "replication_results.csv"), row.names = FALSE)
  saveRDS(results, file.path(run_dir, "replication_results.rds"), compress = "xz")
  utils::write.csv(summary, file.path(run_dir, "scenario_method_summary.csv"), row.names = FALSE)
  utils::write.csv(qa, file.path(run_dir, "qa_report.csv"), row.names = FALSE)

  failure_rows <- results[results$status != "ok", c(
    "scenario", "replication", "method", "status", "message"
  )]
  utils::write.csv(failure_rows, file.path(run_dir, "model_failures.csv"), row.names = FALSE)

  make_figures(summary, figure_dir)

  elapsed <- proc.time()[["elapsed"]] - run_started
  metadata$completed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  metadata$elapsed_seconds <- elapsed
  metadata$qa_passed <- all(qa$passed)
  metadata$maximum_failure_rate <- max(summary$failure_rate)
  utils::write.csv(metadata, file.path(run_dir, "run_metadata.csv"), row.names = FALSE)

  list(
    results = results,
    summary = summary,
    qa = qa,
    metadata = metadata
  )
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  mode <- if (length(args) >= 1) tolower(args[1]) else "all"
  cores <- if (length(args) >= 2) as.integer(args[2]) else {
    max(1L, min(4L, parallel::detectCores() - 1L))
  }
  if (!is.finite(cores) || cores < 1) stop("cores must be a positive integer.")

  if (!mode %in% c("pilot", "final", "all")) {
    stop("Mode must be one of: pilot, final, all.")
  }

  if (mode %in% c("pilot", "all")) {
    cat("Starting 50-replication pilot.\n")
    pilot <- run_simulation(
      run_label = "pilot_50",
      repetitions = 50L,
      cores = cores,
      batch_size = 10L,
      base_seed = 20270000L
    )
    print(pilot$qa)
    if (!all(pilot$qa$passed)) {
      stop("Pilot QA failed. Final 500-replication run was not started.")
    }
    cat("Pilot QA passed.\n")
  }

  if (mode %in% c("final", "all")) {
    cat("Starting 500-replication final run.\n")
    final <- run_simulation(
      run_label = "final_500",
      repetitions = 500L,
      cores = cores,
      batch_size = 10L,
      base_seed = 20370000L
    )
    print(final$qa)
    if (!all(final$qa$passed)) {
      stop("Final run completed, but one or more QA checks failed.")
    }
    cat("Final QA passed.\n")
  }

  cat("Monte Carlo workflow complete. Outputs:", OUTPUT_ROOT, "\n")
}

if (sys.nframe() == 0L) main()
