"""Group-validation and model-selection algorithms; return in-memory evidence."""

from sklearn.model_selection import LeaveOneGroupOut
import numpy as np
import pandas as pd
from .config import MAX_NRMSE, MIN_R2
from .models import TERM_BUILDERS, FitError, fit_polynomial, model_expression, powers_for, predict_polynomial, score_predictions
from .preparation import stable_groups


def cross_validate_form(X, y, groups, form):

    prediction = np.full(len(y), np.nan)
    fold_id = np.full(len(y), -1)
    if len(np.unique(groups)) < 3:
        return prediction, fold_id, "fewer than three independent validation groups"
    for fold, (train, test) in enumerate(LeaveOneGroupOut().split(X, y, groups)):
        try:
            model = fit_polynomial(X[train], y[train], form)
            prediction[test] = predict_polynomial(model, X[test])
            fold_id[test] = fold
        except FitError as exc:
            return prediction, fold_id, str(exc)
    return prediction, fold_id, ""


def candidate_analysis(frame, features, srp, groups, min_r2=MIN_R2, max_nrmse=MAX_NRMSE):
    X, y = frame[list(features)].to_numpy(float), frame[srp].to_numpy(float)
    rows, models, predictions = [], {}, {}
    for form in TERM_BUILDERS:
        row = {"candidate": form, "n_designs": len(y), "n_validation_groups": len(np.unique(groups)),
               "n_coefficients": len(powers_for(len(features), form)), "status": "unavailable",
               "cv_meets_thresholds": False, "accepted": False, "train_r2": np.nan,
               "cv_r2": np.nan, "cv_rmse": np.nan, "cv_nrmse": np.nan}
        try:
            model = fit_polynomial(X, y, form)
            pred = predict_polynomial(model, X)
            training = score_predictions(y, pred)
            row.update({"status": "fit_only", "expression": model_expression(model, features),
                        "rank": model["rank"], "condition_number": model["condition_number"],
                        **{"train_" + key: val for key, val in training.items()}})
            cv_pred, folds, reason = cross_validate_form(X, y, groups, form)
            row["reason"] = reason
            if np.isfinite(cv_pred).all():
                cv = score_predictions(y, cv_pred)
                row.update({"status": "cross_validated", **{"cv_" + key: val for key, val in cv.items()}})
                row["cv_meets_thresholds"] = bool(cv["r2"] >= min_r2 and cv["nrmse"] <= max_nrmse)
                predictions[form] = (cv_pred, folds)
            models[form] = model
        except FitError as exc:
            row["reason"] = str(exc)
        rows.append(row)
    return pd.DataFrame(rows), models, predictions


def select_candidate(candidates):
    valid = candidates[candidates.status.eq("cross_validated")]
    if valid.empty:
        return None
    accepted = valid[valid.cv_meets_thresholds]
    if len(accepted):
        return str(accepted.sort_values(["n_coefficients", "cv_rmse"]).iloc[0].candidate)
    return str(valid.sort_values(["cv_rmse", "n_coefficients"]).iloc[0].candidate)


def nested_validation(frame, features, srp, groups, min_r2, max_nrmse):
    X, y = frame[list(features)].to_numpy(float), frame[srp].to_numpy(float)
    rows = []
    if len(np.unique(groups)) < 4:
        return pd.DataFrame(), {"status": "insufficient groups"}
    for fold, (train, test) in enumerate(LeaveOneGroupOut().split(X, y, groups)):
        inner, _, _ = candidate_analysis(frame.iloc[train], features, srp, groups[train], min_r2, max_nrmse)
        chosen = select_candidate(inner)
        if chosen is None:
            return pd.DataFrame(rows), {"status": "inner validation unavailable"}
        model = fit_polynomial(X[train], y[train], chosen)
        prediction = predict_polynomial(model, X[test])
        for idx, value in zip(test, prediction):
            rows.append({"design_id": frame.iloc[idx].design_id, "group": groups[idx],
                         "outer_fold": fold, "selected_form_in_training": chosen,
                         "observed": y[idx], "predicted": value})
    output = pd.DataFrame(rows)
    return output, {"status": "completed", **score_predictions(output.observed, output.predicted),
                   "interpretation": "internal nested validation of selection procedure; not an external test"}

def analysis_groups(frame, features, spec):

    if spec["code"] == "C":
        if "representative_id" not in frame:
            raise ValueError("C requires representative groups for primary model validation.")
        return frame.representative_id.to_numpy(), "leave_one_upstream_representative_out"
    return stable_groups(frame, features), "leave_one_physical_configuration_out"
