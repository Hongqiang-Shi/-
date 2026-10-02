"""Build and audit the Ceará municipality/district-day analysis panel.

Run with the bundled Python interpreter. Source workbooks are read-only.
"""
from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from pathlib import Path

import numpy as np
import pandas as pd

BASE = Path(r"C:\Users\hishi\Desktop\Paper\When-the-State-Steps-Down-main\Bases")
DOFILE = Path(r"C:\Users\hishi\Desktop\Paper\When-the-State-Steps-Down-main\Do Files\Code_Ceara.do")
PAPER = Path(r"C:\Users\hishi\Desktop\Paper\Thesis_References\reference\files\5\Mancha - 2025 - When the State steps down Reduced police surveillance and gang-related deaths in Brazil.pdf")
ROOT = Path(r"C:\Users\hishi\Documents\Codex\2026-09-13\xia\empirical_rebuild")
OUTCOMES = ["total", "men", "women", "crime_1", "crime_2", "crime_3", "crime_4"]
CITY_FIX = {
    "itapage": "itapaje",
    "juazeiro do": "juazeiro do norte",
    "lavras da mangabeira homicidio doloso": "lavras da mangabeira",
    "quixeramobim  homicidio doloso": "quixeramobim",
    "sao luis do curu  homicidio doloso": "sao luis do curu",
    "senador pompeu homicidio doloso": "senador pompeu",
    "senador pompeu  homicidio doloso": "senador pompeu",
    "senador sa": "senador pompeu",
    "tabuleiro do": "tabuleiro do norte",
}


def norm(s: object) -> str:
    if pd.isna(s):
        return ""
    text = unicodedata.normalize("NFD", str(s))
    return "".join(c for c in text if unicodedata.category(c) != "Mn").lower().strip()


def ais_code(s: object) -> str | None:
    match = re.fullmatch(r"ais\s*0*(\d+)", norm(s))
    if match and 1 <= int(match.group(1)) <= 22:
        return f"ais {int(match.group(1)):02d}"
    return None


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    for name in ("data", "results", "figures", "validation", "code", "report"):
        (ROOT / name).mkdir(parents=True, exist_ok=True)
    raw = pd.read_excel(BASE / "Painel.xlsx", sheet_name="CVLI_CE")
    turf = pd.read_excel(BASE / "Gang_Turfs.xlsx", sheet_name="Gang_Turfs")
    dta = pd.read_stata(BASE / "Daily_Homicides_CE.dta", convert_categoricals=False)
    raw["date"] = pd.to_datetime(raw["DATE"], errors="raise").dt.normalize()
    raw["ais"] = raw["AIS"].map(ais_code)
    raw["city"] = raw["CITY"].map(norm).replace(CITY_FIX)
    duplicate_rows = raw.loc[raw.duplicated(keep=False), ["AIS", "CITY", "DATE", "HOMICIDIOS", "GENDER"]].copy()
    duplicate_rows.insert(0, "source_excel_row", duplicate_rows.index + 2)
    duplicate_rows.to_csv(ROOT / "validation" / "duplicate_source_rows.csv", index=False)
    (raw.loc[raw.ais.isna(), "AIS"].fillna("[MISSING]").value_counts().rename_axis("raw_ais_label")
        .reset_index(name="victim_rows").to_csv(ROOT / "validation" / "excluded_ais_labels.csv", index=False))
    valid = raw.loc[raw.ais.notna() & raw.city.ne("")].copy()
    valid["unit"] = valid.ais + "_" + valid.city
    for col in ["HOMICIDIOS", "crime_1", "crime_2", "crime_3", "crime_4"]:
        valid[col] = pd.to_numeric(valid[col], errors="raise")
    valid["total"] = valid.HOMICIDIOS
    valid["men"] = np.where(valid.GENDER.isin(["M", "Masculino", "MASCULINO"]), valid.HOMICIDIOS, 0)
    # Mancha's Stata code defines women as total minus men, including unclassified sex.
    valid["women"] = valid.total - valid.men
    agg = valid.groupby(["ais", "unit", "date"], as_index=False)[OUTCOMES].sum()
    if agg.duplicated(["unit", "date"]).any():
        raise AssertionError("Duplicate unit/date remained after summation")
    roster = agg[["ais", "unit"]].drop_duplicates().sort_values(["ais", "unit"]).reset_index(drop=True)
    days = pd.date_range(raw.date.min(), raw.date.max(), freq="D", name="date")
    full = pd.MultiIndex.from_product([roster.unit, days], names=["unit", "date"])
    panel = agg.set_index(["unit", "date"])[OUTCOMES].reindex(full, fill_value=0).reset_index()
    panel = panel.merge(roster, on="unit", how="left", validate="many_to_one")
    panel = panel[["ais", "unit", "date"] + OUTCOMES]
    panel["observed_source_row"] = panel.set_index(["unit", "date"]).index.isin(agg.set_index(["unit", "date"]).index)
    for col in OUTCOMES:
        panel[col] = panel[col].astype(np.int16)
    panel.to_csv(ROOT / "data" / "balanced_unit_day.csv.gz", index=False, compression="gzip")
    roster.to_csv(ROOT / "data" / "unit_roster.csv", index=False)
    agg.to_csv(ROOT / "data" / "observed_unit_day.csv.gz", index=False, compression="gzip")
    turf["ais"] = turf.AIS.map(ais_code)
    turf = turf.sort_values("ExposureDistricts", ascending=False).reset_index(drop=True)
    turf["exposure_rank"] = np.arange(1, len(turf) + 1)
    p75 = float(turf.ExposureDistricts.quantile(0.75))
    turf["above_numeric_p75"] = turf.ExposureDistricts > p75
    turf["paper_five"] = turf.ais.isin({"ais 02", "ais 06", "ais 11", "ais 12", "ais 13"})
    turf.to_csv(ROOT / "data" / "gang_exposure_audit.csv", index=False)

    # The released .dta is an intermediate built from Painel.xlsx, not an independent source.
    dta["date"] = pd.to_datetime(dta.DATE).dt.normalize()
    dta["ais"] = dta.AIS.map(ais_code)
    dta["city"] = dta.CITY.map(norm)
    dta_valid = dta.loc[dta.ais.notna()].copy()
    dta_valid["unit"] = dta_valid.ais + "_" + dta_valid.city
    dta_cols = {"daily_homicides": "total", "daily_homicides_men": "men", "daily_homicides_women": "women"}
    dta_valid = dta_valid.rename(columns=dta_cols)
    dta_agg = dta_valid.groupby(["ais", "unit", "date"], as_index=False)[OUTCOMES].sum()
    compare = agg.merge(dta_agg, on=["ais", "unit", "date"], how="outer", suffixes=("_raw", "_dta"), indicator=True)
    differences = compare["_merge"].ne("both")
    for col in OUTCOMES:
        differences |= (compare[f"{col}_raw"].fillna(0) - compare[f"{col}_dta"].fillna(0)).abs() > 1e-9
    compare.loc[differences].to_csv(ROOT / "validation" / "painel_dta_disagreements.csv", index=False)
    source_paths = [BASE / "Painel.xlsx", BASE / "Gang_Turfs.xlsx", BASE / "Daily_Homicides_CE.dta", DOFILE, PAPER]
    hashes = pd.DataFrame([{"path": str(p), "bytes": p.stat().st_size, "sha256": digest(p)} for p in source_paths])
    hashes.to_csv(ROOT / "validation" / "source_hashes.csv", index=False)
    main_window = panel.loc[panel.date.between(pd.Timestamp("2019-11-26"), pd.Timestamp("2020-03-01"))]
    strike_window = panel.loc[panel.date.between(pd.Timestamp("2020-02-18"), pd.Timestamp("2020-03-01"))]
    qa = {
        "painel_rows": int(len(raw)),
        "painel_valid_ais_rows": int(len(valid)),
        "painel_excluded_rows": int(len(raw) - len(valid)),
        "painel_exact_duplicate_rows_retained": int(raw.duplicated().sum()),
        "painel_valid_homicides": int(valid.total.sum()),
        "dta_rows": int(len(dta)),
        "dta_valid_ais_rows": int(len(dta_valid)),
        "dta_duplicated_unit_days_before_reaggregation": int(dta_valid.duplicated(["unit", "date"]).sum()),
        "dta_disagreement_unit_days": int(differences.sum()),
        "dta_total_valid_homicides": int(dta_valid.total.sum()),
        "units": int(len(roster)),
        "ais": int(roster.ais.nunique()),
        "calendar_days": int(len(days)),
        "balanced_rows": int(len(panel)),
        "zero_filled_unit_days": int((~panel.observed_source_row).sum()),
        "sum_total_balanced": int(panel.total.sum()),
        "main_window_rows": int(len(main_window)),
        "main_window_zero_total_rows": int((main_window.total == 0).sum()),
        "main_window_total_homicides": int(main_window.total.sum()),
        "strike_window_rows": int(len(strike_window)),
        "strike_window_zero_total_rows": int((strike_window.total == 0).sum()),
        "strike_window_total_homicides": int(strike_window.total.sum()),
        "sex_unclassified_rows_counted_in_women_like_stata": int((~valid.GENDER.isin(["M", "Masculino", "MASCULINO", "F", "Feminino", "FEMININO"])).sum()),
        "exposure_district_p75": p75,
        "numeric_p75_set": sorted(turf.loc[turf.above_numeric_p75, "ais"].tolist()),
        "paper_five_set": sorted(turf.loc[turf.paper_five, "ais"].tolist()),
    }
    (ROOT / "validation" / "sample_flow.json").write_text(json.dumps(qa, indent=2, ensure_ascii=False), encoding="utf-8")
    assert len(roster) == 358 and roster.ais.nunique() == 22
    assert len(panel) == len(roster) * len(days)
    assert panel.total.sum() == valid.total.sum()
    assert (panel.men + panel.women == panel.total).all()
    print(json.dumps(qa, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
