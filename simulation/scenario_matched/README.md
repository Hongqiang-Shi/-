# Scenario-matched revision

This revision adds an oracle group-gap correction to the validated 500-replication study. S0 uses no correction; S1--S3 and S6 extrapolate a linear pre-treatment treated-control gap; S4--S5 extrapolate a quadratic gap. The scenario label supplies the polynomial order, so the procedure is a simulation benchmark rather than an empirical model-selection rule.

All 3,500 panels were regenerated with the original final-run seeds. Regenerated TWFE and true-selection-bias values agree with the saved final results to below 5e-15. See `validation/scenario_matched_qa.csv`.
