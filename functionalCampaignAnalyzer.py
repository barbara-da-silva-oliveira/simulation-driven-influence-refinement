#!/usr/bin/env python3
"""
Analyzer for aggregated functional simulation campaign CSV files.

Run from the SimulationCampaign folder:

    python3 functionalCampaignAnalyzer.py

Or pass the SimulationCampaign folder:

    python3 functionalCampaignAnalyzer.py /path/to/SimulationCampaign

"""

from __future__ import annotations

import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd


# Configuration

MIN_R2 = 0.85                  # analytic function acceptance threshold
MAX_NRMSE = 0.15               # analytic function acceptance threshold
ENV_FACTOR_BINS = 4            # numeric envFactor columns are split into this many ranges
ALL_PAIRS = False              # True = analyze every numeric input against every known SRP

VALIDITY_OK = {
    "VALID",
    "VALID_ZERO",
    "VALID_BOOLEAN",
    "VALID_BEHAVIORAL_NAN",
    "OK",
    "OK_ALL_REPLICATES",
    "OK_PARTIAL_REPLICATES",
}

SRP_COLUMNS = [
    "completed",
    "completion_time",
    "average_segment_speed",
    "sign_detection_quality",
    "tracking_error_rms",
    "left_distance_to_sign",
    "right_distance_to_sign",
    "stop_distance_to_sign",
    "time_turning",
    "time_to_next_blob20_first",
    "time_to_next_blob20_count",
]

LOWER_IS_BETTER = {
    "completion_time",
    "tracking_error_rms",
    "left_distance_to_sign",
    "right_distance_to_sign",
    "stop_distance_to_sign",
    "time_turning",
    "time_to_next_blob20_first",
}

HIGHER_IS_BETTER = {
    "completed",
    "average_segment_speed",
    "sign_detection_quality",
    "time_to_next_blob20_count",
}

NON_INPUT_COLUMNS = {
    "design_id",
    "run_id",
    "rep",
    "scenario_id",
    "aggregate_status",
    "n_target_replicates",
    "n_valid_replicates",
    "n_missing_logs_replicates",
    "n_invalid_technical_replicates",
    "source_scenario_id",
    "source_scenario_id_P",
    "source_scenario_id_S",
    "source_design_id",
    "label",
}


@dataclass(frozen=True)
class InfluenceSpec:
    """One expected influence analysis from the campaign CSV."""

    name: str
    participant: str
    srp: str
    objective: str
    envFactors: Tuple[str, ...] = ()


DEFAULT_INFLUENCES = [
    InfluenceSpec(
        name="I_Perception_BlobSize_SignDetectionQuality",
        participant="target_blob_size",
        srp="sign_detection_quality",
        objective="maximize",
        envFactors=("luminosity_level",),
    ),
    InfluenceSpec(
        name="I_Perception_Size_SignDetectionQuality",
        participant="size",
        srp="sign_detection_quality",
        objective="maximize",
        envFactors=("luminosity",),
    ),
    InfluenceSpec(
        name="I_Locomotion_VNominal_AverageSegmentSpeed",
        participant="v_nominal",
        srp="average_segment_speed",
        objective="maximize",
        envFactors=("friction_surface",),
    ),
    InfluenceSpec(
        name="I_Locomotion_V_AverageSegmentSpeed",
        participant="v",
        srp="average_segment_speed",
        objective="maximize",
        envFactors=("friction",),
    ),
    InfluenceSpec(
        name="I_Control_WGain_TrackingError",
        participant="w_gain",
        srp="tracking_error_rms",
        objective="minimize",
        envFactors=("source_regime",),
    ),
    InfluenceSpec(
        name="I_Control_WGain_TrackingError_JointCell",
        participant="w_gain",
        srp="tracking_error_rms",
        objective="minimize",
        envFactors=("joint_cell",),
    ),
    InfluenceSpec(
        name="I_Control_WGain_TrackingError_P_S_Regimes",
        participant="w_gain",
        srp="tracking_error_rms",
        objective="minimize",
        envFactors=("source_regime_P", "source_regime_S"),
    ),
    InfluenceSpec(
        name="I_Control_W_TrackingError",
        participant="w",
        srp="tracking_error_rms",
        objective="minimize",
        envFactors=("source_regime",),
    ),
    InfluenceSpec(
        name="I_Mission_VNominal_TimeTurning",
        participant="v_nominal",
        srp="time_turning",
        objective="minimize",
        envFactors=("source_regime",),
    ),
    InfluenceSpec(
        name="I_Mission_WGain_TimeTurning",
        participant="w_gain",
        srp="time_turning",
        objective="minimize",
        envFactors=("source_regime",),
    ),
]


# File path 

def infer_functional_results_dir(simulation_campaign_dir: Path) -> Path:
    return simulation_campaign_dir / "FunctionalCampaign" / "functional_campaign_results"


def infer_output_dir(simulation_campaign_dir: Path) -> Path:
    return simulation_campaign_dir / "InfluenceAnalysisResults"


def find_aggregated_csvs(functional_results_dir: Path) -> List[Tuple[str, Path]]:
    if not functional_results_dir.exists():
        raise FileNotFoundError(f"Functional results folder not found: {functional_results_dir}")

    exact = sorted(functional_results_dir.glob("*/campaign_summary_design_aggregated.csv"))
    if exact:
        return [(p.parent.name, p) for p in exact]

    fallback = sorted(functional_results_dir.glob("**/*aggregated*.csv"))
    return [(p.parent.name, p) for p in fallback]


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def safe_dir_name(text: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", str(text)).strip("_")
    return cleaned or "unnamed"


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


# Basic utilities


def is_numeric_series(series: pd.Series) -> bool:
    return pd.api.types.is_numeric_dtype(series) or pd.to_numeric(series, errors="coerce").notna().any()


def as_numeric(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce")


def validity_col(metric: str) -> str:
    return f"{metric}_validity"


def objective_for_metric(metric: str) -> str:
    return "minimize" if metric in LOWER_IS_BETTER else "maximize"


def fmt_num(value: object, digits: int = 6) -> str:
    try:
        x = float(value)
    except Exception:
        return str(value)
    if not math.isfinite(x):
        return "nan"
    return f"{x:.{digits}g}"


def sanitize_identifier(name: str) -> str:
    out = re.sub(r"[^A-Za-z0-9_]", "_", str(name))
    if not out or out[0].isdigit():
        out = "v_" + out
    return out


# Influence

def available_srps(df: pd.DataFrame) -> List[str]:
    return [c for c in SRP_COLUMNS if c in df.columns and is_numeric_series(df[c])]


def numeric_input_columns(df: pd.DataFrame) -> List[str]:
    srps = set(available_srps(df))
    out = []
    for c in df.columns:
        if c in srps:
            continue
        if c in NON_INPUT_COLUMNS:
            continue
        if c.endswith("_validity"):
            continue
        if not is_numeric_series(df[c]):
            continue
        out.append(c)
    return out


def influence_exists(df: pd.DataFrame, spec: InfluenceSpec) -> bool:
    if spec.participant not in df.columns or spec.srp not in df.columns:
        return False
    if not is_numeric_series(df[spec.participant]) or not is_numeric_series(df[spec.srp]):
        return False
    # EnvFactors are optional when the SRP input is present
    return True


def present_envFactors(df: pd.DataFrame, envFactors: Sequence[str]) -> Tuple[str, ...]:
    return tuple(c for c in envFactors if c in df.columns)


def infer_influences(df: pd.DataFrame, all_pairs: bool = ALL_PAIRS) -> List[InfluenceSpec]:
    influences: List[InfluenceSpec] = []
    seen = set()

    for spec in DEFAULT_INFLUENCES:
        if influence_exists(df, spec):
            actual = InfluenceSpec(
                name=spec.name,
                participant=spec.participant,
                srp=spec.srp,
                objective=spec.objective,
                envFactors=present_envFactors(df, spec.envFactors),
            )
            key = (actual.participant, actual.srp, actual.envFactors)
            if key not in seen:
                influences.append(actual)
                seen.add(key)

    if all_pairs or not influences:
        for participant in numeric_input_columns(df):
            for srp in available_srps(df):
                if participant == srp:
                    continue
                key = (participant, srp, ())
                if key in seen:
                    continue
                influences.append(
                    InfluenceSpec(
                        name=f"I_{participant}_to_{srp}",
                        participant=participant,
                        srp=srp,
                        objective=objective_for_metric(srp),
                        envFactors=(),
                    )
                )
                seen.add(key)

    return influences


# Data preparation


def keep_valid_metric_rows(df: pd.DataFrame, metric: str) -> pd.DataFrame:
    out = df.copy()
    vcol = validity_col(metric)
    if vcol in out.columns:
        out = out[out[vcol].astype(str).isin(VALIDITY_OK)].copy()
    elif "aggregate_status" in out.columns:
        out = out[out["aggregate_status"].astype(str).isin(VALIDITY_OK)].copy()
    out[metric] = as_numeric(out[metric])
    out = out.dropna(subset=[metric])
    return out


def interval_labels(series: pd.Series, n_bins: int) -> Tuple[pd.Series, Optional[Dict[str, object]]]:
    s = as_numeric(series)
    non_null = s.dropna()
    if non_null.empty:
        return pd.Series("overall", index=series.index), None

    unique_count = non_null.nunique()
    if unique_count <= 1:
        value = fmt_num(non_null.iloc[0])
        labels = pd.Series(f"[{value}]", index=series.index, dtype="object")
        return labels, {"mode": "constant", "value": float(non_null.iloc[0])}

    bins = max(1, min(int(n_bins), int(unique_count)))
    quantiles = np.linspace(0, 1, bins + 1)
    edges = np.unique(np.quantile(non_null.to_numpy(dtype=float), quantiles))
    if len(edges) <= 1:
        value = fmt_num(non_null.iloc[0])
        labels = pd.Series(f"[{value}]", index=series.index, dtype="object")
        return labels, {"mode": "constant", "value": float(non_null.iloc[0])}

    labels_text = []
    for i in range(len(edges) - 1):
        left = fmt_num(edges[i])
        right = fmt_num(edges[i + 1])
        close = "]" if i == len(edges) - 2 else ")"
        labels_text.append(f"[{left}, {right}{close}")

    categories = pd.cut(s, bins=edges, labels=labels_text, include_lowest=True, duplicates="drop")
    return categories.astype("object"), {
        "mode": "quantile_interval",
        "bins": len(edges) - 1,
        "edges": [float(x) for x in edges],
    }


def prepare_envFactors(df: pd.DataFrame, envFactors: Sequence[str], n_bins: int = ENV_FACTOR_BINS) -> Tuple[pd.DataFrame, Dict[str, object]]:
    out = df.copy()
    metadata: Dict[str, object] = {}
    derived_cols = []

    for col in envFactors:
        if col not in out.columns:
            continue
        derived = f"{col}__envFactor"
        if is_numeric_series(out[col]):
            out[derived], meta = interval_labels(out[col], n_bins=n_bins)
            metadata[col] = meta or {"mode": "numeric"}
        else:
            out[derived] = out[col].astype(str)
            metadata[col] = {"mode": "categorical"}
        derived_cols.append(derived)

    if not derived_cols:
        out["envFactor"] = "overall"
    elif len(derived_cols) == 1:
        out["envFactor"] = out[derived_cols[0]].astype(str)
    else:
        out["envFactor"] = out[derived_cols].astype(str).agg(" | ".join, axis=1)

    out["envFactor"] = out["envFactor"].replace({"nan": pd.NA, "<NA>": pd.NA})
    return out, metadata

# Regression, monotonicity, function candidates

def slope_tolerance(x: Sequence[float], y: Sequence[float]) -> float:
    x_arr = np.asarray(x, dtype=float)
    y_arr = np.asarray(y, dtype=float)
    x_range = max(float(np.nanmax(x_arr) - np.nanmin(x_arr)), 1e-12)
    y_scale = max(float(np.nanmean(np.abs(y_arr))), 1e-12)
    return 0.01 * y_scale / x_range


def classify_trend_from_slope(slope: float, objective: str, tol: float) -> Tuple[str, str]:
    if not math.isfinite(float(slope)):
        return "not enough data", "not enough data"
    if abs(slope) <= tol:
        trend = "flat"
    elif slope > 0:
        trend = "increasing"
    else:
        trend = "decreasing"

    if objective == "maximize":
        effect = "beneficial" if trend == "increasing" else "prejudicial" if trend == "decreasing" else "neutral"
    elif objective == "minimize":
        effect = "beneficial" if trend == "decreasing" else "prejudicial" if trend == "increasing" else "neutral"
    else:
        effect = "unclassified"
    return trend, effect


def grouped_means(df: pd.DataFrame, x: str, y: str) -> pd.DataFrame:
    work = df[[x, y]].copy()
    work[x] = as_numeric(work[x])
    work[y] = as_numeric(work[y])
    work = work.dropna()
    if work.empty:
        return work
    return work.groupby(x, as_index=False)[y].mean().sort_values(x).reset_index(drop=True)


def regression_summary(df: pd.DataFrame, x: str, y: str, objective: str, envFactor: str = "overall") -> Dict[str, object]:
    g = grouped_means(df, x, y)
    if len(g) < 2:
        return {
            "envFactor": envFactor,
            "x": x,
            "y": y,
            "n_levels": int(len(g)),
            "slope": np.nan,
            "intercept": np.nan,
            "r2": np.nan,
            "trend": "not enough data",
            "effect": "not enough data",
            "x_min": float(g[x].min()) if len(g) else np.nan,
            "x_max": float(g[x].max()) if len(g) else np.nan,
            "y_min": float(g[y].min()) if len(g) else np.nan,
            "y_max": float(g[y].max()) if len(g) else np.nan,
        }

    x_arr = g[x].to_numpy(dtype=float)
    y_arr = g[y].to_numpy(dtype=float)
    slope, intercept = np.polyfit(x_arr, y_arr, 1)
    y_hat = slope * x_arr + intercept
    ss_res = float(np.sum((y_arr - y_hat) ** 2))
    ss_tot = float(np.sum((y_arr - np.mean(y_arr)) ** 2))
    r2 = np.nan if ss_tot <= 1e-12 else 1.0 - ss_res / ss_tot
    tol = slope_tolerance(x_arr, y_arr)
    trend, effect = classify_trend_from_slope(float(slope), objective, tol)
    return {
        "envFactor": envFactor,
        "x": x,
        "y": y,
        "n_levels": int(len(g)),
        "slope": float(slope),
        "intercept": float(intercept),
        "r2": float(r2) if math.isfinite(float(r2)) else np.nan,
        "trend": trend,
        "effect": effect,
        "x_min": float(np.min(x_arr)),
        "x_max": float(np.max(x_arr)),
        "y_min": float(np.min(y_arr)),
        "y_max": float(np.max(y_arr)),
    }


def regression_by_envFactor(df: pd.DataFrame, x: str, y: str, objective: str) -> pd.DataFrame:
    rows = []
    for env, sub in df.groupby("envFactor", dropna=True):
        rows.append(regression_summary(sub, x, y, objective, envFactor=str(env)))
    return pd.DataFrame(rows)


def monotonicity_table(df: pd.DataFrame, x: str, y: str, objective: str) -> pd.DataFrame:
    rows = []
    for env, sub in df.groupby("envFactor", dropna=True):
        reg = regression_summary(sub, x, y, objective, envFactor=str(env))
        rows.append(
            {
                "envFactor": str(env),
                "x": x,
                "y": y,
                "x_observed_range": f"[{fmt_num(reg['x_min'])}, {fmt_num(reg['x_max'])}]",
                "x_min": reg["x_min"],
                "x_max": reg["x_max"],
                "y_min": reg["y_min"],
                "y_max": reg["y_max"],
                "local_slope": reg["slope"],
                "trend": reg["trend"],
                "effect": reg["effect"],
                "n_levels": reg["n_levels"],
                "r2": reg["r2"],
            }
        )
    return pd.DataFrame(rows)


def local_step_monotonicity(df: pd.DataFrame, x: str, y: str, objective: str) -> pd.DataFrame:
    rows = []
    for env, sub in df.groupby("envFactor", dropna=True):
        g = grouped_means(sub, x, y)
        if len(g) < 2:
            rows.append(
                {
                    "envFactor": str(env),
                    "x": x,
                    "y": y,
                    "start_x": np.nan,
                    "end_x": np.nan,
                    "start_y": np.nan,
                    "end_y": np.nan,
                    "delta_y": np.nan,
                    "local_trend": "not enough data",
                    "effect": "not enough data",
                }
            )
            continue
        tol = slope_tolerance(g[x], g[y])
        for i in range(len(g) - 1):
            x0, x1 = float(g.iloc[i][x]), float(g.iloc[i + 1][x])
            y0, y1 = float(g.iloc[i][y]), float(g.iloc[i + 1][y])
            dy = y1 - y0
            trend, effect = classify_trend_from_slope(dy, objective, tol)
            rows.append(
                {
                    "envFactor": str(env),
                    "x": x,
                    "y": y,
                    "x_step": f"[{fmt_num(x0)}, {fmt_num(x1)}]",
                    "start_x": x0,
                    "end_x": x1,
                    "start_y": y0,
                    "end_y": y1,
                    "delta_y": dy,
                    "local_trend": trend,
                    "effect": effect,
                }
            )
    return pd.DataFrame(rows)


def design_matrix(df: pd.DataFrame, columns: Sequence[str], form: str) -> Tuple[np.ndarray, List[str], Dict[str, str]]:
    usable = []
    for c in columns:
        if c in df.columns and is_numeric_series(df[c]):
            usable.append(c)
    aliases = {c: sanitize_identifier(c) for c in usable}
    arrays = [np.ones(len(df), dtype=float)]
    terms = ["1"]

    for c in usable:
        arrays.append(as_numeric(df[c]).to_numpy(dtype=float))
        terms.append(aliases[c])

    if form in {"interaction", "quadratic"}:
        for i in range(len(usable)):
            for j in range(i + 1, len(usable)):
                ci, cj = usable[i], usable[j]
                arrays.append(as_numeric(df[ci]).to_numpy(dtype=float) * as_numeric(df[cj]).to_numpy(dtype=float))
                terms.append(f"{aliases[ci]}*{aliases[cj]}")

    if form == "quadratic":
        for c in usable:
            arrays.append(as_numeric(df[c]).to_numpy(dtype=float) ** 2)
            terms.append(f"{aliases[c]}^2")

    return np.column_stack(arrays), terms, aliases


def expression_from_fit(coefs: np.ndarray, terms: Sequence[str]) -> str:
    parts = []
    for coef, term in zip(coefs, terms):
        coef = float(coef)
        if not math.isfinite(coef) or abs(coef) < 1e-12:
            continue
        if term == "1":
            parts.append(f"{coef:.12g}")
        else:
            sign = "+" if coef >= 0 else "-"
            parts.append(f" {sign} {abs(coef):.12g}*{term}")
    return "".join(parts).strip() or "0.0"


def function_candidates(df: pd.DataFrame, x: str, y: str, envFactors: Sequence[str], min_r2: float, max_nrmse: float) -> pd.DataFrame:
    candidate_columns = [x] + [c for c in envFactors if c != x]
    work = df.copy()
    for c in candidate_columns + [y]:
        if c in work.columns:
            work[c] = as_numeric(work[c])
    work = work.dropna(subset=[c for c in candidate_columns + [y] if c in work.columns])

    rows = []
    if len(work) < 2:
        return pd.DataFrame(rows)

    y_arr = as_numeric(work[y]).to_numpy(dtype=float)
    y_range = max(float(np.nanmax(y_arr) - np.nanmin(y_arr)), 1e-12)
    y_mean = float(np.nanmean(y_arr))
    constant_rmse = float(np.sqrt(np.mean((y_arr - y_mean) ** 2)))
    constant_nrmse = constant_rmse / y_range
    constant_accepted = constant_nrmse <= max_nrmse
    rows.append(
        {
            "candidate": "constant",
            "accepted": bool(constant_accepted),
            "expression": f"{y_mean:.12g}",
            "r2": np.nan,
            "rmse": constant_rmse,
            "nrmse": constant_nrmse,
            "variable_map_json": "{}",
            "reason": "accepted as approximately constant" if constant_accepted else "not constant enough",
        }
    )

    for form in ["linear", "interaction", "quadratic"]:
        X, terms, aliases = design_matrix(work, candidate_columns, form=form)
        if X.shape[0] <= X.shape[1]:
            rows.append(
                {
                    "candidate": form,
                    "accepted": False,
                    "expression": "",
                    "r2": np.nan,
                    "rmse": np.nan,
                    "nrmse": np.nan,
                    "variable_map_json": json.dumps(aliases),
                    "reason": "not enough rows for this model complexity",
                }
            )
            continue
        try:
            coefs, *_ = np.linalg.lstsq(X, y_arr, rcond=None)
            pred = X @ coefs
            rmse = float(np.sqrt(np.mean((y_arr - pred) ** 2)))
            nrmse = rmse / y_range
            ss_res = float(np.sum((y_arr - pred) ** 2))
            ss_tot = float(np.sum((y_arr - np.mean(y_arr)) ** 2))
            r2 = np.nan if ss_tot <= 1e-12 else 1.0 - ss_res / ss_tot
            accepted = bool(math.isfinite(float(r2)) and r2 >= min_r2 and nrmse <= max_nrmse)
            rows.append(
                {
                    "candidate": form,
                    "accepted": accepted,
                    "expression": expression_from_fit(coefs, terms),
                    "r2": float(r2) if math.isfinite(float(r2)) else np.nan,
                    "rmse": rmse,
                    "nrmse": nrmse,
                    "variable_map_json": json.dumps(aliases),
                    "reason": "accepted" if accepted else f"requires r2>={min_r2} and nrmse<={max_nrmse}",
                }
            )
        except Exception as exc:
            rows.append(
                {
                    "candidate": form,
                    "accepted": False,
                    "expression": "",
                    "r2": np.nan,
                    "rmse": np.nan,
                    "nrmse": np.nan,
                    "variable_map_json": json.dumps(aliases),
                    "reason": str(exc),
                }
            )
    return pd.DataFrame(rows)


# Participant impact


def standardized_slope(df: pd.DataFrame, x: str, y: str) -> Tuple[float, float, float]:
    work = df[[x, y]].copy()
    work[x] = as_numeric(work[x])
    work[y] = as_numeric(work[y])
    work = work.dropna()
    if len(work) < 2:
        return np.nan, np.nan, np.nan
    x_arr = work[x].to_numpy(dtype=float)
    y_arr = work[y].to_numpy(dtype=float)
    if np.nanstd(x_arr) <= 1e-12 or np.nanstd(y_arr) <= 1e-12:
        return 0.0, 0.0, 0.0
    slope, _ = np.polyfit(x_arr, y_arr, 1)
    corr = float(np.corrcoef(x_arr, y_arr)[0, 1])
    std_impact = float(abs(slope) * (np.nanmax(x_arr) - np.nanmin(x_arr)) / max(np.nanmax(y_arr) - np.nanmin(y_arr), 1e-12))
    return float(slope), corr, std_impact


def participant_impact(df: pd.DataFrame, srp: str, objective: str) -> pd.DataFrame:
    rows = []
    for col in numeric_input_columns(df):
        if col == srp:
            continue
        slope, corr, impact = standardized_slope(df, col, srp)
        tol = 1e-12
        trend, effect = classify_trend_from_slope(slope, objective, tol)
        rows.append(
            {
                "participant": col,
                "srp": srp,
                "slope_if_participant_increases": slope,
                "pearson_corr": corr,
                "standardized_impact": impact,
                "trend_if_participant_increases": trend,
                "effect_if_participant_increases": effect,
                "rationale": f"Estimated from linear association between {col} and {srp} in the aggregated campaign CSV.",
            }
        )
    out = pd.DataFrame(rows)
    if out.empty:
        return out
    total = out["standardized_impact"].replace([np.inf, -np.inf], np.nan).fillna(0).sum()
    if total > 0:
        out["weight_sum_norm"] = out["standardized_impact"].fillna(0) / total
    else:
        out["weight_sum_norm"] = 1.0 / len(out)
    return out.sort_values("standardized_impact", ascending=False).reset_index(drop=True)

# Main influence analysis

def analyze_influence(
    df_raw: pd.DataFrame,
    campaign_name: str,
    csv_path: Path,
    spec: InfluenceSpec,
    out_dir: Path,
) -> Dict[str, object]:
    ensure_dir(out_dir)

    df_valid = keep_valid_metric_rows(df_raw, spec.srp)
    used_envFactors = [c for c in spec.envFactors if c in df_valid.columns]
    prepared, envFactor_metadata = prepare_envFactors(df_valid, used_envFactors, n_bins=ENV_FACTOR_BINS)

    if spec.participant not in prepared.columns or spec.srp not in prepared.columns:
        raise ValueError(f"Missing required columns for influence {spec.participant} -> {spec.srp}")

    prepared[spec.participant] = as_numeric(prepared[spec.participant])
    prepared[spec.srp] = as_numeric(prepared[spec.srp])
    prepared = prepared.dropna(subset=[spec.participant, spec.srp])

    prepared.to_csv(out_dir / "prepared_data.csv", index=False)

    overall = pd.DataFrame([regression_summary(prepared, spec.participant, spec.srp, spec.objective, envFactor="overall")])
    by_env = regression_by_envFactor(prepared, spec.participant, spec.srp, spec.objective)
    mono = monotonicity_table(prepared, spec.participant, spec.srp, spec.objective)
    local = local_step_monotonicity(prepared, spec.participant, spec.srp, spec.objective)
    funcs = function_candidates(prepared, spec.participant, spec.srp, used_envFactors, min_r2=MIN_R2, max_nrmse=MAX_NRMSE)
    impact = participant_impact(prepared, spec.srp, spec.objective)

    overall.to_csv(out_dir / "overall_regression.csv", index=False)
    by_env.to_csv(out_dir / "regression_by_envFactor.csv", index=False)
    mono.to_csv(out_dir / "monotonicity_table.csv", index=False)
    local.to_csv(out_dir / "local_step_monotonicity.csv", index=False)
    funcs.to_csv(out_dir / "function_candidates.csv", index=False)
    impact.to_csv(out_dir / "participant_impact.csv", index=False)

    accepted_function = None
    if not funcs.empty and "accepted" in funcs.columns:
        accepted = funcs[funcs["accepted"] == True]
        if not accepted.empty:
            best = accepted.iloc[0].to_dict()
            accepted_function = {
                "candidate": best.get("candidate"),
                "expression": best.get("expression"),
                "r2": best.get("r2"),
                "nrmse": best.get("nrmse"),
                "variableMap": json.loads(best.get("variable_map_json", "{}") or "{}"),
            }
    if accepted_function:
        (out_dir / "accepted_function.txt").write_text(str(accepted_function["expression"]), encoding="utf-8")
    else:
        (out_dir / "accepted_function.txt").write_text(
            "No analytic expression accepted by the configured thresholds.\n",
            encoding="utf-8",
        )

    feedback = {
        "schemaVersion": "simple-campaign-csv-influence-analysis-v1",
        "campaign": campaign_name,
        "sourceCsv": str(csv_path),
        "influence": {
            "name": spec.name,
            "participant": spec.participant,
            "srp": spec.srp,
            "objective": spec.objective,
            "envFactors": used_envFactors,
        },
        "envFactorMetadata": envFactor_metadata,
        "outputs": {
            "monotonicityTable": "monotonicity_table.csv",
            "localStepMonotonicity": "local_step_monotonicity.csv",
            "overallRegression": "overall_regression.csv",
            "regressionByEnvFactor": "regression_by_envFactor.csv",
            "functionCandidates": "function_candidates.csv",
            "participantImpact": "participant_impact.csv",
        },
        "acceptedFunction": accepted_function,
    }
    write_json(out_dir / "influence_feedback.json", feedback)

    summary_lines = [
        f"# Influence analysis: {spec.name}",
        "",
        f"Campaign: `{campaign_name}`",
        f"Source CSV: `{csv_path}`",
        f"Participant: `{spec.participant}`",
        f"SRP: `{spec.srp}`",
        f"Objective: `{spec.objective}`",
        f"EnvFactors: `{', '.join(used_envFactors) if used_envFactors else 'overall'}`",
        "",
        "## Monotonicity table summary",
        "",
    ]
    if mono.empty:
        summary_lines.append("No monotonicity table could be computed.")
    else:
        for _, row in mono.iterrows():
            summary_lines.append(
                f"- {row['envFactor']}: {row['trend']} / {row['effect']} "
                f"over {row['x_observed_range']} (slope={fmt_num(row['local_slope'])})"
            )
    summary_lines += ["", "## Accepted analytic function", ""]
    summary_lines.append(f"`{accepted_function['expression']}`" if accepted_function else "No analytic expression accepted by the configured thresholds.")
    (out_dir / "analysis_summary.md").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    return {
        "campaign": campaign_name,
        "source_csv": str(csv_path),
        "influence_name": spec.name,
        "participant": spec.participant,
        "srp": spec.srp,
        "objective": spec.objective,
        "envFactors": ";".join(used_envFactors),
        "output_dir": str(out_dir),
        "n_raw_rows": int(len(df_raw)),
        "n_valid_rows": int(len(df_valid)),
        "n_monotonicity_rows": int(len(mono)),
        "accepted_function": accepted_function["candidate"] if accepted_function else "",
    }


def analyze_campaign_csv(campaign_name: str, csv_path: Path, campaign_out_dir: Path) -> List[Dict[str, object]]:
    ensure_dir(campaign_out_dir)
    df = pd.read_csv(csv_path)
    influences = infer_influences(df, all_pairs=ALL_PAIRS)

    manifest_rows: List[Dict[str, object]] = []
    if not influences:
        (campaign_out_dir / "campaign_summary.md").write_text(
            f"# {campaign_name}\n\nNo analyzable influence was inferred from `{csv_path}`.\n",
            encoding="utf-8",
        )
        return manifest_rows

    for spec in influences:
        influence_dir = campaign_out_dir / safe_dir_name(f"{spec.participant}__to__{spec.srp}")
        try:
            row = analyze_influence(
                df_raw=df,
                campaign_name=campaign_name,
                csv_path=csv_path,
                spec=spec,
                out_dir=influence_dir,
            )
            manifest_rows.append(row)
        except Exception as exc:
            ensure_dir(influence_dir)
            (influence_dir / "ERROR.txt").write_text(str(exc) + "\n", encoding="utf-8")
            manifest_rows.append(
                {
                    "campaign": campaign_name,
                    "source_csv": str(csv_path),
                    "influence_name": spec.name,
                    "participant": spec.participant,
                    "srp": spec.srp,
                    "objective": spec.objective,
                    "envFactors": ";".join(spec.envFactors),
                    "output_dir": str(influence_dir),
                    "error": str(exc),
                }
            )

    pd.DataFrame(manifest_rows).to_csv(campaign_out_dir / "influences_manifest.csv", index=False)

    lines = [
        f"# Campaign analysis: {campaign_name}",
        "",
        f"Source CSV: `{csv_path}`",
        f"Influences analyzed: {len(manifest_rows)}",
        "",
    ]
    for row in manifest_rows:
        status = "ERROR" if row.get("error") else "OK"
        lines.append(f"- {status}: `{row['participant']}` -> `{row['srp']}` in `{Path(row['output_dir']).name}`")
    (campaign_out_dir / "campaign_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    return manifest_rows

# Main

def main() -> int:
    if len(sys.argv) > 2:
        raise SystemExit("Usage: python3 functionalCampaignAnalyzer.py [SimulationCampaignFolder]")

    simulation_campaign_dir = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else Path.cwd().resolve()
    functional_results_dir = infer_functional_results_dir(simulation_campaign_dir)
    output_root = infer_output_dir(simulation_campaign_dir)
    ensure_dir(output_root)

    csv_entries = find_aggregated_csvs(functional_results_dir)
    if not csv_entries:
        raise SystemExit(f"No aggregated campaign CSV files found in {functional_results_dir}")

    global_manifest: List[Dict[str, object]] = []
    for campaign_name, csv_path in csv_entries:
        campaign_out = output_root / safe_dir_name(campaign_name)
        rows = analyze_campaign_csv(campaign_name, csv_path, campaign_out)
        global_manifest.extend(rows)

    pd.DataFrame(global_manifest).to_csv(output_root / "analysis_manifest.csv", index=False)
    write_json(
        output_root / "analysis_manifest.json",
        {
            "outputRoot": str(output_root),
            "campaignCount": len(csv_entries),
            "influenceCount": len(global_manifest),
            "entries": global_manifest,
        },
    )

    print(f"Analyzed {len(csv_entries)} campaign CSV file(s).")
    print(f"Influence analyses generated: {len(global_manifest)}")
    print(f"Results written to: {output_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
