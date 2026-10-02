# Simulation: Core Code and Results

This folder was streamlined on 2026-10-02. It retains five research scripts, the complete saved replication-level CSVs, numerical summaries, comparison figures, run metadata, compact quality reports, and environment information. No retained estimation code or numerical results were changed.

## Retained Files

| Location | Purpose |
| --- | --- |
| `original/panel_simulation_scenarios.R` | Original seven-scenario panel generator and DGP definitions. Simulated data are generated from the prescribed seeds; no external input dataset is required. |
| `original/monte_carlo_evaluation/code/monte_carlo_pipeline.R` | Original Monte Carlo estimation and evaluation pipeline. |
| `original/monte_carlo_evaluation/code/14_estimation_95ci_forest_plot.R` | Confidence-interval calculations and plotting from the complete replication CSV. |
| `original/monte_carlo_evaluation/output/final_500/` | Complete original replication results, method summaries, confidence-interval results, final figures, QA, failures, and run metadata. |
| `audit_code/validate_results.py` | Recomputes the full-precision summaries and method rankings used as inputs to the scenario-matched comparison. This supporting calculation script is retained; repeated refit and document-check scripts were removed. |
| `audit_outputs/` | Original-method summary, method rankings, and R environment information. |
| `scenario_matched/code/scenario_matched_gap_correction.R` | Scenario-matched linear/quadratic gap correction; the scenario label supplies the polynomial order, so this is an oracle benchmark. |
| `scenario_matched/results/` | Complete corrected replication results, corrected and combined summaries, rankings, paired TWFE comparisons, and coefficient summaries. |
| `scenario_matched/validation/` | Compact numerical QA and environment information. |

The original replication CSV contains 17,500 rows: seven scenarios, 500 replications per scenario, and five methods. The scenario-matched replication CSV contains 3,500 rows: seven scenarios and 500 replications. Individual simulated panels can be regenerated using the retained DGP functions and saved seeds.

## Execution and Dependencies

The original project used R 4.5.0 with `randomForest` 4.7-1.2, `gbm` 2.3.1, and `Synth` 1.1-10. See `audit_outputs/session_info.txt` and `scenario_matched/validation/session_info.txt`. The supporting Python summary script uses NumPy and pandas.

From `original/monte_carlo_evaluation/code/`, the original run command is:

```powershell
Rscript monte_carlo_pipeline.R final 4
```

The `final` mode uses 500 replications per scenario. The pipeline recreates checkpoint files during a new run; saved checkpoints from the completed run are not required to read or analyze the retained consolidated results.

The scenario-matched script consumes the original pipeline, `original/monte_carlo_evaluation/output/final_500/replication_results.csv`, and the summary retained as `audit_outputs/results_summary.csv`. The original scripts still contain their original directory settings. Before running elsewhere, update the scenario-matched script's `root`, `source_root`, `out_root`, and `old_summary_path`, and the supporting Python script's `SRC` and `OUT`, to the intended input and output directories. The Python script also contains historical inventory references that must be adapted if that script is rerun. Run in a separate output directory to preserve the saved results.

The thesis source and final manuscript figures are available in `../paper_source/`. Historical manuscript rewriting and packaging scripts are not needed for estimation or to use those saved assets.

## Cleanup and Recovery

Removed items are completed-run batch checkpoints, PDF layout-check images, alternate RDS copies of retained CSV results, a byte-identical duplicate summary, historical inventories/logs, repeated validation scripts, and scripts that packaged earlier manuscript versions.

All 79 removed files were verified against identical copies in their original research directories before removal. Those original copies were preserved. `../provenance/simulation_removed_files_2026-10-02.csv` lists each removed path, size, SHA-256 hash, recovery source, and reason. `../provenance/copied_files_manifest.csv` remains the historical record of the initial package; `../provenance/current_files_manifest.csv` describes the files currently present, excluding itself. The cleanup did not rerun any models or modify the retained results.
