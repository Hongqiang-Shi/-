# ============================================================
# Panel-data simulation for forecasting-based bias correction
# Implements:
#   Y_it(0) = alpha_i + gamma_t + theta_i f(t) + epsilon_it
#   D_i ~ Bernoulli(p_i)
#   p_i = exp(delta_0 + delta_1 theta_i) /
#         [1 + exp(delta_0 + delta_1 theta_i)]
#   D_it = D_i * 1(t > T0)
#   Y_it = Y_it(0) + ATT * D_it
#
# The script uses base R only. Running it creates:
#   1) one CSV per scenario;
#   2) one combined CSV;
#   3) a scenario-definition CSV;
#   4) an RDS file containing data and scenario metadata.
# ============================================================

# -------------------------
# 1. User settings
# -------------------------

SEED <- 20260810
OUTPUT_DIR <- "simulation_output"

# Balanced panel dimensions
N_UNITS <- 200
N_PERIODS <- 20
N_PRE_PERIODS <- 12       # treatment begins at t = 13
TRUE_ATT <- 2

# Set TRUE only if you also want repeated Monte Carlo datasets.
# The ordinary one-dataset-per-scenario output is always produced.
RUN_MONTE_CARLO <- FALSE
N_REPLICATIONS <- 100


# -------------------------
# 2. Helper functions
# -------------------------

inverse_logit <- function(x) {
  # plogis() is numerically more stable than exp(x)/(1 + exp(x)).
  plogis(x)
}

trend_function <- function(time, trend_type) {
  if (trend_type == "linear") {
    return(time)
  }

  if (trend_type == "quadratic") {
    return(time^2)
  }

  stop("trend_type must be either 'linear' or 'quadratic'.")
}

safe_file_name <- function(x) {
  gsub("[^A-Za-z0-9_-]", "_", x)
}


# -------------------------
# 3. Main data generator
# -------------------------

generate_panel_data <- function(
    N = 200,
    T_periods = 20,
    T0 = 12,
    ATT = 2,
    trend_type = "linear",
    theta_mean = 0,
    theta_sd = 0.05,
    delta0 = -0.40,
    delta1 = 10,
    sigma_alpha = 1,
    gamma_slope = 0.10,
    sigma_epsilon = 1,
    scenario_name = "custom",
    seed = NULL) {

  if (!is.null(seed)) set.seed(seed)

  if (T0 < 1 || T0 >= T_periods) {
    stop("T0 must be at least 1 and smaller than T_periods.")
  }

  # Unit-level observed covariates. They are included in the output so that
  # later estimators can use a covariate matrix X. The outcome DGP still has
  # the exact form in the equations because their effect is absorbed by alpha_i.
  X1 <- rnorm(N, mean = 0, sd = 1)
  X2 <- rbinom(N, size = 1, prob = 0.50)
  X3 <- runif(N, min = -1, max = 1)

  # Unit fixed effect alpha_i. It is constant over time for each unit.
  alpha_unobserved <- rnorm(N, mean = 0, sd = sigma_alpha)
  alpha_i <- 0.60 * X1 - 0.40 * X2 + 0.30 * X3 + alpha_unobserved

  # Unit-specific trend loading theta_i.
  # theta_sd = 0 produces parallel trends.
  if (theta_sd == 0) {
    theta_i <- rep(theta_mean, N)
  } else {
    theta_i <- rnorm(N, mean = theta_mean, sd = theta_sd)
  }

  # Unit-level treatment assignment.
  linear_index <- delta0 + delta1 * theta_i
  p_i <- inverse_logit(linear_index)
  D_i <- rbinom(N, size = 1, prob = p_i)

  # Avoid an unusable draw containing only treated or only control units.
  if (length(unique(D_i)) < 2) {
    stop(
      "Treatment assignment produced only one group. ",
      "Change delta0/delta1 or use a larger N."
    )
  }

  # Balanced panel: unit 1 has all T periods, then unit 2, and so on.
  panel <- expand.grid(
    time = seq_len(T_periods),
    id = seq_len(N)
  )
  panel <- panel[order(panel$id, panel$time), ]
  row.names(panel) <- NULL

  # Merge unit-level quantities into the long panel.
  unit_data <- data.frame(
    id = seq_len(N),
    X1 = X1,
    X2 = X2,
    X3 = X3,
    alpha_i = alpha_i,
    theta_i = theta_i,
    p_i = p_i,
    D_i = D_i
  )
  panel <- merge(panel, unit_data, by = "id", sort = FALSE)
  panel <- panel[order(panel$id, panel$time), ]
  row.names(panel) <- NULL

  # Common time effect gamma_t and heterogeneous trend theta_i f(t).
  panel$gamma_t <- gamma_slope * panel$time
  panel$f_t <- trend_function(panel$time, trend_type)
  panel$trend_component <- panel$theta_i * panel$f_t

  # Idiosyncratic noise.
  panel$epsilon_it <- rnorm(nrow(panel), mean = 0, sd = sigma_epsilon)

  # Untreated potential outcome Y_it(0).
  panel$Y0 <- panel$alpha_i + panel$gamma_t +
    panel$trend_component + panel$epsilon_it

  # Treatment is switched on only after the pre-treatment period.
  panel$post <- as.integer(panel$time > T0)
  panel$D_it <- panel$D_i * panel$post

  # Treated potential outcome and observed outcome. The treatment effect exists
  # only after treatment becomes available, so Y1 = Y0 in the pre-period.
  panel$Y1 <- panel$Y0 + ATT * panel$post
  panel$tau_it <- ATT * panel$post
  panel$Y_obs <- panel$Y0 + ATT * panel$D_it

  # Useful relative/event time: -1 is the last pre-treatment period,
  # 0 is the first treated period.
  first_treated_period <- T0 + 1
  panel$event_time <- panel$time - first_treated_period

  # Attach scenario information to every row for easy combination.
  panel$scenario <- scenario_name
  panel$trend_type <- trend_type
  panel$true_ATT <- ATT
  panel$T0 <- T0
  panel$delta0 <- delta0
  panel$delta1 <- delta1
  panel$theta_sd_setting <- theta_sd
  panel$sigma_epsilon_setting <- sigma_epsilon

  # Put identifiers and main analysis variables first.
  first_columns <- c(
    "scenario", "id", "time", "event_time", "post", "D_i", "D_it",
    "Y_obs", "Y0", "Y1", "tau_it", "p_i", "alpha_i", "theta_i",
    "gamma_t", "f_t", "trend_component", "epsilon_it", "X1", "X2", "X3"
  )
  panel <- panel[, c(first_columns, setdiff(names(panel), first_columns))]

  return(panel)
}


# -------------------------
# 4. Scenario definitions
# -------------------------

# Interpretation:
# - theta_sd controls cross-unit trend heterogeneity.
# - delta1 controls how strongly theta_i predicts treatment assignment.
# - sigma_epsilon controls stochastic noise.
# - quadratic scenarios use a smaller theta_sd because t^2 grows much faster.
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
  description = c(
    "No unit-specific trend heterogeneity; parallel trends",
    "Linear trend with weak heterogeneity and selection",
    "Linear trend with moderate heterogeneity and selection",
    "Linear trend with strong heterogeneity and selection",
    "Quadratic trend with moderate heterogeneity and selection",
    "Quadratic trend with strong heterogeneity and selection",
    "Moderate linear heterogeneity with high stochastic noise"
  ),
  stringsAsFactors = FALSE
)


# -------------------------
# 5. Generate and export one dataset per scenario
# -------------------------

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

scenario_data <- vector("list", nrow(scenario_grid))
names(scenario_data) <- scenario_grid$scenario

for (s in seq_len(nrow(scenario_grid))) {
  cfg <- scenario_grid[s, ]

  dat <- generate_panel_data(
    N = N_UNITS,
    T_periods = N_PERIODS,
    T0 = N_PRE_PERIODS,
    ATT = TRUE_ATT,
    trend_type = cfg$trend_type,
    theta_mean = cfg$theta_mean,
    theta_sd = cfg$theta_sd,
    delta0 = cfg$delta0,
    delta1 = cfg$delta1,
    sigma_alpha = cfg$sigma_alpha,
    gamma_slope = cfg$gamma_slope,
    sigma_epsilon = cfg$sigma_epsilon,
    scenario_name = cfg$scenario,
    seed = SEED + s
  )

  scenario_data[[s]] <- dat

  output_file <- file.path(
    OUTPUT_DIR,
    paste0(safe_file_name(cfg$scenario), ".csv")
  )
  write.csv(dat, output_file, row.names = FALSE)
}

all_scenarios <- do.call(rbind, scenario_data)
row.names(all_scenarios) <- NULL

write.csv(
  all_scenarios,
  file.path(OUTPUT_DIR, "all_scenarios_combined.csv"),
  row.names = FALSE
)

write.csv(
  scenario_grid,
  file.path(OUTPUT_DIR, "scenario_definitions.csv"),
  row.names = FALSE
)

saveRDS(
  list(
    data = scenario_data,
    scenario_definitions = scenario_grid,
    global_settings = list(
      seed = SEED,
      N = N_UNITS,
      T = N_PERIODS,
      T0 = N_PRE_PERIODS,
      ATT = TRUE_ATT
    )
  ),
  file.path(OUTPUT_DIR, "panel_simulation_bundle.rds")
)


# -------------------------
# 6. Diagnostics and validity checks
# -------------------------

scenario_summary <- do.call(
  rbind,
  lapply(scenario_data, function(dat) {
    unit_rows <- dat$time == 1
    treated <- dat$D_i == 1
    control <- dat$D_i == 0

    data.frame(
      scenario = dat$scenario[1],
      rows = nrow(dat),
      units = length(unique(dat$id)),
      periods = length(unique(dat$time)),
      treated_share = mean(dat$D_i[unit_rows]),
      mean_theta_treated = mean(dat$theta_i[unit_rows & treated]),
      mean_theta_control = mean(dat$theta_i[unit_rows & control]),
      theta_gap = mean(dat$theta_i[unit_rows & treated]) -
        mean(dat$theta_i[unit_rows & control]),
      outcome_sd = sd(dat$Y_obs)
    )
  })
)
row.names(scenario_summary) <- NULL

write.csv(
  scenario_summary,
  file.path(OUTPUT_DIR, "scenario_summary.csv"),
  row.names = FALSE
)

# Core checks for the first generated dataset.
example_data <- scenario_data[[1]]
stopifnot(nrow(example_data) == N_UNITS * N_PERIODS)
stopifnot(all(table(example_data$id) == N_PERIODS))
stopifnot(all(example_data$D_it[example_data$post == 0] == 0))
stopifnot(all(
  abs(example_data$Y_obs -
        (example_data$Y0 + TRUE_ATT * example_data$D_it)) < 1e-10
))


# -------------------------
# 7. Optional Monte Carlo generator
# -------------------------

generate_monte_carlo <- function(scenario_grid, R = 100, base_seed = 50000) {
  output <- vector("list", nrow(scenario_grid) * R)
  counter <- 1L

  for (s in seq_len(nrow(scenario_grid))) {
    cfg <- scenario_grid[s, ]

    for (r in seq_len(R)) {
      dat <- generate_panel_data(
        N = N_UNITS,
        T_periods = N_PERIODS,
        T0 = N_PRE_PERIODS,
        ATT = TRUE_ATT,
        trend_type = cfg$trend_type,
        theta_mean = cfg$theta_mean,
        theta_sd = cfg$theta_sd,
        delta0 = cfg$delta0,
        delta1 = cfg$delta1,
        sigma_alpha = cfg$sigma_alpha,
        gamma_slope = cfg$gamma_slope,
        sigma_epsilon = cfg$sigma_epsilon,
        scenario_name = cfg$scenario,
        seed = base_seed + 10000L * s + r
      )

      dat$replication <- r
      output[[counter]] <- dat
      counter <- counter + 1L
    }
  }

  do.call(rbind, output)
}

if (RUN_MONTE_CARLO) {
  monte_carlo_data <- generate_monte_carlo(
    scenario_grid = scenario_grid,
    R = N_REPLICATIONS,
    base_seed = SEED + 100000
  )

  # RDS is used because repeated long-panel CSV files become unnecessarily large.
  saveRDS(
    monte_carlo_data,
    file.path(OUTPUT_DIR, "monte_carlo_all_scenarios.rds"),
    compress = "xz"
  )
}


# -------------------------
# 8. Console output
# -------------------------

cat("Simulation completed.\n")
cat("Output directory:", normalizePath(OUTPUT_DIR), "\n\n")
print(scenario_summary, row.names = FALSE)

# Example usage after running this script:
#   moderate <- read.csv(
#     file.path(OUTPUT_DIR, "S2_linear_moderate.csv")
#   )
#   head(moderate)
#   table(moderate$D_i[moderate$time == 1])
#   X <- as.matrix(moderate[, c("X1", "X2", "X3")])
