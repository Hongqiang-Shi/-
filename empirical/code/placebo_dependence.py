"""Paired MSE contrasts with HAC uncertainty for overlapping training windows."""
from pathlib import Path
import numpy as np
import pandas as pd

root = Path(__file__).resolve().parents[1]
raw = pd.read_csv(root / "results" / "placebo_window_estimates.csv")
rows = []
for outcome, sub in raw.groupby("outcome"):
    wide = sub.pivot(index="test_start", columns="method", values="adjusted_estimate")
    for method in ("linear_gap", "synthetic_control", "random_forest", "gradient_boosting"):
        z = (wide[method]**2 - wide.twfe**2).dropna().to_numpy(float)
        n = len(z)
        q = z - z.mean()
        lag = 6
        lr = np.dot(q,q) / n
        for k in range(1, lag+1):
            lr += 2 * (1-k/(lag+1)) * np.dot(q[k:],q[:-k]) / n
        se = np.sqrt(max(0,lr/n))
        rows.append({"outcome":outcome,"method":method,"paired_windows":n,
                     "mean_mse_difference_vs_twfe":float(z.mean()),
                     "hac_bartlett_lag":lag,"hac_se":float(se),
                     "approx_95_low":float(z.mean()-1.96*se),
                     "approx_95_high":float(z.mean()+1.96*se)})
pd.DataFrame(rows).to_csv(root / "results" / "paired_placebo_hac.csv", index=False)
