"""Conditional direction evidence and controlled finite differences."""

from .campaigns import participants, participant_role
import json
import numpy as np
import pandas as pd
from .importance import association_row, direction
from .preparation import stable_groups
from .validation import analysis_groups


def monotonicity_tables(frame, spec, n_bootstrap):

    rows, steps = [], []
    for feature in participants(spec):
        others = [x for x in participants(spec) if x != feature]
        groups, _ = analysis_groups(frame, participants(spec), spec)
        # overall = association_row(frame, feature, spec['output_srp'], spec['objective'], groups, n_bootstrap)
        # overall.update({"condition": "all observed designs", "conditions_json": "{}",
        #                 "basis": "marginal_association", "other_participants_fixed": False})
        # rows.append(overall)
        # Numeric conditions use two quantile strata, adaptively bounded by data.
        # Conditions are participant ranges; upstream SRPs are never called envFactors.
        work = frame.copy()
        condition_cols = []
        if spec['code'] == "C" and feature == "w_gain":
            condition_cols = ["representative_id"]
        else:
            for col in others:
                label = "_condition_" + col
                if work[col].nunique() > 1:
                    work[label] = pd.qcut(work[col], q=2, duplicates="drop")
                    condition_cols.append(label)
        if condition_cols:
            for _, sub in work.groupby(condition_cols, observed=True, dropna=True):
                conditions = {col: {"observed_min": float(sub[col].min()),
                                    "observed_max": float(sub[col].max()),
                                    "participant_type": participant_role(spec, col)} for col in others}
                for col in others:
                    label = "_condition_" + col
                    if label in sub:
                        conditions[col]["quantile_bin"] = str(sub[label].iloc[0])
                condition = "; ".join(f"{col} in [{v['observed_min']:.6g}, {v['observed_max']:.6g}]"
                                      for col, v in conditions.items())
                fixed = all(sub[col].nunique() == 1 for col in others)
                # A fixed C representative supports w comparisons at distinct designs.
                subgroups = (stable_groups(sub, participants(spec)) if fixed else
                             analysis_groups(sub, participants(spec), spec)[0])
                row = association_row(sub, feature, spec['output_srp'], spec['objective'], subgroups, n_bootstrap)
                row.update({"condition": condition, "conditions_json": json.dumps(conditions),
                            "basis": "fixed_other_participants" if fixed else "binned_conditional_association",
                            "other_participants_fixed": fixed})
                if spec['code'] == "C" and feature == "w_gain":
                    row["representative_id"] = int(sub.representative_id.iloc[0])
                    row["joint_cell"] = str(sub.joint_cell.iloc[0]) if "joint_cell" in sub else ""
                rows.append(row)
        # Adjacent differences require the other participants to be exactly fixed.
        fixed_columns = ["representative_id"] if spec['code'] == "C" and feature == "w_gain" else others
        count = 0
        subsets = frame.groupby(fixed_columns, dropna=False) if fixed_columns else [((), frame)]
        for _, sub in subsets:
            levels = sub.groupby(feature)[spec['output_srp']].mean().sort_index()
            if len(levels) < 2:
                continue
            for (x0, y0), (x1, y1) in zip(list(levels.items())[:-1], list(levels.items())[1:]):
                slope = (y1 - y0) / (x1 - x0)
                tolerance = .01 * max(float(np.mean(np.abs(levels))), 1e-12) / np.ptp(levels.index.to_numpy(float))
                trend, effect = direction(slope, spec['objective'], tolerance)
                steps.append({"participant": feature, "srp": spec['output_srp'], "status": "observed_controlled_difference",
                              "fixed_conditions_json": json.dumps({col: float(sub[col].iloc[0]) for col in others}),
                              "x_start": x0, "x_end": x1, "y_start": y0, "y_end": y1,
                              "delta_y": y1 - y0, "delta_x": x1 - x0, "local_slope": slope,
                              "slope_tolerance": tolerance, "observed_trend": trend,
                              "objective_effect": effect, "uncertainty": "individual step not statistically validated"})
                count += 1
        if not count:
            steps.append({"participant": feature, "srp": spec['output_srp'], "status": "no_controlled_pairs",
                          "uncertainty": "other participants co-vary; no partial derivative inferred from adjacent LHS rows"})
    return pd.DataFrame(rows), pd.DataFrame(steps)
