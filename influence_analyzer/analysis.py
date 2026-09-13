"""Orchestrate one response analysis and export its evidence."""

import numpy as np
from .io import write_csv, write_json
from .models import model_expression, raw_model_terms
from .plotting import response_plots
from .preparation import is_constant, valid_model_data
from .validation import analysis_groups, candidate_analysis, nested_validation, select_candidate


def response_analysis(data, features, srp, spec, output, settings, primary=False, plots=False):
    """Analyze one response, export its evidence, and return a summary dictionary."""
    output.mkdir(parents=True, exist_ok=True)
    frame = valid_model_data(data, features, srp)
    metadata = {"srp": srp, "features": features, "n_usable_designs": len(frame),
                "role": "primary_target" if primary else "exploratory_response", "accepted": False}
    write_csv(output / "prepared_data.csv", frame)
    if not len(frame):
        metadata["status"] = "no_valid_complete_observations_or_missing_participants"
        write_json(output / "response_summary.json", metadata)
        return metadata
    groups, validation = analysis_groups(frame, features, spec)
    metadata.update({"validation": validation, "n_validation_groups": len(np.unique(groups))})
    if is_constant(frame[srp]):
        metadata.update({"status": "constant_response", "observed_value": float(frame[srp].iloc[0]),
                         "interpretation": "constant only in observed data; no claim of global constancy"})
        write_json(output / "response_summary.json", metadata)
        return metadata
    candidates, models, predictions = candidate_analysis(frame, features, srp, groups, settings['min_r2'], settings['max_nrmse'])
    selected = select_candidate(candidates)
    metadata.update({"status": "analyzed", "selected_diagnostic_candidate": selected})
    if primary:
        nested_rows, nested_metrics = nested_validation(frame, features, srp, groups, settings['min_r2'], settings['max_nrmse'])
        write_csv(output / "nested_cv_predictions.csv", nested_rows)
        write_json(output / "nested_cv_metrics.json", nested_metrics)
        metadata["nested_validation"] = nested_metrics
    if selected is not None:
        result = candidates[candidates.candidate.eq(selected)].iloc[0]
        metadata.update({"cv_r2": result.cv_r2, "cv_rmse": result.cv_rmse, "cv_nrmse": result.cv_nrmse,
                         "train_r2": result.train_r2, "cv_meets_thresholds": bool(result.cv_meets_thresholds)})
        nested_ok = (metadata.get("nested_validation", {}).get("r2", -np.inf) >= settings['min_r2'] and
                     metadata.get("nested_validation", {}).get("nrmse", np.inf) <= settings['max_nrmse'])
        metadata["accepted"] = bool(primary and result.cv_meets_thresholds and nested_ok)
        candidates.loc[candidates.candidate.eq(selected), "accepted"] = metadata["accepted"]
        candidate = models[selected]
        raw_terms, raw_expression = raw_model_terms(candidate, features)
        candidate_info = {**candidate, "features": features, "output_srp": srp,
                          "accepted_for_primary_refinement": metadata["accepted"],
                          "expression_language": "Python arithmetic; ** means exponentiation",
                          "expression": model_expression(candidate, features),
                          "raw_expression": raw_expression,
                          "observed_domain": {x: [float(frame[x].min()), float(frame[x].max())] for x in features},
                          "domain_note": "marginal bounds do not imply full factorial coverage, observed joint support only"}
        write_json(output / "selected_model.json", candidate_info)
        write_csv(output / "selected_model_coefficients.csv", raw_terms)
        metadata["selected_expression_raw"] = raw_expression
        (output / "selected_function.txt").write_text(
            ("Accepted internally for primary refinement.\n" if metadata["accepted"] else
             "Diagnostic candidate only; not accepted for primary refinement.\n") +
            raw_expression + "\n\nNumerically scaled equivalent:\n" + model_expression(candidate, features) + "\n", encoding="utf-8")
        pred_rows = []
        for form, (values, folds) in predictions.items():
            for i, value in enumerate(values):
                pred_rows.append({"design_id": frame.iloc[i].design_id, "validation_group": groups[i],
                                  "fold": folds[i], "candidate": form, "observed": frame.iloc[i][srp],
                                  "predicted": value, "residual": frame.iloc[i][srp] - value})
        write_csv(output / "cv_predictions.csv", pred_rows)
    write_csv(output / "function_candidates.csv", candidates)
    if plots:
        response_plots(frame, features, srp, predictions, selected, output, f"Campaign {spec['code']}: {srp}")
    write_json(output / "response_summary.json", metadata)
    return metadata
