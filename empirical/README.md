# Ceará empirical rebuild

This directory is a fresh, reproducible rebuild of the thesis's empirical study. It does not overwrite the earlier `xia/empirical` work. The updated manuscript source and compiled PDF live in `xia/outputs/vscode_thesis_project`; a copy of the previous `main.tex`, `abstract.tex`, and `main.pdf` is retained in `archive/thesis_before_rebuild`.
The existing simulation numerical outputs and figures were preserved; only the thesis prose linking them to the rebuilt empirical study was revised.

## Inputs and provenance

The inputs are the user's `Bases/Painel.xlsx` (victim records), `Bases/Gang_Turfs.xlsx` (gang exposure), `Bases/Daily_Homicides_CE.dta` (released intermediate aggregation), Mancha's `Do Files/Code_Ceara.do`, and Mancha's paper PDF. Exact paths and SHA-256 digests are in `validation/source_hashes.csv`. The DTA is derived from `Painel.xlsx`; matching the two is a consistency check, not independent corroboration.

`validation/sample_flow.json` documents exclusions, zero filling, duplicate handling and treatment sets. `validation/painel_dta_disagreements.csv` has a header but no data rows because re-aggregated DTA and victim records agree on every valid unit-day/outcome. The DTA contains one duplicate unit-day before re-aggregation. Seven byte-for-byte repeated source rows are retained as potentially distinct victim records, consistent with summing all original rows. The residual `women = total - men` follows the released code, so 24 victims of unclassified sex are counted there; this label should not be interpreted literally for those records.

`validation/duplicate_source_rows.csv` lists the original spreadsheet row numbers of repeated records without victim names; `validation/excluded_ais_labels.csv` accounts for non-geographic AIS labels and missing AIS values.

## Estimand and fixed protocol

Main treatment: AIS 02, 06, 11, 12, 13. Main unit: municipality/district-day; all 358 units are balanced from 2014-01-01 to 2020-12-31. Main window: 84 days before 2020-02-18 and 13 strike days through 2020-03-01. The TWFE with unit and date effects equals the post-minus-pre gap DID to machine precision (`validation/twfe_equivalence.json`). Within an arm, units have equal weight. All five candidates use that same TWFE and pre-gap. Bias is predicted untreated post gap minus observed pre gap, averaged over 13 days (7/13 and 6/13 for the two calendar blocks). The adjusted estimate is TWFE minus bias.

The candidate set and hyperparameters were fixed before examining strike-period estimates: no correction; linear regression on 12 weekly group-gap means; one-pre-mean Synthetic Control with nonnegative weights and maximum-entropy tie-break; Random Forest (500 trees, 2 candidate features per split, leaf size 5); Gradient Boosting (800 depth-3 trees, learning rate 0.01, leaf size 10, subsample 0.7). The tree models fit daily treatment and control *group means* using relative day, treatment-arm indicator, weekday and month, because the simulated X1--X3 do not exist in the real data. Their target and feature set therefore differ from the simulation. Synthetic Control may observe contemporaneous controls; none use treated strike outcomes for fitting or selection.

Selection is minimum RMSE over 154 rolling 84-day training/13-day pre-strike placebo tests, stepping 14 days. All models are refitted within every window. The 13-day testing windows do not overlap but the 84-day training windows do; window-error uncertainty cannot assume independent windows. The selected method per outcome is frozen before final estimation. Fixed-method AIS-stratified bootstrap inference uses 499 draws; total-homicide selection-aware inference repeats all rolling windows, selection, and strike fitting in each draw (99 draws). Only five treated AIS make these intervals fragile, and the 99-draw tail quantiles are coarse. The machine-learning random seeds are deterministic and recorded in `code/estimate.py`.

The paper's intended five-AIS treatment is distinct from the released Stata code's four-AIS implementation: Stata lowercases AIS before comparing to uppercase `"AIS 13"`. A strict numeric 75th-percentile rule for `ExposureDistricts` includes AIS 07 (0.588235 versus threshold 0.587728) and gives six AIS. Four and six AIS appear only in sensitivity analyses. `code/replicate_mancha.py` independently reproduces the paper's *external* high-dimensional regression on the source's nonzero observation days. Those coefficients do not enter the thesis's TWFE correction equation.

The four-AIS total interaction reproduces 0.334996 versus the printed 0.335. The other published interactions differ by at most 0.0006; women's is 0.068401 versus printed 0.069, so it does not round identically to three decimals. That small discrepancy is not attributed to the thesis correction and has not been silently labeled an exact reproduction.

## Outputs

- `data/balanced_unit_day.csv.gz`, `data/observed_unit_day.csv.gz`, `data/unit_roster.csv`, `data/gang_exposure_audit.csv`: analysis data and source audit.
- `results/placebo_window_estimates.csv`, `placebo_performance.csv`, `paired_placebo_mse.csv`, `paired_placebo_hac.csv`: pre-strike evaluation, including all window-level pseudo-effects, method failure counts and a lag-six HAC sensitivity for paired MSE contrasts.
- `results/strike_estimates.csv`: all 35 final estimates with TWFE, predicted gap, pre-gap, bias, corrected estimate and pre-RMSE selection flag.
- `results/bootstrap_fixed_draws.csv.gz`, `bootstrap_fixed_summary.csv`: 499 AIS resamples for every outcome and method.
- `results/bootstrap_selection_aware_total.csv`, `bootstrap_selection_aware_total_summary.json`: full re-selection draws for total homicides.
- `results/sensitivity_total.csv`: pre-period length (8, 12, 26, 52, 104 weeks), four/five/six AIS and AIS-day aggregation.
- `results/mancha_external_replication.csv`: published, reproduced four-AIS and corrected-code five-AIS interactions under the original specification.
- `validation/output_checks.json`: common TWFE and bias-identity checks; `validation/bootstrap_*_failures.json`: draw failures.
- `validation/final_qa.json` and `validation/visual_qa.md`: final numerical/PDF text checks and 21-page visual inspection record.
- `validation/deliverable_manifest.csv`: SHA-256 hashes of the final generated data, code, numerical outputs, figures, QA files and manuscript snapshot.
- `figures/`: presentation copies of the new figures. LaTeX source tables and vector figures are in the updated thesis project.
- `report/RESULTS_CN.md`: Chinese audit and numerical handoff generated directly from the CSV outputs.
- `manuscript/thesis_project/`: a self-contained snapshot of the updated LaTeX project and compiled `main.pdf` after final verification.

## Reproduce

Use Python 3.12 with `pandas==3.0.1`, `numpy==2.3.5`, `scipy==1.18.1`, `scikit-learn==1.9.1`, `openpyxl==3.1.5`, `matplotlib==3.11.2`, and `pypdf==6.10.0` for final PDF QA. The existing thesis project also needs its TeX toolchain; this run compiled with Tectonic and rendered with Poppler. From `code`, run in this order:

```powershell
python prepare_data.py
python estimate.py qa
python estimate.py placebo
python placebo_dependence.py
python estimate.py final
python estimate.py sensitivity
python replicate_mancha.py
python bootstrap.py fixed --reps 499 --workers 4
python bootstrap.py selection --reps 99 --workers 4
python generate_artifacts.py
python generate_selection_table.py
# Compile the updated thesis project's main.tex to main.pdf, then copy that
# project into empirical_rebuild/manuscript/thesis_project.
python generate_report.py
python final_qa.py
python write_manifest.py
```

`prepare_data.py` uses the original absolute user-supplied input paths; edit its input constants only if replicating on another machine. Results are deterministic given the listed package versions and fixed seeds. The bootstrap and placebo stages are computationally intensive. The thesis project's `main.tex` inputs `empirical_rebuild_section.tex` and new `tables/*_rebuild.tex` files. Compile from the thesis project directory with its existing TeX setup. The public paper's own coefficients are external comparisons, not a denominator, offset or baseline for this correction.
