"""Participant importance and association estimators. Not causal contributions."""

from .campaigns import participants, participant_role
from scipy import stats
import numpy as np
import pandas as pd
from .config import MIN_TREND_DESIGNS, MIN_TREND_LEVELS, SEED
from .models import FitError, fit_polynomial
from .preparation import is_constant


def resample_groups(groups, rng):
    """Return row indices for a bootstrap draw of whole groups with replacement.

    Draw as many group IDs as distinct groups; include every row of each chosen
    group, repeating its rows when that group is selected more than once.
    """
    unique = np.unique(groups)
    return np.concatenate([np.flatnonzero(groups == group)
                           for group in rng.choice(unique, size=len(unique), replace=True)])


def direction(slope, objective, tolerance=0.0):
    """Translate a signed slope into (trend, objective effect), without inference.

    The objective is maximize, minimize, or unclassified. The caller must check
    statistical support separately; a point-estimate sign is not proof.
    """
    if not np.isfinite(slope):
        return "unavailable", "unclassified"
    trend = "flat" if abs(slope) <= tolerance else "increasing" if slope > 0 else "decreasing"
    effect = "unclassified"
    if objective in ("maximize", "minimize"):
        if trend == "flat":
            effect = "neutral"
        elif (trend == "increasing") == (objective == "maximize"):
            effect = "beneficial"
        else:
            effect = "prejudicial"
    return trend, effect


def participant_impact(frame, spec, groups, n_bootstrap):
    """Joint linear partial slopes; NOT Morris, Sobol, or causal contributions.

    importance_i = abs(beta_i) * observed_range(x_i) / observed_range(y)
    relative_importance_i = importance_i / sum(importance)
    All participants of this Influence enter the same regression.
    """
    features, srp = participants(spec), spec['output_srp']
    if len(frame) < 6 or is_constant(frame[srp]):
        return pd.DataFrame([{"participant": x, "status": "insufficient_or_constant_response"} for x in features])
    X, y = frame[list(features)].to_numpy(float), frame[srp].to_numpy(float)
    try:
        model = fit_polynomial(X, y, "linear")
    except FitError as exc:
        return pd.DataFrame([{"participant": x, "status": str(exc)} for x in features])
    slopes = model["coefficients"][1:] / model["scale"]
    ranges = np.ptp(X, axis=0)
    impact = np.abs(slopes) * ranges / np.ptp(y)
    relative = impact / impact.sum() if impact.sum() > 1e-12 else np.zeros(len(impact))
    slope_samples, impact_samples = [], []
    rng = np.random.default_rng(SEED)
    for _ in range(n_bootstrap):
        idx = resample_groups(groups, rng)
        try:
            fit = fit_polynomial(X[idx], y[idx], "linear")
            beta = fit["coefficients"][1:] / fit["scale"]
            slope_samples.append(beta)
            strength = np.abs(beta) * ranges / np.ptp(y)
            impact_samples.append(strength / strength.sum() if strength.sum() > 1e-12 else np.zeros(len(strength)))
        except FitError:
            continue
    slope_ci = np.full((2, len(features)), np.nan)
    importance_ci = slope_ci.copy()
    if len(slope_samples) >= max(50, n_bootstrap // 2):
        slope_ci = np.quantile(slope_samples, [0.025, 0.975], axis=0)
        importance_ci = np.quantile(impact_samples, [0.025, 0.975], axis=0)
    rows = []
    for j, feature in enumerate(features):
        trend, effect = direction(slopes[j], spec['objective'])
        stable = bool(slope_ci[0, j] > 0 or slope_ci[1, j] < 0)
        rows.append({"participant": feature, "participant_type": participant_role(spec, feature), "srp": srp,
                     "status": "descriptive_joint_linear_estimate", "partial_slope": slopes[j],
                     "slope_ci95_low": slope_ci[0, j], "slope_ci95_high": slope_ci[1, j],
                     "observed_x_range": ranges[j], "range_scaled_impact": impact[j],
                     "relative_importance": relative[j], "importance_ci95_low": importance_ci[0, j],
                     "importance_ci95_high": importance_ci[1, j], "point_estimate_trend": trend,
                     "direction_supported_by_bootstrap": stable,
                     "effect_if_participant_increases": effect if stable else "undetermined",
                     "objective_policy": spec['objective'], "n_designs": len(y),
                     "n_groups": len(np.unique(groups)), "bootstrap_successes": len(slope_samples),
                     "method": "OLS with all declared participants; group bootstrap; observed-range scaling",
                     "scope": "sampled campaign only; not a causal or variance contribution"})
    return pd.DataFrame(rows).sort_values("relative_importance", ascending=False)


def association_row(frame, feature, srp, objective="unclassified", groups=None, bootstraps=0):
    """Return descriptive bivariate slope/correlations and optional direction evidence.

    Unlike participant_impact, this regression has one explanatory variable.
    Bootstrap direction checks need sufficient designs, levels and groups.
    The default zero draws computes descriptive associations only. ``r2`` here
    is squared Pearson correlation, not cross-validated predictive R2.
    """
    x, y = frame[feature].to_numpy(float), frame[srp].to_numpy(float)
    row = {"participant": feature, "srp": srp, "n_designs": len(frame),
           "n_levels": len(np.unique(x)), "slope": np.nan, "pearson_r": np.nan,
           "spearman_rho": np.nan, "r2": np.nan, "trend": "undetermined",
           "effect": "undetermined", "status": "insufficient_data"}
    if not len(x):
        return row
    row.update({"x_min": x.min(), "x_max": x.max(), "y_min": y.min(), "y_max": y.max()})
    if is_constant(x):
        row["status"] = "constant_participant"
        return row
    if is_constant(y):
        row.update({"status": "constant_response", "slope": 0.0, "trend": "flat_in_observations"})
        return row
    if len(x) < 3:
        return row
    regression = stats.linregress(x, y)
    slope = regression.slope
    row.update({"slope": slope, "pearson_r": regression.rvalue,
                "spearman_rho": stats.spearmanr(x, y).statistic,
                "r2": regression.rvalue ** 2, "status": "descriptive_association"})
    tolerance = .01 * max(float(np.mean(np.abs(y))), 1e-12) / np.ptp(x)
    row["slope_tolerance"] = tolerance
    row["point_estimate_trend"], _ = direction(slope, objective, tolerance)
    lower, upper = np.nan, np.nan
    if groups is None:
        groups = np.arange(len(x))
    row["n_groups"] = len(np.unique(groups))
    if len(x) >= MIN_TREND_DESIGNS and len(np.unique(x)) >= MIN_TREND_LEVELS and len(np.unique(groups)) >= 4:
        rng, slopes = np.random.default_rng(SEED), []
        for _ in range(bootstraps):
            idx = resample_groups(groups, rng)
            if not is_constant(x[idx]):
                slopes.append(stats.linregress(x[idx], y[idx]).slope)
        if len(slopes) >= max(50, bootstraps // 2):
            lower, upper = np.quantile(slopes, [.025, .975])
            if lower > tolerance or upper < -tolerance:
                row["trend"], row["effect"] = direction(slope, objective, tolerance)
                row["status"] = "directional_association_supported"
            elif lower >= -tolerance and upper <= tolerance:
                row["trend"] = "approximately_flat_association"
                row["status"] = "small_effect_interval"
            else:
                row["status"] = "direction_not_resolved"
    row.update({"slope_ci95_low": lower, "slope_ci95_high": upper,
                "interpretation": "association within stated conditions; not proof of monotonicity"})
    return row
