"""AIS-stratified cluster bootstrap, including complete placebo re-selection.

The selection-aware stage refits all five methods in every 84/13-day
pre-strike placebo window for each resampled panel, then refits the winner
in the actual strike window. It is intentionally computationally expensive.
"""
from __future__ import annotations

import argparse
import json
import os
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np
import pandas as pd

from estimate import (
    METHODS, OUTCOMES, PAPER5, ROOT, SEED, STRIKE,
    fit_window, load_data, placebo_origins,
)

DATA = None


def initialize() -> None:
    global DATA
    DATA = load_data()


def draws(reps: int, seed: int) -> list[np.ndarray]:
    data = load_data()
    rng = np.random.default_rng(seed)
    treated = np.array([i for i, a in enumerate(data.ais) if a in PAPER5])
    controls = np.array([i for i, a in enumerate(data.ais) if a not in PAPER5])
    result = []
    for _ in range(reps):
        sample = np.r_[rng.choice(treated, len(treated), replace=True), rng.choice(controls, len(controls), replace=True)]
        result.append(np.bincount(sample, minlength=len(data.ais)).astype(float))
    return result


def fixed_worker(job: tuple[int, np.ndarray]) -> list[dict[str, object]]:
    b, multiplicity = job
    strike_i = int(DATA.dates.get_loc(STRIKE))
    out = []
    for oi in range(len(OUTCOMES)):
        results = fit_window(DATA, PAPER5, oi, strike_i, ais_multiplicity=multiplicity)
        for r in results:
            out.append({"draw": b, "outcome": r["outcome"], "method": r["method"],
                        "twfe": r["twfe"], "bias_term": r["bias_term"], "adjusted_estimate": r["adjusted_estimate"], "status": r["status"]})
    return out


def selection_worker(job: tuple[int, np.ndarray]) -> dict[str, object]:
    b, multiplicity = job
    sq = {m: [] for m in METHODS}
    for index in placebo_origins(DATA):
        estimates = fit_window(DATA, PAPER5, 0, index, ais_multiplicity=multiplicity)
        for r in estimates:
            sq[r["method"]].append(float(r["adjusted_estimate"])**2)
    rmse = {m: float(np.sqrt(np.mean(sq[m]))) for m in METHODS}
    winner = min(METHODS, key=lambda m: (rmse[m], METHODS.index(m)))
    strike_i = int(DATA.dates.get_loc(STRIKE))
    result = fit_window(DATA, PAPER5, 0, strike_i, methods=(winner,), ais_multiplicity=multiplicity)[0]
    return {"draw": b, "selected_method": winner, "selected_rmse": rmse[winner],
            "adjusted_estimate": result["adjusted_estimate"], "twfe": result["twfe"],
            "bias_term": result["bias_term"], **{f"rmse_{m}": v for m, v in rmse.items()}}


def execute(kind: str, reps: int, workers: int) -> None:
    jobs = list(enumerate(draws(reps, SEED + (1000 if kind == "selection" else 0)), start=1))
    task = fixed_worker if kind == "fixed" else selection_worker
    rows: list[dict[str, object]] = []
    started = time.monotonic()
    failures = []
    with ProcessPoolExecutor(max_workers=workers, initializer=initialize) as pool:
        future_map = {pool.submit(task, job): job[0] for job in jobs}
        for future in as_completed(future_map):
            b = future_map[future]
            try:
                result = future.result()
                rows.extend(result if isinstance(result, list) else [result])
            except Exception as e:
                failures.append({"draw": b, "error": repr(e)})
            if (len(rows)//(35 if kind == "fixed" else 1) + len(failures)) % 10 == 0:
                print(f"{kind} draws completed={len(rows)//(35 if kind == 'fixed' else 1)}, failed={len(failures)}, elapsed={time.monotonic()-started:.1f}s", flush=True)
    output = ROOT / "results" / ("bootstrap_fixed_draws.csv.gz" if kind == "fixed" else "bootstrap_selection_aware_total.csv")
    frame = pd.DataFrame(rows).sort_values(["draw", "outcome", "method"] if kind == "fixed" else ["draw"])
    frame.to_csv(output, index=False, compression="gzip" if kind == "fixed" else None)
    (ROOT / "validation" / f"bootstrap_{kind}_failures.json").write_text(json.dumps(failures, indent=2), encoding="utf-8")
    if failures:
        raise RuntimeError(f"{len(failures)} {kind} bootstrap draws failed")
    if kind == "fixed":
        summary = []
        for (outcome, method), block in frame.groupby(["outcome", "method"]):
            x = block.adjusted_estimate.to_numpy(float)
            summary.append({"outcome": outcome, "method": method, "draws": len(x), "se": float(x.std(ddof=1)),
                            "ci025": float(np.quantile(x, .025)), "ci975": float(np.quantile(x, .975)),
                            "two_sided_sign_p": float(min(1, 2*min(np.mean(x<=0), np.mean(x>=0))))})
        pd.DataFrame(summary).to_csv(ROOT / "results" / "bootstrap_fixed_summary.csv", index=False)
    else:
        x = frame.adjusted_estimate.to_numpy(float)
        report = {"draws": len(x), "se": float(x.std(ddof=1)), "ci025": float(np.quantile(x,.025)),
                  "ci975": float(np.quantile(x,.975)), "selection_counts": frame.selected_method.value_counts().to_dict()}
        (ROOT / "results" / "bootstrap_selection_aware_total_summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["fixed", "selection"])
    parser.add_argument("--reps", type=int, default=499)
    parser.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 2))
    args = parser.parse_args()
    execute(args.kind, args.reps, args.workers)


if __name__ == "__main__":
    main()
