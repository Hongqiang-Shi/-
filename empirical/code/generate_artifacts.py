"""Build manuscript tables and figures from frozen CSV results, never fit models."""
from pathlib import Path
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent / "outputs" / "vscode_thesis_project"
TABLES = PROJECT / "tables"
FIGURES = PROJECT / "figures"
METHODS = ["twfe", "linear_gap", "synthetic_control", "random_forest", "gradient_boosting"]
LABELS = {"twfe": "No correction", "linear_gap": "Linear gap", "synthetic_control": "SC--entropy", "random_forest": "RF--empirical", "gradient_boosting": "GB--empirical"}
OUTCOMES = ["total", "men", "women", "crime_1", "crime_2", "crime_3", "crime_4"]
OLABEL = {"total": "Total", "men": "Men", "women": "Women", **{f"crime_{i}":f"Crime {i}" for i in range(1,5)}}

def fmt(x, d=4):
    return f"{float(x):.{d}f}"

def save(name, text):
    (TABLES / name).write_text(text + "\n", encoding="utf-8")

def main():
    TABLES.mkdir(exist_ok=True)
    FIGURES.mkdir(exist_ok=True)
    p = pd.read_csv(ROOT / "results" / "placebo_performance.csv")
    e = pd.read_csv(ROOT / "results" / "strike_estimates.csv")
    m = pd.read_csv(ROOT / "results" / "mancha_external_replication.csv")
    s = pd.read_csv(ROOT / "results" / "sensitivity_total.csv")
    ci_file = ROOT / "results" / "bootstrap_fixed_summary.csv"
    ci = pd.read_csv(ci_file) if ci_file.exists() else None
    if ci is not None:
        e = e.merge(ci[["outcome", "method", "ci025", "ci975", "se"]], on=["outcome", "method"], validate="one_to_one")

    lines = [r"\begin{table}[htbp]",r"\centering\small",r"\caption{Total-homicide rolling pre-strike placebo performance (154 windows, 84-day training and 13-day test). The pseudo-effect is zero; variance is the population variance of placebo estimates. SC--entropy uses an entropy tie-break; RF--empirical and GB--empirical use forecast-known calendar and group features.}",r"\label{tab:placeborebuild}",r"\begin{tabular}{lrrrrrr}",r"\toprule",r"Method & Signed error & Variance & MAE & RMSE & Windows & Failures\\",r"\midrule"]
    for method in METHODS:
        r = p[(p.outcome=="total")&(p.method==method)].iloc[0]
        lines.append(f"{LABELS[method]} & {fmt(r.signed_bias,5)} & {fmt(r.variance,6)} & {fmt(r.mae,5)} & {fmt(r.rmse,5)} & {int(r.windows_available)} & {int(r.failures)}\\\\")
    lines += [r"\bottomrule",r"\end{tabular}",r"\end{table}"]
    save("empirical_placebo_rebuild.tex", "\n".join(lines))

    lines=[r"\begin{longtable}{llrrrrrr}",r"\caption{All-outcome pre-strike placebo performance (same 154 windows and models in each row).}\label{tab:allplaceborebuild}\\",r"\toprule",r"Outcome & Method & Signed error & Variance & MAE & RMSE & Windows & Failures\\",r"\midrule",r"\endfirsthead",r"\toprule",r"Outcome & Method & Signed error & Variance & MAE & RMSE & Windows & Failures\\",r"\midrule",r"\endhead"]
    for outcome in OUTCOMES:
        for method in METHODS:
            r=p[(p.outcome==outcome)&(p.method==method)].iloc[0]
            lines.append(f"{OLABEL[outcome]} & {LABELS[method]} & {fmt(r.signed_bias,5)} & {fmt(r.variance,6)} & {fmt(r.mae,5)} & {fmt(r.rmse,5)} & {int(r.windows_available)} & {int(r.failures)}\\\\")
        lines.append(r"\midrule" if outcome!=OUTCOMES[-1] else r"\bottomrule")
    lines.append(r"\end{longtable}")
    save("empirical_placebo_all_rebuild.tex", "\n".join(lines))

    lines=[r"\begin{longtable}{llrrrrl}",r"\caption{Strike-period TWFE, predicted bias and correction on the common unit/date panel. Percentile intervals resample AIS within treatment arms; * marks the pre-strike RMSE winner.}\label{tab:estimatesrebuild}\\",r"\toprule",r"Outcome & Method & TWFE & Bias $\widehat B_m$ & Adjusted & 95\% interval & Selected\\",r"\midrule",r"\endfirsthead",r"\toprule",r"Outcome & Method & TWFE & Bias & Adjusted & 95\% interval & Selected\\",r"\midrule",r"\endhead"]
    for outcome in OUTCOMES:
        for method in METHODS:
            r=e[(e.outcome==outcome)&(e.method==method)].iloc[0]
            interval=f"[{fmt(r.ci025,3)}, {fmt(r.ci975,3)}]" if ci is not None else "pending"
            lines.append(f"{OLABEL[outcome]} & {LABELS[method]} & {fmt(r.twfe,4)} & {fmt(r.bias_term,4)} & {fmt(r.adjusted_estimate,4)} & {interval} & {'*' if r.selected_by_prestrike_rmse else ''}\\\\")
        lines.append(r"\midrule" if outcome!=OUTCOMES[-1] else r"\bottomrule")
    lines.append(r"\end{longtable}")
    save("empirical_estimates_rebuild.tex", "\n".join(lines))

    lines=[r"\begin{table}[htbp]",r"\centering\small",r"\caption{External replication of Mancha's interaction regression versus this thesis's distinct TWFE benchmark. Coefficients are not subtracted from one another.}",r"\label{tab:mancharebuild}",r"\begin{tabular}{lrrrr}",r"\toprule",r"Outcome & Published & Replicated four AIS & Corrected five AIS & Thesis TWFE\\",r"\midrule"]
    for outcome in OUTCOMES:
        a=m[(m.outcome==outcome)&(m.treatment_definition=="released_code_four")].iloc[0]
        b=m[(m.outcome==outcome)&(m.treatment_definition=="paper_intended_five")].iloc[0]
        c=e[(e.outcome==outcome)&(e.method=="twfe")].iloc[0]
        lines.append(f"{OLABEL[outcome]} & {fmt(a.published_interaction,3)} & {fmt(a.reproduced_interaction,3)} & {fmt(b.reproduced_interaction,3)} & {fmt(c.twfe,3)}\\\\")
    lines += [r"\bottomrule",r"\end{tabular}",r"\end{table}"]
    save("empirical_mancha_rebuild.tex", "\n".join(lines))

    lines=[r"\begin{longtable}{lrrrrr}",r"\caption{Total-homicide sensitivity to pre-period length, treatment definition, and aggregation. Entries are adjusted estimates, not comparable across the last unit-aggregation row in absolute scale.}\label{tab:sensitivityrebuild}\\",r"\toprule",r"Specification & TWFE & Linear & SC & RF & GB\\",r"\midrule"]
    cases=[("Five AIS, 8 weeks", "paper_five", "municipality_district",56),("Five AIS, 12 weeks", "paper_five", "municipality_district",84),("Five AIS, 26 weeks", "paper_five", "municipality_district",182),("Five AIS, 52 weeks", "paper_five", "municipality_district",364),("Five AIS, 104 weeks", "paper_five", "municipality_district",728),("Four AIS, 12 weeks", "released_code_four", "municipality_district",84),("Six AIS, 12 weeks", "numeric_p75_six", "municipality_district",84),("AIS--day, 12 weeks", "paper_five", "AIS_aggregate",84)]
    for label,definition,mode,days in cases:
        b=s[(s.definition==definition)&(s.unit_mode==mode)&(s.pre_days==days)].set_index("method")
        lines.append(label+" & "+" & ".join(fmt(b.loc[k,"adjusted_estimate"],3) for k in METHODS)+r"\\")
    lines += [r"\bottomrule",r"\end{longtable}"]
    save("empirical_sensitivity_rebuild.tex", "\n".join(lines))

    # All 35 entries are in the table; the heatmap makes close placebo rankings legible.
    mat=np.array([[p[(p.outcome==o)&(p.method==m)].iloc[0].rmse / p[(p.outcome==o)&(p.method=="twfe")].iloc[0].rmse -1 for m in METHODS] for o in OUTCOMES])*100
    fig, ax=plt.subplots(figsize=(9,4.5))
    im=ax.imshow(mat,aspect="auto",cmap="RdBu_r",vmin=-20,vmax=20)
    ax.set_xticks(range(5),[LABELS[m] for m in METHODS],rotation=25,ha="right")
    ax.set_yticks(range(7),[OLABEL[o] for o in OUTCOMES])
    for i in range(7):
        for j in range(5): ax.text(j,i,f"{mat[i,j]:+.1f}%",ha="center",va="center",fontsize=8)
    fig.colorbar(im,ax=ax,label="RMSE relative to no correction (%)")
    fig.tight_layout(); fig.savefig(FIGURES/"empirical_rmse_rebuild.pdf"); fig.savefig(ROOT/"figures"/"empirical_rmse_rebuild.pdf"); fig.savefig(ROOT/"figures"/"empirical_rmse_rebuild.png",dpi=180); plt.close(fig)

    total=e[e.outcome=="total"].set_index("method").loc[METHODS]
    fig,ax=plt.subplots(figsize=(7.5,3.4))
    x=np.arange(5)
    y=total.adjusted_estimate.to_numpy(float)
    if ci is not None:
        low=total.ci025.to_numpy(float); high=total.ci975.to_numpy(float)
        ax.errorbar(x,y,yerr=np.vstack([y-low,high-y]),fmt="o",capsize=4,color="#163a5f")
    else: ax.plot(x,y,"o",color="#163a5f")
    ax.axhline(0,color="0.5",lw=1)
    ax.set_xticks(x,[LABELS[m] for m in METHODS],rotation=20,ha="right")
    ax.set_ylabel("Homicides per unit-day")
    ax.set_title("Common TWFE benchmark with method-specific gap correction")
    fig.tight_layout();fig.savefig(FIGURES/"empirical_total_estimates_rebuild.pdf");fig.savefig(ROOT/"figures"/"empirical_total_estimates_rebuild.pdf");fig.savefig(ROOT/"figures"/"empirical_total_estimates_rebuild.png",dpi=180);plt.close(fig)

    fig,ax=plt.subplots(figsize=(7,3.3))
    pg=total.iloc[0].pre_gap; og=total.iloc[0].observed_test_gap
    ax.axvline(pg,color="0.5",ls="--",label="Observed pre gap")
    ax.axvline(og,color="black",ls=":",label="Observed strike gap (not fitted)")
    ax.scatter(total.predicted_untreated_test_gap.to_numpy(float),np.arange(5),color="#ad4c31",zorder=3)
    ax.set_yticks(np.arange(5),[LABELS[m] for m in METHODS]);ax.invert_yaxis()
    ax.set_xlabel("Treated-minus-control total homicides per unit-day")
    ax.legend(fontsize=8,loc="lower right")
    fig.tight_layout();fig.savefig(FIGURES/"empirical_counterfactual_gap_rebuild.pdf");fig.savefig(ROOT/"figures"/"empirical_counterfactual_gap_rebuild.pdf");fig.savefig(ROOT/"figures"/"empirical_counterfactual_gap_rebuild.png",dpi=180);plt.close(fig)

    # Checks generated from outputs, including an exact common benchmark per outcome.
    checks={"all_placebo_candidates_have_154_windows":bool((p.windows_available==154).all()),"all_placebo_failures_zero":bool((p.failures==0).all()),"all_methods_share_twfe_by_outcome":bool(all(e[e.outcome==o].twfe.max()-e[e.outcome==o].twfe.min()<1e-12 for o in OUTCOMES)),"all_adjusted_equal_twfe_minus_bias":bool(np.allclose(e.adjusted_estimate,e.twfe-e.bias_term,atol=1e-12)),"all_bias_equal_predicted_gap_minus_pre_gap":bool(np.allclose(e.bias_term,e.predicted_untreated_test_gap-e.pre_gap,atol=1e-12)),"selected_per_outcome":{o:e[(e.outcome==o)&e.selected_by_prestrike_rmse].method.iloc[0] for o in OUTCOMES}}
    (ROOT/"validation"/"output_checks.json").write_text(json.dumps(checks,indent=2),encoding="utf-8")
    assert all(v for k,v in checks.items() if isinstance(v,bool))
    print(checks)

if __name__=="__main__": main()
