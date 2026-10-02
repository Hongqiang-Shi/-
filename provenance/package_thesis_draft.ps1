$ErrorActionPreference = 'Stop'
$xiaRoot = 'C:\Users\hishi\Documents\Codex\2026-09-13\xia'
$researchRoot = 'C:\Users\hishi\Desktop\Paper\new paper process'
$draftTarget = Join-Path $xiaRoot 'thesis draft'
if (Test-Path -LiteralPath $draftTarget) { throw "Target already exists; refusing to overwrite: $draftTarget" }
$copyPlan = [System.Collections.Generic.List[object]]::new()
function Add-File([string]$Source, [string]$Relative, [string]$Category) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Missing source: $Source" }
    $copyPlan.Add([pscustomobject]@{Source=$Source; Relative=$Relative; Category=$Category})
}
function Add-Tree([string]$Source, [string]$Relative, [string]$Category) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing directory: $Source" }
    Get-ChildItem -LiteralPath $Source -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/]__pycache__[\\/]' } | ForEach-Object {
        $suffix = $_.FullName.Substring($Source.TrimEnd('\').Length + 1)
        Add-File $_.FullName (Join-Path $Relative $suffix) $Category
    }
}

# Preserve the research project's layout for its original R entry points.
Add-File (Join-Path $researchRoot 'panel_simulation_scenarios.R') 'simulation\original\panel_simulation_scenarios.R' 'simulation_code'
Add-Tree (Join-Path $researchRoot 'monte_carlo_evaluation\code') 'simulation\original\monte_carlo_evaluation\code' 'simulation_code'
Add-Tree (Join-Path $researchRoot 'monte_carlo_evaluation\output\final_500') 'simulation\original\monte_carlo_evaluation\output\final_500' 'simulation_saved_results'
$auditRoot = Join-Path $xiaRoot 'outputs\thesis_draft_outputs'
Get-ChildItem -LiteralPath (Join-Path $auditRoot 'code') -File | ForEach-Object { Add-File $_.FullName (Join-Path 'simulation\audit_code' $_.Name) 'simulation_code' }
foreach ($name in @('README.md','simulation_audit.md','session_info.txt','run_log.txt','file_inventory.csv','results_summary.csv','results_summary_updated.csv','method_ranking_by_scenario.csv')) {
    Add-File (Join-Path $auditRoot $name) (Join-Path 'simulation\audit_outputs' $name) 'simulation_documentation_results'
}
$revisionRoot = Join-Path $xiaRoot 'outputs\scenario_matched_revision'
Add-Tree (Join-Path $revisionRoot 'code') 'simulation\scenario_matched\code' 'simulation_code'
Add-Tree (Join-Path $revisionRoot 'results') 'simulation\scenario_matched\results' 'simulation_saved_results'
Add-Tree (Join-Path $revisionRoot 'validation') 'simulation\scenario_matched\validation' 'simulation_validation'
Add-File (Join-Path $revisionRoot 'README.md') 'simulation\scenario_matched\README.md' 'simulation_documentation'
foreach ($name in @('build_scenario_matched_revision.py','package_scenario_revision.py')) {
    Add-File (Join-Path $xiaRoot "work\$name") (Join-Path 'simulation\manuscript_tools' $name) 'simulation_code'
}

$empiricalRoot = Join-Path $xiaRoot 'empirical_rebuild'
foreach ($part in @('code','data','results','figures','report')) {
    Add-Tree (Join-Path $empiricalRoot $part) (Join-Path 'empirical' $part) "empirical_$part"
}
foreach ($name in @('README.md','DATA_DICTIONARY.md')) {
    Add-File (Join-Path $empiricalRoot $name) (Join-Path 'empirical' $name) 'empirical_documentation'
}
Get-ChildItem -LiteralPath (Join-Path $empiricalRoot 'validation') -File | Where-Object { $_.Extension -in @('.csv','.json','.md') } | ForEach-Object {
    Add-File $_.FullName (Join-Path 'empirical\validation' $_.Name) 'empirical_validation'
}
Add-File 'C:\Users\hishi\Desktop\Paper\When-the-State-Steps-Down-main\Do Files\Code_Ceara.do' 'empirical\reference_code\Code_Ceara.do' 'external_reference_code'

$paperRoot = Join-Path $xiaRoot 'outputs\vscode_thesis_project'
Add-File (Join-Path $paperRoot 'main.pdf') 'main.pdf' 'latest_paper_pdf'
foreach ($name in @('main.tex','abstract.tex','empirical_rebuild_section.tex')) {
    Add-File (Join-Path $paperRoot $name) (Join-Path 'paper_source' $name) 'paper_source'
}
foreach ($part in @('tables','figures','source_data','.vscode')) {
    Add-Tree (Join-Path $paperRoot $part) (Join-Path 'paper_source' $part) 'paper_source'
}
Add-File $PSCommandPath 'provenance\package_thesis_draft.ps1' 'packaging_tool'

# Confirm the archived original simulation scripts match the audited snapshots.
foreach ($name in @('panel_simulation_scenarios.R','monte_carlo_pipeline.R','14_estimation_95ci_forest_plot.R')) {
    $source = if ($name -eq 'panel_simulation_scenarios.R') { Join-Path $researchRoot $name } else { Join-Path $researchRoot "monte_carlo_evaluation\code\$name" }
    $snapshot = Join-Path $auditRoot "code\source\$name"
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $snapshot).Hash) { throw "Simulation source differs from audited snapshot: $name" }
}
if (($copyPlan | Group-Object Relative | Where-Object Count -gt 1).Count -gt 0) { throw 'Duplicate destination in copy plan' }
New-Item -ItemType Directory -Path $draftTarget | Out-Null
$manifest = foreach ($item in $copyPlan) {
    $destination = Join-Path $draftTarget $item.Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $destination
    $sourceHash = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) { throw "Copy verification failed: $($item.Relative)" }
    [pscustomobject]@{category=$item.Category; destination=$item.Relative; source=$item.Source; bytes=(Get-Item -LiteralPath $destination).Length; source_modified=(Get-Item -LiteralPath $item.Source).LastWriteTime.ToString('o'); source_sha256=$sourceHash; destination_sha256=$targetHash; verified=$true}
}
$manifest | Export-Csv -LiteralPath (Join-Path $draftTarget 'provenance\copied_files_manifest.csv') -NoTypeInformation -Encoding UTF8
[pscustomobject]@{target=$draftTarget; copied_files=$manifest.Count; study_code_files=($manifest | Where-Object category -in @('simulation_code','empirical_code','external_reference_code')).Count; copied_bytes=($manifest | Measure-Object bytes -Sum).Sum; all_hashes_verified=$true} | ConvertTo-Json
