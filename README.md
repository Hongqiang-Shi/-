# Thesis Draft Package

Prepared on 2026-10-02. This folder consolidates the current simulation and Ceará empirical code, existing numerical results, and the latest thesis draft. All existing files were copied without alteration; no models were re-estimated, no results were modified, and no source files were overwritten.

## Latest Thesis

- `main.pdf`: the latest verified version of the thesis. It contains 21 pages and includes the rebuilt Ceará empirical analysis, discussion, and conclusion.
- Original file: `C:\Users\hishi\Documents\Codex\2026-09-13\xia\outputs\vscode_thesis_project\main.pdf`.
- This PDF is identical to `empirical_rebuild/manuscript/thesis_project/main.pdf`. Its SHA-256 hash is `f6d318e08c062c9c254eb83e18728d86cc6ca9fc23f4fcc8d765a6e7a9b855f9`.
- `paper_source/`: the LaTeX main document, abstract, empirical section, tables, figures, and related source data for the same version. The compilation entry point is `paper_source/main.tex`. Older PDFs, archived drafts, and temporary compilation files are not included.

## Folder Structure

| Location | Contents |
| --- | --- |
| `simulation/original/` | Original panel-generation scripts, Monte Carlo pipeline, and 95% confidence-interval plotting scripts. The original relative project structure is preserved, together with the existing `final_500` outputs. |
| `simulation/audit_code/` | Code for auditing panels and results, producing summaries and figures, and packaging the original manuscript. |
| `simulation/audit_outputs/` | Audit documentation, original file inventory, run logs, R session information, and saved summaries. |
| `simulation/scenario_matched/` | R code, results, and validation for the scenario-matched gap correction. This method uses simulated scenario labels and therefore serves as an oracle benchmark. |
| `simulation/manuscript_tools/` | Scripts for generating and packaging the revised simulation figures and manuscript assets. |
| `empirical/code/` | All 11 Python scripts from the latest `empirical_rebuild`, rather than the earlier three-method empirical version. |
| `empirical/reference_code/Code_Ceara.do` | Mancha's original Stata code, retained as a separately identified external benchmark. It is not the entry point for the thesis's TWFE correction. |
| `empirical/data/` | Cleaned panel data, the unit roster, and the gang-exposure audit. |
| `empirical/results/` | Placebo results, strike-period estimates, bootstrap results, sensitivity analyses, and external replication results. |
| `empirical/figures/`, `report/`, `validation/` | Figures, the Chinese-language results report, source hashes, and numerical quality checks. The large rendered PDF page images were not copied into `validation/`. |
| `provenance/copied_files_manifest.csv` | The original path, destination-relative path, size, original modification time, and source/destination SHA-256 hash for every copied file. |
| `provenance/code_index.csv` | Entry-point index for 26 research-related code files: 14 simulation files, 11 empirical Python files, and one external Stata file. |

## Running the Code

This package is a **snapshot of the original implementations and results**, not a path-refactored, one-click portable software package. If the code is run directly, some scripts retain absolute paths that read from or write to the original `xia` and Desktop research directories. Do not assume that every output will be written into this folder. These paths were left unchanged to avoid altering the existing analysis.

Before rerunning the project on another computer, inspect and update the input directories, project root, output directories, and `.libPaths()` settings. This is especially important for the scenario-matched R scripts, the simulation Python plotting and packaging scripts, and the empirical data-cleaning, estimation, and external-replication scripts. It is advisable to copy the project to a separate working directory and set output paths explicitly so that the archived results in this package are not overwritten.

This package does not include the third-party `r_library`, a Python installation, or the original victim-level Excel files. Rebuilding the empirical cleaning stage still requires `Painel.xlsx`, `Gang_Turfs.xlsx`, and `Daily_Homicides_CE.dta`, located in `C:\Users\hishi\Desktop\Paper\When-the-State-Steps-Down-main\Bases`. Exact source hashes are recorded in `empirical/validation/source_hashes.csv`. The DTA file is derived from `Painel.xlsx` and is not an independent data source.

### Simulation

The original Monte Carlo entry point is `simulation/original/monte_carlo_evaluation/code/monte_carlo_pipeline.R`.

```powershell
Rscript monte_carlo_pipeline.R final 4
```

The `final` mode uses 500 replications for each scenario. The original script also supports the `pilot` and `all` modes. The original project used R 4.5.0, randomForest 4.7-1.2, gbm 2.3.1, and Synth 1.1-10. More complete environment details are available in `simulation/audit_outputs/session_info.txt`. The confidence-interval plotting entry point is `14_estimation_95ci_forest_plot.R` in the same directory, and the standalone DGP validation entry point is `simulation/original/panel_simulation_scenarios.R`.

After the original run is complete, the scripts in `audit_code/` can be used to validate the results and generate the original manuscript assets. The scenario-matched extension starts from `simulation/scenario_matched/code/scenario_matched_gap_correction.R`, which uses the original `final_500` outputs and audit summaries. The script `manuscript_tools/build_scenario_matched_revision.py` then generates the revised assets. These scripts retain references to their original directories. For details of the audit process, see `simulation/audit_outputs/README.md` and `simulation_audit.md`. The creation of this package should not be interpreted as a fresh rerun of the complete simulation.

### Empirical Analysis

The complete specification, data dictionary, and execution order are documented in `empirical/README.md` and `empirical/DATA_DICTIONARY.md`. The main candidate procedures are no correction, linear between-group gap correction, Synthetic Control, Random Forest, and Gradient Boosting. Each procedure subtracts its predicted untreated gap change from the same TWFE estimate. The external Mancha coefficient does not enter this correction formula.

The original analysis used Python 3.12 with pandas 3.0.1, numpy 2.3.5, scipy 1.18.1, scikit-learn 1.9.1, openpyxl 3.1.5, matplotlib 3.11.2, and pypdf 6.10.0. After updating the paths, run the scripts from `empirical/code/` in the following order:

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
# After compiling the thesis and updating the manuscript/thesis_project snapshot referenced by the scripts:
python generate_report.py
python final_qa.py
python write_manifest.py
```

`pdf_contact.py` is a helper script for rendering and visually checking the thesis PDF; it is not part of the estimation process. The placebo analysis and selection-aware bootstrap can take a substantial amount of time. Original directory names appearing in the copied `empirical/README.md` and manifest are provenance records and do not indicate that the package has already been ported.

## Package Verification

After copying, the source and destination SHA-256 hashes of all 204 existing files were compared individually and found to be identical. The three original simulation R scripts were also compared with the existing audit snapshot and matched exactly. The two existing locations of the latest PDF and the copy included in this package have the same hash. This packaging step only organized the files and verified their integrity; it did not rerun the simulation or empirical analysis or recompile the thesis.

`provenance/package_thesis_draft.ps1` records how this package was assembled. To protect existing files, the script terminates if the destination folder already exists and therefore cannot be rerun directly on the current package.
