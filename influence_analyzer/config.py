"""Numerical parameters for the analysis. Modify SETTINGS to change a calculation."""

import math

VERSION = "2.3.0"
SEED = 20260910
MIN_R2 = 0.7
MAX_NRMSE = 0.15
MIN_RESIDUAL_DF = 2
MIN_TREND_DESIGNS = 6
MIN_TREND_LEVELS = 4
BOOTSTRAPS = 400

SETTINGS = {
    "min_r2": MIN_R2,
    "max_nrmse": MAX_NRMSE,
    "bootstraps": BOOTSTRAPS,
    "no_plots": False,
}

def validate_settings(settings):
    """Validate the settings before creating result files."""
    if not isinstance(settings["bootstraps"], int) or settings["bootstraps"] < 100:
        raise ValueError("Use an integer number of bootstrap draws of at least 100.")
    if not math.isfinite(settings["min_r2"]) or not 0 <= settings["min_r2"] <= 1:
        raise ValueError("The R² threshold must be finite and in [0, 1].")
    if not math.isfinite(settings["max_nrmse"]) or settings["max_nrmse"] <= 0:
        raise ValueError("The NRMSE threshold must be finite and positive.")
    if not isinstance(settings["no_plots"], bool):
        raise ValueError("no_plots must be a Boolean.")
