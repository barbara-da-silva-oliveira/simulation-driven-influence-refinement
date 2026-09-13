""" Preparation masks, and configuration grouping."""

import numpy as np
import pandas as pd
from .campaigns import NUMERIC_VALID, SRPS


def finite(series):
    """Return a numeric Series; unparseable values and infinities become NaN.
    """
    return pd.to_numeric(series, errors="coerce").replace([np.inf, -np.inf], np.nan)


def numeric_mask(frame, metric):
    """Return a Boolean Series selecting finite observations with usable statuses.
    ``frame`` is a run or design table; ``metric`` is one column name.
    """
    if metric not in frame:
        return pd.Series(False, index=frame.index)
    mask = finite(frame[metric]).notna()
    validity = metric + "_validity"
    if validity in frame:
        mask &= frame[validity].astype(str).str.strip().str.upper().isin(NUMERIC_VALID)
    elif "aggregate_status" in frame:
        mask &= frame.aggregate_status.astype(str).isin(NUMERIC_VALID)
    if "aggregate_status" in frame:
        mask &= ~frame.aggregate_status.astype(str).str.startswith("INVALID")
    if "run_validity" in frame:
        mask &= frame.run_validity.eq("VALID_RUN")
    if "status" in frame:
        mask &= frame.status.eq("OK")
    return mask


def is_constant(values):
    """Return whether a nonempty numeric vector has negligible observed range."""
    values = np.asarray(values, dtype=float)
    if not len(values):
        return False
    return np.ptp(values) <= 1e-12 * max(1.0, float(np.max(np.abs(values))))


def stable_groups(frame, columns):
    """Return one integer group per row, based on the listed numeric columns.
    """
    keys = frame[list(columns)].apply(lambda row: tuple(
        "<missing>" if pd.isna(v) else format(float(v), ".12g") for v in row), axis=1)
    return pd.factorize(keys, sort=True)[0]


def valid_model_data(data, features, srp):
    """Return a copied, indexed table with complete usable inputs and response.
    ``features`` is a sequence of column names; ``srp`` is the output column.
    """
    if any(x not in data for x in (*features, srp)):
        return data.iloc[0:0].copy()
    work = data.loc[numeric_mask(data, srp)].copy()
    for feature in features:
        if feature in SRPS:
            work = work.loc[numeric_mask(work, feature)].copy()
    for col in (*features, srp):
        work[col] = finite(work[col])
    return work.dropna(subset=[*features, srp]).reset_index(drop=True)
