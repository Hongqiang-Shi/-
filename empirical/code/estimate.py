"""Common-benchmark TWFE gap correction with pre-strike rolling placebos.

Requires numpy/pandas/scipy/scikit-learn. All methods use the same unit roster,
calendar dates, and unit-weighted treated/control means. No strike-period
treated outcome enters a counterfactual fit or the selection rule.
"""
from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.optimize import brentq
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor

ROOT = Path(r"C:\Users\hishi\Documents\Codex\2026-09-13\xia\empirical_rebuild")
OUTCOMES = ["total", "men", "women", "crime_1", "crime_2", "crime_3", "crime_4"]
METHODS = ["twfe", "linear_gap", "synthetic_control", "random_forest", "gradient_boosting"]
PAPER5 = {"ais 02", "ais 06", "ais 11", "ais 12", "ais 13"}
CODE4 = {"ais 02", "ais 06", "ais 11", "ais 12"}
P75SIX = PAPER5 | {"ais 07"}
STRIKE = pd.Timestamp("2020-02-18")
PRE_DAYS = 84
POST_DAYS = 13
PLACEBO_STEP = 14
SEED = 20260928
RF_TREES = 500
GB_TREES = 800


@dataclass
class Data:
    dates: pd.DatetimeIndex
    roster: pd.DataFrame
    unit_values: np.ndarray  # unit x day x outcome
    ais_sums: np.ndarray     # ais x day x outcome
    ais: list[str]
    ais_counts: np.ndarray
    unit_ais: np.ndarray


def load_data() -> Data:
    roster = pd.read_csv(ROOT / "data" / "unit_roster.csv")
    obs = pd.read_csv(ROOT / "data" / "observed_unit_day.csv.gz", parse_dates=["date"])
    roster = roster.sort_values("unit").reset_index(drop=True)
    dates = pd.date_range("2014-01-01", "2020-12-31", freq="D")
    ais = sorted(roster.ais.unique())
    ui = pd.Index(roster.unit).get_indexer(obs.unit)
    di = pd.Index(dates).get_indexer(obs.date)
    assert (ui >= 0).all() and (di >= 0).all()
    values = np.zeros((len(roster), len(dates), len(OUTCOMES)), dtype=np.float64)
    np.add.at(values, (ui, di), obs[OUTCOMES].to_numpy(float))
    unit_ais = pd.Index(ais).get_indexer(roster.ais)
    ais_counts = np.bincount(unit_ais, minlength=len(ais)).astype(float)
    ais_sums = np.zeros((len(ais), len(dates), len(OUTCOMES)), dtype=np.float64)
    for a in range(len(ais)):
        ais_sums[a] = values[unit_ais == a].sum(axis=0)
    assert int(values.sum(axis=(0, 1))[0]) == 27418
    return Data(dates, roster, values, ais_sums, ais, ais_counts, unit_ais)


def unit_weights(data: Data, treated: set[str], ais_multiplicity: np.ndarray | None = None, mode: str = "unit") -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    if ais_multiplicity is None:
        ais_multiplicity = np.ones(len(data.ais), dtype=float)
    t_ais = np.array([a in treated for a in data.ais])
    if mode == "ais":
        counts = np.ones(len(data.ais), dtype=float)
    else:
        counts = data.ais_counts
    mt = ais_multiplicity * t_ais
    mc = ais_multiplicity * (~t_ais)
    nt, nc = float(mt @ counts), float(mc @ counts)
    if nt <= 0 or nc <= 0:
        raise ValueError("Bootstrap draw omitted a treatment arm")
    return mt, mc, mt / nt, mc / nc


def group_series(data: Data, treated: set[str], ais_multiplicity: np.ndarray | None = None, mode: str = "unit") -> tuple[np.ndarray, np.ndarray]:
    _, _, wt, wc = unit_weights(data, treated, ais_multiplicity, mode)
    sums = data.ais_sums if mode == "unit" else data.ais_sums
    return np.einsum("a,ado->do", wt, sums), np.einsum("a,ado->do", wc, sums)


def machine_features(dates: pd.DatetimeIndex, start: int, train_days: int, end: int) -> tuple[np.ndarray, np.ndarray]:
    day = dates[start:end]
    # All four features are known for both groups when a forecast is made.
    rel = np.arange(len(day), dtype=float)
    base = np.column_stack([rel, day.dayofweek.to_numpy(float), day.month.to_numpy(float)])
    train_base = base[:train_days]
    post_base = base[train_days:]
    def stack(x: np.ndarray) -> np.ndarray:
        return np.vstack([np.column_stack([x[:, 0], np.ones(len(x)), x[:, 1:]]), np.column_stack([x[:, 0], np.zeros(len(x)), x[:, 1:]])])
    return stack(train_base), stack(post_base)


def synthetic_weights(donor_pre_mean: np.ndarray, donor_base: np.ndarray, target: float) -> tuple[np.ndarray, str]:
    """Match the sole Synth predictor; max-entropy ties resolve underidentification."""
    x = np.asarray(donor_pre_mean, float)
    base = np.asarray(donor_base, float)
    base = base / base.sum()
    lo, hi = float(x.min()), float(x.max())
    if np.ptp(x) < 1e-12:
        return base, "all_donor_means_equal"
    if target <= lo + 1e-12:
        mask = np.isclose(x, lo)
        w = base * mask
        return w / w.sum(), "below_or_at_donor_support"
    if target >= hi - 1e-12:
        mask = np.isclose(x, hi)
        w = base * mask
        return w / w.sum(), "above_or_at_donor_support"
    def weights(lam: float) -> np.ndarray:
        z = np.log(base) + lam * (x - x.mean())
        z -= z.max()
        w = np.exp(z)
        return w / w.sum()
    f = lambda lam: float(weights(lam) @ x - target)
    lower, upper = -1.0, 1.0
    while f(lower) > 0:
        lower *= 2
    while f(upper) < 0:
        upper *= 2
    w = weights(brentq(f, lower, upper, xtol=1e-12))
    return w, "exact_mean_match"


def fit_window(data: Data, treated: set[str], outcome: int, test_start: int, pre_days: int = 84, methods: tuple[str, ...] = tuple(METHODS), ais_multiplicity: np.ndarray | None = None, mode: str = "unit") -> list[dict[str, object]]:
    if pre_days % 7 or test_start < pre_days or test_start + POST_DAYS > len(data.dates):
        raise ValueError("Invalid training/test window")
    train_start = test_start - pre_days
    train = slice(train_start, test_start)
    test = slice(test_start, test_start + POST_DAYS)
    treated_series, control_series = group_series(data, treated, ais_multiplicity, mode)
    tr = treated_series[:, outcome]
    co = control_series[:, outcome]
    gaps = tr - co
    gpre = float(gaps[train].mean())
    gtest = float(gaps[test].mean())
    strike_blocks = gaps[test]
    assert np.isclose(gtest, (7 * strike_blocks[:7].mean() + 6 * strike_blocks[7:].mean()) / 13, atol=1e-14)
    twfe = gtest - gpre
    results: list[dict[str, object]] = []
    pred: dict[str, float] = {}
    status: dict[str, str] = {}
    if "twfe" in methods:
        pred["twfe"] = gpre
        status["twfe"] = "ok"
    if "linear_gap" in methods:
        weekly = gaps[train].reshape(-1, 7).mean(axis=1)
        x = np.arange(1, len(weekly) + 1, dtype=float)
        slope, intercept = np.polyfit(x, weekly, 1)
        pred["linear_gap"] = float((7 * (intercept + slope * (len(weekly) + 1)) + 6 * (intercept + slope * (len(weekly) + 2))) / 13)
        status["linear_gap"] = "ok"
    if "synthetic_control" in methods:
        _, mc, _, _ = unit_weights(data, treated, ais_multiplicity, mode)
        if mode == "ais":
            donors = data.ais_sums[:, :, outcome]
            base = mc
        else:
            donors = data.unit_values[:, :, outcome]
            base = mc[data.unit_ais]
        use = base > 0
        donor = donors[use]
        donor_pre = donor[:, train].mean(axis=1)
        target = float(tr[train].mean())
        w, sc_status = synthetic_weights(donor_pre, base[use], target)
        synthetic_post = float(w @ donor[:, test].mean(axis=1))
        pred["synthetic_control"] = synthetic_post - float(co[test].mean())
        status["synthetic_control"] = sc_status
    if "random_forest" in methods or "gradient_boosting" in methods:
        X_train, X_test = machine_features(data.dates, train_start, pre_days, test_start + POST_DAYS)
        y_train = np.concatenate([tr[train], co[train]])
        seed = int(SEED + outcome * 100000 + test_start)
        if "random_forest" in methods:
            rf = RandomForestRegressor(n_estimators=RF_TREES, max_features=2, min_samples_leaf=5, bootstrap=True, n_jobs=1, random_state=seed)
            rf.fit(X_train, y_train)
            p = rf.predict(X_test)
            pred["random_forest"] = float((p[:POST_DAYS] - p[POST_DAYS:]).mean())
            status["random_forest"] = "ok"
        if "gradient_boosting" in methods:
            gb = GradientBoostingRegressor(n_estimators=GB_TREES, max_depth=3, learning_rate=0.01, min_samples_leaf=10, subsample=0.7, random_state=seed)
            gb.fit(X_train, y_train)
            p = gb.predict(X_test)
            pred["gradient_boosting"] = float((p[:POST_DAYS] - p[POST_DAYS:]).mean())
            status["gradient_boosting"] = "ok"
    for method in methods:
        b = pred[method] - gpre
        tau = twfe - b
        assert np.isclose(tau, gtest - pred[method], atol=1e-11)
        results.append({"outcome": OUTCOMES[outcome], "method": method, "test_start": str(data.dates[test_start].date()), "pre_days": pre_days,
                        "treated_units": int((data.roster.ais.isin(treated)).sum()) if mode == "unit" else len(treated),
                        "pre_gap": gpre, "observed_test_gap": gtest, "twfe": twfe, "predicted_untreated_test_gap": pred[method],
                        "bias_term": b, "adjusted_estimate": tau, "status": status[method]})
    return results


def placebo_origins(data: Data, step: int = PLACEBO_STEP) -> list[int]:
    strike_i = int(data.dates.get_loc(STRIKE))
    return list(range(PRE_DAYS, strike_i - POST_DAYS + 1, step))


def run_placebos(data: Data) -> pd.DataFrame:
    origins = placebo_origins(data)
    rows: list[dict[str, object]] = []
    started = time.monotonic()
    for o in range(len(OUTCOMES)):
        failures = 0
        for index in origins:
            try:
                rows += fit_window(data, PAPER5, o, index)
            except Exception as e:
                failures += 1
                for method in METHODS:
                    rows.append({"outcome": OUTCOMES[o], "method": method, "test_start": str(data.dates[index].date()), "status": f"failed: {type(e).__name__}: {e}", "adjusted_estimate": np.nan})
        print(f"placebo {OUTCOMES[o]}: {len(origins)} windows, failures={failures}, elapsed={time.monotonic()-started:.1f}s", flush=True)
    df = pd.DataFrame(rows)
    df.to_csv(ROOT / "results" / "placebo_window_estimates.csv", index=False)
    summaries = []
    for (outcome, method), block in df.groupby(["outcome", "method"]):
        e = block.adjusted_estimate.dropna().to_numpy(float)
        summaries.append({"outcome": outcome, "method": method, "windows_available": len(e), "failures": len(block)-len(e),
                          "signed_bias": float(e.mean()) if len(e) else np.nan,
                          "variance": float(np.var(e)) if len(e) else np.nan,
                          "mae": float(np.abs(e).mean()) if len(e) else np.nan,
                          "rmse": float(np.sqrt(np.square(e).mean())) if len(e) else np.nan,
                          "mse": float(np.square(e).mean()) if len(e) else np.nan})
    summary = pd.DataFrame(summaries)
    summary["rank_rmse"] = summary.groupby("outcome").rmse.rank(method="min")
    summary.to_csv(ROOT / "results" / "placebo_performance.csv", index=False)
    paired = []
    for outcome, block in df.groupby("outcome"):
        w = block.pivot(index="test_start", columns="method", values="adjusted_estimate")
        for method in METHODS:
            if method == "twfe":
                continue
            pair = w[["twfe", method]].dropna()
            z = np.square(pair[method].to_numpy(float)) - np.square(pair.twfe.to_numpy(float))
            paired.append({"outcome": outcome, "method": method, "paired_windows": len(z), "mean_mse_difference_vs_twfe": float(z.mean()), "naive_mcse_overlapping_windows": float(z.std(ddof=1)/np.sqrt(len(z)))})
    pd.DataFrame(paired).to_csv(ROOT / "results" / "paired_placebo_mse.csv", index=False)
    return summary


def run_final(data: Data, performance: pd.DataFrame) -> pd.DataFrame:
    strike_i = int(data.dates.get_loc(STRIKE))
    rows = []
    for o in range(len(OUTCOMES)):
        rows += fit_window(data, PAPER5, o, strike_i)
    final = pd.DataFrame(rows)
    winners = performance.sort_values(["outcome", "rmse", "method"]).drop_duplicates("outcome")["method"]
    winner_map = dict(zip(performance.sort_values(["outcome", "rmse", "method"]).drop_duplicates("outcome").outcome, winners))
    final["selected_by_prestrike_rmse"] = [r.method == winner_map[r.outcome] for r in final.itertuples()]
    final.to_csv(ROOT / "results" / "strike_estimates.csv", index=False)
    print("Pre-strike selected methods:", winner_map, flush=True)
    return final


def run_sensitivity(data: Data) -> None:
    strike_i = int(data.dates.get_loc(STRIKE))
    rows = []
    for name, treated in [("paper_five", PAPER5), ("released_code_four", CODE4), ("numeric_p75_six", P75SIX)]:
        for days in (56, 84, 182, 364, 728):
            for result in fit_window(data, treated, 0, strike_i, pre_days=days):
                rows.append({"definition": name, "unit_mode": "municipality_district", **result})
    for result in fit_window(data, PAPER5, 0, strike_i, mode="ais"):
        rows.append({"definition": "paper_five", "unit_mode": "AIS_aggregate", **result})
    pd.DataFrame(rows).to_csv(ROOT / "results" / "sensitivity_total.csv", index=False)


def twfe_qa(data: Data) -> dict[str, object]:
    strike_i = int(data.dates.get_loc(STRIKE))
    train = slice(strike_i-PRE_DAYS, strike_i)
    test = slice(strike_i, strike_i+POST_DAYS)
    tr, co = group_series(data, PAPER5)
    gap_tau = (tr[test] - co[test]).mean(axis=0) - (tr[train] - co[train]).mean(axis=0)
    x = np.tile(np.arange(PRE_DAYS+POST_DAYS) >= PRE_DAYS, (len(data.roster), 1)).astype(float)
    x[~data.roster.ais.isin(PAPER5).to_numpy()] = 0
    # Exact two-way within transformation, independent of the gap calculation.
    rx = x - x.mean(axis=1, keepdims=True) - x.mean(axis=0, keepdims=True) + x.mean()
    ry = data.unit_values[:, strike_i-PRE_DAYS:strike_i+POST_DAYS, :]
    ry = ry - ry.mean(axis=1, keepdims=True) - ry.mean(axis=0, keepdims=True) + ry.mean(axis=(0,1),keepdims=True)
    coef = np.einsum("ut,uto->o", rx, ry) / np.square(rx).sum()
    delta = np.abs(coef - gap_tau)
    assert delta.max() < 1e-10
    return {"outcomes": OUTCOMES, "gap_did": gap_tau.tolist(), "within_twfe": coef.tolist(), "max_abs_difference": float(delta.max())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["placebo", "final", "sensitivity", "qa", "all"])
    args = parser.parse_args()
    data = load_data()
    if args.stage in {"qa", "all"}:
        info = twfe_qa(data)
        (ROOT / "validation" / "twfe_equivalence.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
        print(info, flush=True)
    if args.stage in {"placebo", "all"}:
        performance = run_placebos(data)
    else:
        performance = pd.read_csv(ROOT / "results" / "placebo_performance.csv") if args.stage == "final" else None
    if args.stage in {"final", "all"}:
        run_final(data, performance)
    if args.stage in {"sensitivity", "all"}:
        run_sensitivity(data)


if __name__ == "__main__":
    main()
