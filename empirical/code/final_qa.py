"""Final numerical and PDF text checks; visual page inspection remains manual."""
from pathlib import Path
import json
import numpy as np
import pandas as pd
from pypdf import PdfReader

root = Path(__file__).resolve().parents[1]
project = root.parent / "outputs" / "vscode_thesis_project"
flow = json.loads((root/"validation"/"sample_flow.json").read_text(encoding="utf-8"))
checks = json.loads((root/"validation"/"output_checks.json").read_text(encoding="utf-8"))
p = pd.read_csv(root/"results"/"placebo_window_estimates.csv")
e = pd.read_csv(root/"results"/"strike_estimates.csv")
fixed = pd.read_csv(root/"results"/"bootstrap_fixed_draws.csv.gz")
sel = pd.read_csv(root/"results"/"bootstrap_selection_aware_total.csv")
pdf = PdfReader(project/"main.pdf")
pdf_text = "\n".join(page.extract_text() or "" for page in pdf.pages)
report = {
    "sample_rows_balanced":flow["balanced_rows"]==flow["units"]*flow["calendar_days"],
    "main_window_rows":flow["main_window_rows"]==358*97,
    "homicide_source_dta_match":flow["dta_disagreement_unit_days"]==0 and flow["painel_valid_homicides"]==flow["dta_total_valid_homicides"],
    "placebo_rows":len(p)==7*5*154,
    "strike_rows":len(e)==7*5,
    "fixed_bootstrap_rows":len(fixed)==499*7*5,
    "selection_aware_draws":len(sel)==99,
    "twfe_common":checks["all_methods_share_twfe_by_outcome"],
    "bias_identity":checks["all_adjusted_equal_twfe_minus_bias"] and checks["all_bias_equal_predicted_gap_minus_pre_gap"],
    "no_placebo_failure":checks["all_placebo_failures_zero"],
    "pdf_pages":len(pdf.pages),
    "pdf_contains_empirical": "Empirical Study" in pdf_text,
    "pdf_contains_discussion": "Discussion" in pdf_text,
    "pdf_contains_conclusion": "Conclusion" in pdf_text,
    "pdf_no_selection_placeholder": "being recomputed" not in pdf_text,
    "pdf_contains_selection_table": "Full RMSE selection" in pdf_text,
    "fixed_bootstrap_failure_count":len(json.loads((root/"validation"/"bootstrap_fixed_failures.json").read_text())),
    "selection_bootstrap_failure_count":len(json.loads((root/"validation"/"bootstrap_selection_failures.json").read_text())),
}
assert all(v for v in report.values() if isinstance(v,bool)), report
assert report["fixed_bootstrap_failure_count"]==0 and report["selection_bootstrap_failure_count"]==0
(root/"validation"/"final_qa.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
print(json.dumps(report,indent=2))
