"""Generate a Chinese numerical handoff directly from verified CSV outputs."""
from pathlib import Path
import json
import pandas as pd

root = Path(__file__).resolve().parents[1]
result = root / "results"
flow = json.loads((root / "validation" / "sample_flow.json").read_text(encoding="utf-8"))
selection = json.loads((result / "bootstrap_selection_aware_total_summary.json").read_text(encoding="utf-8"))
p = pd.read_csv(result / "placebo_performance.csv")
e = pd.read_csv(result / "strike_estimates.csv")
ci = pd.read_csv(result / "bootstrap_fixed_summary.csv")
e = e.merge(ci[["outcome","method","ci025","ci975"]],on=["outcome","method"],validate="one_to_one")
m = pd.read_csv(result / "mancha_external_replication.csv")
s = pd.read_csv(result / "sensitivity_total.csv")
outcomes = ["total","men","women","crime_1","crime_2","crime_3","crime_4"]
methods = ["twfe","linear_gap","synthetic_control","random_forest","gradient_boosting"]
names = {"twfe":"不校正","linear_gap":"线性差距","synthetic_control":"SC（熵择优）","random_forest":"RF（实证特征）","gradient_boosting":"GB（实证特征）"}

lines = ["# Ceará empirical rebuild：结果与核查", "",
"所有下表数值由 `results/*.csv` 自动生成。估计单位是每个 municipality/district 每日凶杀案数；主处理组为 AIS 02、06、11、12、13。", "",
"## 方法与数据变更", "",
f"- 从 `Painel.xlsx` 的 {flow['painel_rows']:,} 条受害者记录开始；排除 {flow['painel_excluded_rows']} 条 AIS 缺失/无效记录，保留 {flow['painel_valid_homicides']:,} 条有效记录。", 
f"- 重建 {flow['units']} 个地点、{flow['ais']} 个 AIS、{flow['calendar_days']:,} 天的平衡面板，共 {flow['balanced_rows']:,} 个单位日；其中 {flow['zero_filled_unit_days']:,} 个是补零日。84+13 天主窗口有 {flow['main_window_rows']:,} 个单位日、{flow['main_window_zero_total_rows']:,} 个零值日。",
"- `Daily_Homicides_CE.dta` 是源表的中间产物；重新按单位日汇总后与原始 `Painel.xlsx` 在七个结果上逐项一致，不算独立证据。保留 7 条完全相同的受害者记录，因为无法证明是重复受害者；DTA 有 1 个被拆成两行的单位日。",
"- 主处理组采用论文正文所列五个 AIS。发布的 Stata 代码先转小写再用大写 `AIS 13` 判断，因此实际运行四 AIS；机械高于上四分位阈值又会纳入 AIS 07，成为六 AIS。四、六 AIS 仅用于敏感性。",
"- 所有方法共用同一个单位/日期 TWFE DID 和同一个 84 天处理前平均差距；校正项是预测的无罢工处理后差距减去该基准，处理后 7/6 天按 7/13 与 6/13 加权。",
"- SC 以处理前单一均值匹配并用最大熵处理多重解，可用同期对照组结果；RF/GB 改用预测时已知的相对日、组别、星期、月份特征拟合组均值，与 simulation 的单位级 X1–X3 特征不同。", "",
"## 处理前滚动 placebo（154 个相同窗口）", "",
"每窗口用此前 84 天训练，预测随后 13 天；下表误差是虚拟处理效应（真实值为零）。方差采用总体分母；重叠的训练窗口使误差相关。主要选择标准事前固定为 RMSE 最小。", "",
"| 结果 | 方法 | 平均有符号误差 | 方差 | MAE | RMSE | 可用 | 失败 |", "|---|---|---:|---:|---:|---:|---:|---:|"]
for o in outcomes:
    for method in methods:
        r = p[(p.outcome==o)&(p.method==method)].iloc[0]
        lines.append(f"| {o} | {names[method]} | {r.signed_bias:.5f} | {r.variance:.6f} | {r.mae:.5f} | {r.rmse:.5f} | {int(r.windows_available)} | {int(r.failures)} |")
lines += ["", "总凶杀案 RF 的 RMSE 为 0.00809，TWFE 为 0.00830，相对降低约 2.6%；但配对 MSE 差异的 lag-6 HAC 标准误超过其绝对差异，因此不能将这点优势解释为明确统计分离。", "",
"## 罢工期估计与固定方法 AIS 区间", "",
"下表每一行都从该结果变量的相同 TWFE 扣除该方法的预测偏差项；`*` 是处理前 RMSE 选中的方法。百分位区间来自 499 次 AIS 分层重抽样。", "",
"| 结果 | 方法 | TWFE | 预测偏差 | 校正后估计 | 95% 区间 | 入选 |", "|---|---|---:|---:|---:|---|:---:|"]
for o in outcomes:
    for method in methods:
        r = e[(e.outcome==o)&(e.method==method)].iloc[0]
        lines.append(f"| {o} | {names[method]} | {r.twfe:.4f} | {r.bias_term:.4f} | {r.adjusted_estimate:.4f} | [{r.ci025:.4f}, {r.ci975:.4f}] | {'*' if r.selected_by_prestrike_rmse else ''} |")
counts = ", ".join(f"{names[k]} {selection['selection_counts'].get(k,0)} 次" for k in methods)
lines += ["", "## 完整重新选择的推断（总凶杀案）", "",
f"对总凶杀案进行了 {selection['draws']} 次 AIS 分层重抽样；每次完整重跑全部 154 个 placebo 窗口、全部五方法的 RMSE 选择及罢工期重估。选择次数：{counts}。选中程序的 95% 百分位区间为 [{selection['ci025']:.4f}, {selection['ci975']:.4f}]；标准差 {selection['se']:.4f}。尾部由 99 次抽样估计，精度有限。", "",
"## 与 Mancha 原回归的外部对照", "",
"原回归使用非零观察日、2014–2020 年全时段、地点/AIS-年/月/星期固定效应及全州罢工项；本论文使用补零的 97 日窗口、地点和逐日固定效应、不同权重及正文五 AIS。系数不是同一估计对象，二者差额不是校正偏差。", "",
"| 结果 | 原文印刷 | 四 AIS 复算 | 五 AIS 同式复算 | 本论文 TWFE |", "|---|---:|---:|---:|---:|"]
for o in outcomes:
    a=m[(m.outcome==o)&(m.treatment_definition=="released_code_four")].iloc[0]
    b=m[(m.outcome==o)&(m.treatment_definition=="paper_intended_five")].iloc[0]
    c=e[(e.outcome==o)&(e.method=="twfe")].iloc[0]
    lines.append(f"| {o} | {a.published_interaction:.3f} | {a.reproduced_interaction:.6f} | {b.reproduced_interaction:.6f} | {c.twfe:.6f} |")
lines += ["", "女性外部系数复算 0.068401，对原文 0.069 相差 0.000599，三位小数不能完全复现；其余差异不超过 0.000404。该差异未被称作本论文的校正效果。", "",
"## 敏感性与限制", "",
"`results/sensitivity_total.csv` 给出 8、12、26、52、104 周、四/五/六 AIS，以及 AIS 日聚合下五方法的总凶杀案估计。12 周 TWFE：五 AIS 0.0344、四 AIS 0.0568、六 AIS 0.0349；AIS 日聚合为 0.7671，但计量单位和权重已改变。", "",
"主要限制：五个处理 AIS 极少；部分结局稀有；SC 与纯处理前预测器的信息集不同；ML 无 simulation 的生成协变量；处理前预测不能观察或证明罢工期真实反事实；窗口训练集重叠；女性残差类别包含 24 个未分类性别记录。", "",
"## 复现入口", "",
"从 `README.md` 的命令顺序运行 `code/prepare_data.py`、`estimate.py`、`placebo_dependence.py`、`replicate_mancha.py`、`bootstrap.py` 及生成脚本。`validation/source_hashes.csv` 提供五个原始资料的 SHA-256；`validation/output_checks.json` 记录共同基准与代数恒等式。新版论文在 `manuscript/thesis_project/main.pdf`（同时更新原 xia 项目）。", ""]
(root / "report" / "RESULTS_CN.md").write_text("\n".join(lines), encoding="utf-8")
