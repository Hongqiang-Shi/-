"""Replicate Mancha's released Ceará regression as an external benchmark.

Uses the Stata-generated .dta solely to replicate the paper's own specification.
No coefficient produced here enters the TWFE gap correction.
"""
from __future__ import annotations

from pathlib import Path
import numpy as np
import pandas as pd

ROOT = Path(r"C:\Users\hishi\Documents\Codex\2026-09-13\xia\empirical_rebuild")
DATA = Path(r"C:\Users\hishi\Desktop\Paper\When-the-State-Steps-Down-main\Bases\Daily_Homicides_CE.dta")
OUTCOMES = {
    "total": "daily_homicides", "men": "daily_homicides_men", "women": "daily_homicides_women",
    "crime_1": "crime_1", "crime_2": "crime_2", "crime_3": "crime_3", "crime_4": "crime_4",
}
PUBLISHED = dict(zip(OUTCOMES, [0.335, 0.267, 0.069, 0.297, 0.267, 0.180, 0.159]))


def codes(values: pd.Series) -> np.ndarray:
    return pd.factorize(values, sort=True)[0].astype(np.int64)


def residualize(z: np.ndarray, groups: list[np.ndarray], tol: float = 1e-11) -> tuple[np.ndarray, int]:
    out = z.astype(float).copy()
    prev = out.copy()
    scale = max(1.0, float(np.abs(out).max()))
    for it in range(1, 5001):
        for g in groups:
            n = int(g.max()) + 1
            count = np.bincount(g, minlength=n)
            for k in range(out.shape[1]):
                sums = np.bincount(g, weights=out[:, k], minlength=n)
                out[:, k] -= (sums / count)[g]
        if np.abs(out-prev).max() < tol*scale:
            return out, it
        prev[:] = out
    raise RuntimeError("HDFE projections did not converge")


def main() -> None:
    raw = pd.read_stata(DATA, convert_categoricals=False)
    raw = raw.loc[raw.id_ais.notna()].copy()
    raw = raw.sort_values(["id_code2", "DATE"]).drop_duplicates(["id_code2", "DATE"], keep="first")
    raw["year"] = raw.year.fillna(pd.to_datetime(raw.DATE).dt.year)
    raw["month"] = raw.month.fillna(pd.to_datetime(raw.DATE).dt.month)
    raw["weekday"] = raw.weekday.fillna((pd.to_datetime(raw.DATE).dt.dayofweek+1)%7)
    raw["ais_year"] = raw.id_ais.astype(int).astype(str) + "_" + raw.year.astype(int).astype(str)
    fe_cols = ["id_code2", "ais_year", "month", "weekday"]
    for col in fe_cols:
        while True:
            keep = raw.groupby(col)[col].transform("size") > 1
            if keep.all():
                break
            raw = raw.loc[keep].copy()
    four = {"ais 02", "ais 06", "ais 11", "ais 12"}
    five = four | {"ais 13"}
    rows = []
    groups = [codes(raw[c]) for c in fe_cols]
    for name, treated in [("released_code_four", four), ("paper_intended_five", five)]:
        tr = raw.AIS.isin(treated).astype(float).to_numpy()
        x = np.column_stack([raw.militar.to_numpy(float), raw.militar.to_numpy(float)*tr])
        z = np.column_stack([raw[list(OUTCOMES.values())].to_numpy(float), x])
        rz, iterations = residualize(z, groups)
        xres = rz[:, -2:]
        beta, *_ = np.linalg.lstsq(xres, rz[:, :len(OUTCOMES)], rcond=None)
        for j, outcome in enumerate(OUTCOMES):
            rows.append({"treatment_definition": name, "outcome": outcome, "published_interaction": PUBLISHED[outcome],
                         "reproduced_interaction": float(beta[1,j]), "n_source_unit_days": len(raw),
                         "n_ais": int(raw.id_ais.nunique()), "hdfe_iterations": iterations})
    result = pd.DataFrame(rows)
    result.to_csv(ROOT / "results" / "mancha_external_replication.csv", index=False)
    four_result = result[(result.treatment_definition == "released_code_four") & (result.outcome == "total")].iloc[0]
    assert abs(four_result.reproduced_interaction-0.335) < 0.001
    print(result.to_string(index=False))


if __name__ == "__main__":
    main()
