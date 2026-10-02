"""Insert completed selection-aware inference into the manuscript."""
from pathlib import Path
import json
import pandas as pd

root = Path(__file__).resolve().parents[1]
project = root.parent / "outputs" / "vscode_thesis_project"
report = json.loads((root / "results" / "bootstrap_selection_aware_total_summary.json").read_text(encoding="utf-8"))
fixed = pd.read_csv(root / "results" / "bootstrap_fixed_summary.csv")
f = fixed[(fixed.outcome=="total") & (fixed.method=="random_forest")].iloc[0]
e = pd.read_csv(root / "results" / "strike_estimates.csv")
original = e[(e.outcome=="total") & (e.method=="random_forest")].iloc[0]
names = {"twfe":"no correction", "linear_gap":"linear gap", "synthetic_control":"Synthetic Control", "random_forest":"Random Forest", "gradient_boosting":"Gradient Boosting"}
counts = ", ".join(f"{names[m]} {report['selection_counts'].get(m,0)}" for m in names)
interpretation = ("Selection changes across draws, showing that the small placebo-RMSE advantage is sensitive to AIS composition."
                  if sum(int(v)>0 for v in report['selection_counts'].values())>1
                  else "The same method was selected in every draw, although this does not validate the missing strike-period counterfactual.")
tex = rf"""\begin{{table}}[htbp]
\centering\small
\caption{{Fixed-method versus full selection-aware AIS bootstrap for total homicides. Both rows share the original-sample point estimate; percentile intervals differ in whether selection is repeated.}}
\label{{tab:selectionrebuild}}
\begin{{tabular}}{{lrrrl}}
\toprule
Procedure & Draws & Estimate & 95\% interval & Re-selection\\
\midrule
Random Forest fixed & {int(f.draws)} & {original.adjusted_estimate:.4f} & [{f.ci025:.4f}, {f.ci975:.4f}] & No\\
Full RMSE selection & {report['draws']} & {original.adjusted_estimate:.4f} & [{report['ci025']:.4f}, {report['ci975']:.4f}] & Yes\\
\bottomrule
\end{{tabular}}
\end{{table}}

Across {report['draws']} selection-aware resamples, the pre-strike RMSE rule chose {counts}. The observed-sample winner was Random Forest. {interpretation} Neither interval is a randomization-based causal interval.
"""
(project / "tables" / "empirical_selection_rebuild.tex").write_text(tex, encoding="utf-8")
print(tex)
