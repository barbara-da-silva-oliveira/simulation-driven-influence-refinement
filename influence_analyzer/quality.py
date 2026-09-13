"""Data-quality and replication calculations; return tables without writing files."""

import json
import numpy as np
import pandas as pd
from .campaigns import ALIASES, SRPS, UNITS
from .preparation import finite, is_constant, numeric_mask


def quality_tables(data, raw, spec):
    """Return availability, replicate-statistics and aggregation-reconciliation tables.
    ``data`` has one row per design; optional ``raw`` has one row per replicate.
    """
    availability, replication, reconciliation = [], [], []
    for srp in SRPS:
        valid = data.loc[numeric_mask(data, srp)]
        y = finite(valid[srp]).to_numpy() if srp in valid else np.array([])
        vcol = srp + "_validity"
        flags = data[vcol].value_counts(dropna=False).to_dict() if vcol in data else {}
        status = ("column_missing" if srp not in data else "no_numeric_observations" if len(y) == 0
                  else "constant" if is_constant(y) else "variable")
        row = {"campaign": spec['code'], "srp": srp, "role": "target" if srp == spec['output_srp'] else "exploratory",
               "unit": UNITS[srp], "status": status, "n_designs": len(data), "n_numeric_designs": len(y),
               "n_distinct_values": len(np.unique(y)), "mean": np.mean(y) if len(y) else np.nan,
               "std_between_designs": np.std(y, ddof=1) if len(y) > 1 else np.nan,
               "min": np.min(y) if len(y) else np.nan, "max": np.max(y) if len(y) else np.nan,
               "n_behavioral_nan": int(flags.get("VALID_BEHAVIORAL_NAN", 0)),
               "validity_counts_json": json.dumps(flags), "n_numeric_runs": np.nan}
        if raw is not None and srp in raw:
            usable = raw.loc[numeric_mask(raw, srp)].copy()
            usable[srp] = finite(usable[srp])
            row["n_numeric_runs"] = len(usable)
            for design_id, sub in raw.groupby("design_id", sort=True):
                vals = finite(sub.loc[numeric_mask(sub, srp), srp]).to_numpy()
                mean = np.mean(vals) if len(vals) else np.nan
                expected = float(mean >= 0.5) if srp == "completed" and len(vals) else mean
                observed = float(data.set_index("design_id").at[design_id, srp])
                ok = bool(np.isclose(expected, observed, rtol=1e-8, atol=1e-10, equal_nan=True))
                replication.append({"design_id": design_id, "srp": srp, "n_raw_runs": len(sub),
                                    "n_numeric_replicates": len(vals), "replicate_mean": mean,
                                    "replicate_sd": np.std(vals, ddof=1) if len(vals) >= 2 else np.nan,
                                    "replicate_range": np.ptp(vals) if len(vals) else np.nan})
                reconciliation.append({"design_id": design_id, "srp": srp,
                                       "aggregate_value": observed, "recomputed_value": expected,
                                       "match": ok, "difference": observed - expected})
        availability.append(row)
    return pd.DataFrame(availability), pd.DataFrame(replication), pd.DataFrame(reconciliation)

def sampling_table(recorded, data, spec, source_name="campaign_wlhs_internal_weights.csv"):
    """Summarize an optional weights table already loaded by the I/O adapter."""
    rows = []
    if recorded is not None:
        for _, r in recorded.iterrows():
            participant = ALIASES.get(str(r["Input"]), str(r["Input"]))
            weight, shape = float(r["WeightMaxNorm"]), float(r["BetaShape"])
            values = finite(data[participant]).dropna() if participant in data else pd.Series(dtype=float)
            rows.append({"campaign": spec['code'], "participant": participant,
                         "mu_star_recorded": r["MuStarRaw"], "sampling_weight_max_norm": weight,
                         "beta_alpha": shape, "beta_beta": shape,
                         "implied_gain_if_weight_positive": (shape - 1) / weight if weight > 0 else np.nan,
                         "n_designs": len(values), "n_distinct_levels": values.nunique(),
                         "observed_min": values.min(), "observed_max": values.max(),
                         "source": source_name,
                         "interpretation": "recorded sampling policy used in functional campaign"})
    return pd.DataFrame(rows)
