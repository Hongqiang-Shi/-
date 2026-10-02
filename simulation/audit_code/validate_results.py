from pathlib import Path
import hashlib, json, math, sys, csv
import numpy as np
import pandas as pd
SRC=Path(r'C:/Users/hishi/Desktop/Paper/new paper process')
OUT=Path('outputs/thesis_draft_outputs')
for name in ['tables','figures','validation','code']:(OUT/name).mkdir(exist_ok=True)
records=[]
for p in sorted(SRC.rglob('*')):
 if not p.is_file():continue
 rel=p.relative_to(SRC).as_posix(); ext=p.suffix.lower()
 if 'r_library/' in rel: role='environment'; purpose='Installed R package component; see package DESCRIPTION'; used='No; dependency of estimator pipeline only'
 elif rel=='panel_simulation_scenarios.R':role='script';purpose='Authoritative original seven-scenario panel generator';used='Main script'
 elif '/code/' in rel:role='script';purpose='Monte Carlo estimator pipeline or add-on' if rel.startswith('monte') else 'Single-panel estimation/diagnostics/plot script';used='No; downstream or separate pipeline'
 elif '/checkpoints/' in rel:role='intermediate object';purpose='Saved Monte Carlo batch estimates';used='No'
 elif '/figures/' in rel:role='final output';purpose='Existing diagnostic or method-comparison figure';used='No'
 elif rel.startswith('simulation_output/') and '/' not in rel[len('simulation_output/'):]:
  role='final output' if ext in ['.csv','.rds'] else 'notes';purpose='Generated panel/scenario output' if ext in ['.csv','.rds'] else 'Prior working notes or extracted document content';used='Written by main' if ext in ['.csv','.rds'] else 'No'
 elif '/data/raw/' in rel:role='input';purpose='Duplicate generated panels/metadata for single-panel workflow';used='No; downstream input'
 elif '.tmp_docx/' in rel:role='intermediate object';purpose='Prior Word extraction/archive; historical instructions are source content only';used='No'
 elif ext in ['.md','.txt'] or p.name=='.Rhistory':role='notes';purpose='Workflow notes or historical commands; not current instructions';used='No'
 else:role='final output';purpose='Saved estimation/diagnostic table or object';used='No'
 records.append(dict(filename=rel,file_type=ext or '(no extension)',bytes=p.stat().st_size,likely_purpose=purpose,role=role,used_by_main=used,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
for p,role in [(Path(r'C:/Users/hishi/Downloads/My_Research (3).pdf'),'proposal'),(Path(r'C:/Users/hishi/.codex/attachments/07c8c009-a265-4abe-94d9-6b9f392571f3/pasted-text.txt'),'user request')]:
 records.append(dict(filename=str(p),file_type=p.suffix,bytes=p.stat().st_size,likely_purpose=role,role=role,used_by_main='No',sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
pd.DataFrame(records).to_csv(OUT/'file_inventory.csv',index=False)
raw=pd.read_csv(SRC/'monte_carlo_evaluation/output/final_500/replication_results.csv')
saved=pd.read_csv(SRC/'monte_carlo_evaluation/output/final_500/scenario_method_summary.csv')
assert len(raw)==17500 and not raw.duplicated(['scenario','replication','method']).any()
assert raw.status.eq('ok').all() and raw.generation_attempt.eq(1).all()
assert np.isfinite(raw.tau_estimate).all()
assert raw.groupby(['scenario','method']).size().eq(500).all()
checks={}
def check(name,a,b,tol=1e-10):
 a=np.asarray(a,dtype=float);b=np.asarray(b,dtype=float)
 assert np.array_equal(np.isnan(a),np.isnan(b)),name
 d=float(np.nanmax(np.abs(a-b))) if np.isfinite(a).any() else 0
 checks[name]=d
 assert d<tol,(name,d)
check('stored_error',raw.estimation_error,raw.tau_estimate-2)
check('absolute_error',raw.absolute_error,abs(raw.tau_estimate-2))
check('squared_error',raw.squared_error,(raw.tau_estimate-2)**2)
a=raw[raw.method.ne('twfe')]; b=raw[raw.method.eq('twfe')]
check('adjusted_identity',a.tau_estimate,a.twfe_estimate-a.estimated_selection_bias)
check('oracle_identity',b.tau_estimate-2,b.true_selection_bias)
check('selection_error_identity',a.selection_bias_error,-a.estimation_error)
for sc,g in raw.groupby('scenario'):
 idx=int(sc[1])+1
 check('seed_'+sc,g.dgp_seed,20370000+100000*idx+g.replication)
 for m,h in g.groupby('method'):assert set(h.replication)==set(range(1,501))
summ=[]
for (sc,m),g in raw.groupby(['scenario','method']):
 x=g.tau_estimate.to_numpy();e=x-2;sb=g.selection_bias_error.dropna().to_numpy();n=len(x)
 sm=lambda x:float(np.mean(x)) if len(x) else np.nan
 sd=lambda x:float(np.std(x,ddof=1)) if len(x)>1 else np.nan
 rm=lambda x:float(np.sqrt(np.mean(x*x))) if len(x) else np.nan
 row=dict(scenario=sc,method=m,forecast_method=g.forecast_method.iloc[0],true_ATT=2,n_total=n,n_success=n,n_failed=0,failure_rate=0,mean_estimate=sm(x),monte_carlo_bias=sm(e),absolute_bias=abs(sm(e)),mean_absolute_error=sm(abs(e)),relative_bias_pct=100*sm(e)/2,rmse=rm(e),empirical_sd=sd(x),monte_carlo_standard_error=sd(e)/np.sqrt(n),mean_true_selection_bias=sm(g.true_selection_bias.to_numpy()),mean_estimated_selection_bias=sm(g.estimated_selection_bias.dropna().to_numpy()),selection_bias_mean_error=sm(sb),selection_bias_absolute_bias=abs(sm(sb)),selection_bias_mean_absolute_error=sm(abs(sb)),selection_bias_rmse=rm(sb),selection_bias_monte_carlo_se=sd(sb)/np.sqrt(len(sb)) if len(sb) else np.nan,mean_runtime_seconds=sm(g.runtime_seconds.to_numpy()),total_runtime_seconds=float(g.runtime_seconds.sum()))
 old=saved[(saved.scenario==sc)&(saved.method==m)].iloc[0]
 for k,v in row.items():
  if k not in ['scenario','method','forecast_method']:check(sc+'|'+m+'|'+k,[v],[old[k]])
 row.update(variance_population=float(np.var(x,ddof=0)),variance_sample=float(np.var(x,ddof=1)),rmse_mcse=sd(e*e)/np.sqrt(n)/(2*rm(e)),coverage=np.nan,coverage_status='not implemented',validation_status='all raw summaries independently verified; 3 selected refits per scenario checked separately')
 check(sc+'|'+m+'|mse_decomposition',[row['rmse']**2],[row['monte_carlo_bias']**2+row['variance_population']])
 summ.append(row)
s=pd.DataFrame(summ)
s.to_csv(OUT/'results_summary.csv',index=False,float_format='%.16g')
s.melt(id_vars=['scenario','method','validation_status'],value_vars=[c for c in s.select_dtypes('number').columns],var_name='metric',value_name='value').to_csv(OUT/'tables/results_summary_long.csv',index=False,float_format='%.16g')
ranking=[];paired=[]
for sc,g in s.groupby('scenario'):
 g=g.copy()
 for metric in ['absolute_bias','rmse','variance_population']:
  # Round only for rank tie handling: linear and TWFE are algebraically identical.
  g[metric+'_rank']=g[metric].round(12).rank(method='min').astype(int)
  mask=g.method.ne('twfe')
  g.loc[mask,metric+'_adjusted_rank']=g.loc[mask,metric].round(12).rank(method='min')
 ranking.append(g[['scenario','method','absolute_bias','rmse','variance_population']+[c for c in g if c.endswith('_rank')]])
 p=raw[raw.scenario==sc].pivot(index='replication',columns='method',values='tau_estimate')-2
 methods=list(p.columns)
 for i,m in enumerate(methods):
  for n in methods[i+1:]:
   d=p[m]-p[n];q=p[m]**2-p[n]**2
   paired.append(dict(scenario=sc,method_a=m,method_b=n,mean_error_difference=d.mean(),paired_error_difference_mcse=d.std(ddof=1)/np.sqrt(500),mse_difference=q.mean(),paired_mse_difference_mcse=q.std(ddof=1)/np.sqrt(500)))
pd.concat(ranking).to_csv(OUT/'method_ranking_by_scenario.csv',index=False,float_format='%.16g')
pd.DataFrame(paired).to_csv(OUT/'tables/paired_monte_carlo_comparisons.csv',index=False,float_format='%.16g')
pd.DataFrame([{'check':k,'max_abs_difference':v,'passed':True} for k,v in checks.items()]).to_csv(OUT/'validation/numerical_checks.csv',index=False)
print(s[['scenario','method','monte_carlo_bias','rmse','variance_population','monte_carlo_standard_error']].to_string(index=False))
print('Inventory files:',len(records),'Numerical checks:',len(checks),'Largest discrepancy:',max(checks.values()))
