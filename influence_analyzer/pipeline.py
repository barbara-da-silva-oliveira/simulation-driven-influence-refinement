"""Application orchestration across campaigns; coordinates analysis and outputs"""

from .campaigns import participants, participant_role
from datetime import datetime
from datetime import timezone
import matplotlib
import numpy as np
import pandas as pd
import scipy
import sklearn
import sys
from .analysis import response_analysis
from .config import MIN_RESIDUAL_DF, SEED, VERSION, validate_settings
from .control import control_diagnostics
from .importance import participant_impact
from .io import load_campaign, locate_campaigns, package_source_hashes, read_csv, sha256, write_csv, write_json
from .monotonicity import monotonicity_tables
from .preparation import finite, numeric_mask, stable_groups, valid_model_data
from .quality import quality_tables, sampling_table
from .validation import analysis_groups, candidate_analysis


def analyze_campaign(spec, path, output, settings):

    output.mkdir(parents=True, exist_ok=True)
    data, raw, checks, warnings = load_campaign(path, spec)
    availability, replication, reconciliation = quality_tables(data, raw, spec)
    write_csv(output / "prepared_designs.csv", data)
    write_csv(output / "srp_availability.csv", availability)
    write_csv(output / "replicate_statistics.csv", replication)
    weights_path = path.with_name("campaign_wlhs_internal_weights.csv")
    recorded_weights = read_csv(weights_path) if weights_path.exists() else None
    write_csv(output / "sampling_audit.csv", sampling_table(recorded_weights, data, spec, weights_path.name))
    if len(reconciliation) and not reconciliation.match.all():
        raise ValueError("Aggregate/raw discrepancies found. Measurements not replaced.")
    if raw is not None:
        for design_id, sub in raw.groupby("design_id"):
            row = data.set_index("design_id").loc[design_id]
            for col, actual in (("n_target_replicates", len(sub)),
                                ("n_valid_replicates", int(sub.run_validity.eq("VALID_RUN").sum()))):
                if col in row and int(row[col]) != actual:
                    warnings.append(f"Design {design_id}: {col}={row[col]}, raw count={actual}.")
        completed = raw.loc[numeric_mask(raw, "completed"), "completed"]
        checks.append({"check": "recorded_completion", "status": "OBSERVED",
                       "details": f"{int(completed.sum())}/{len(completed)} valid runs marked completed by the evaluator"})
    checks.append({"check": "aggregate_reconciliation", "status": "OK" if len(reconciliation) else "UNAVAILABLE",
                   "details": f"{len(reconciliation)} metric/design values compared"})
    error_files = len(list(path.parent.glob("design_*/error_attempt*.txt")))
    if error_files:
        warnings.append(f"{error_files} historical error files coexist with final run summaries; "
                        "these files alone do not identify failed final replicates or retry counts.")

    primary_dir = output / "primary_results"
    primary = response_analysis(data, participants(spec), spec['output_srp'], spec, primary_dir,
                                settings, primary=True, plots=not settings['no_plots'])
    frame = valid_model_data(data, participants(spec), spec['output_srp'])
    if len(frame) and primary.get("status") == "analyzed":
        groups, _ = analysis_groups(frame, participants(spec), spec)
        impact = participant_impact(frame, spec, groups, settings['bootstraps'])
        write_csv(primary_dir / "participant_impact.csv", impact)
        # mono, steps = monotonicity_tables(frame, spec, settings['bootstraps'])
        mono, steps = monotonicity_tables(frame, spec, settings['bootstraps'])
        write_csv(primary_dir / "monotonicity_table.csv", mono)
        # write_csv(primary_dir / "local_step_monotonicity.csv", steps)
        # write_csv(primary_dir / "participant_correlations.csv", frame[list(participants(spec))].corr().rename_axis("participant").reset_index())
        if "relative_importance" in impact:
            primary["participant_importance"] = impact[["participant", "relative_importance", "partial_slope",
                                                         "slope_ci95_low", "slope_ci95_high", "importance_ci95_low",
                                                         "importance_ci95_high"]].to_dict("records")
        if spec['code'] == "C":
            # A second, different question: unseen angular-gain levels in known representatives.
            w_groups = stable_groups(frame, ("w_gain",))
            candidates_w, _, _ = candidate_analysis(frame, participants(spec), spec['output_srp'],
                                                    w_groups, settings['min_r2'], settings['max_nrmse'])
            write_csv(primary_dir / "validation_leave_one_w_level_out.csv", candidates_w)

    association_rows= []
    # Retain physical cross-effects in C 
    if spec['code'] == "C":
        control_diagnostics(data, spec, output, settings)
    summary = {"campaign": spec['code'], "source_campaign_folder": path.parent.name, "influence": spec,
               "n_designs": len(data), "n_runs": len(raw) if raw is not None else None,
               "n_representatives": data.representative_id.nunique() if "representative_id" in data else None,
               "n_joint_cells": data.joint_cell.nunique() if "joint_cell" in data else None,
               "primary": primary, "warnings": warnings,
               "scope": "functional analysis of supplied summary CSVs"}
    write_json(output / "campaign_summary.json", summary)
    write_json(primary_dir / "influence_feedback.json", {
        "schemaVersion": "functional-campaign-analysis-v2", "status": "analysis_proposal",
        "campaign": spec['code'], "influence": spec,
        "acceptedFunction": primary.get("selected_diagnostic_candidate") if primary.get("accepted") else None,
        "outputs": {"monotonicityTable": "monotonicity_table.csv", "participantImpact": "participant_impact.csv",
                    "functionCandidates": "function_candidates.csv"},
        "note": "Analysis evidence."})
    return summary, availability, pd.DataFrame(association_rows)


def run_analysis(source, output, settings):
    validate_settings(settings)
    root, entries = locate_campaigns(source)
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output directory is not empty. Choose a fresh output folder to avoid mixing analysis versions.")
    output.mkdir(parents=True, exist_ok=True)
    inventory, manifest = [], []
    campaign_folders = [root] if (root / "campaign_summary_design_aggregated.csv").exists() else sorted(root.glob("campaign_*"))
    for folder in campaign_folders:
        inventory.append({"folder": folder.name,
                          "status": "executed_campaign" if (folder / "campaign_summary_design_aggregated.csv").exists()
                          else "metadata_only_no_aggregate"})
        for file in sorted(folder.glob("*.csv")):
            manifest.append({"relative_path": str(file.relative_to(root)), "sha256": sha256(file), "bytes": file.stat().st_size})
    write_json(output / "source_manifest.json", manifest)
    write_csv(output / "campaign_inventory.csv", inventory)
    summaries, availability, associations, errors = [], [], [], []
    for spec, path in entries:
        print(f"Analyzing campaign {spec['code']}: {path.parent.name}", flush=True)
        try:
            summary, avail, assoc = analyze_campaign(spec, path, output / path.parent.name, settings)
            summaries.append(summary)
            availability.append(avail)
            associations.append(assoc)
        except (ValueError, KeyError, OSError) as exc:
            errors.append({"campaign": spec['code'], "folder": path.parent.name, "error": str(exc)})
            write_json(output / path.parent.name / "ERROR.json", errors[-1])
            print(f"Campaign {spec['code']} failed: {exc}", file=sys.stderr, flush=True)
    all_availability = pd.concat(availability, ignore_index=True) if availability else pd.DataFrame()
    if not summaries:
        write_json(output / "errors.json", errors)
        raise ValueError("No campaigns could be analyzed; see errors.json.")
    write_csv(output / "all_srp_availability.csv", all_availability)
    write_csv(output / "all_srp_associations.csv", pd.concat(associations, ignore_index=True))
    write_csv(output / "primary_summary.csv", [{"campaign": s["campaign"], "n_designs": s["n_designs"],
               "n_runs": s["n_runs"], "target_srp": s["influence"]["output_srp"],
               "selected_candidate": s["primary"].get("selected_diagnostic_candidate"),
               "candidate_cv_r2": s["primary"].get("cv_r2"), "candidate_cv_nrmse": s["primary"].get("cv_nrmse"),
               "nested_cv_r2": s["primary"].get("nested_validation", {}).get("r2"),
               "nested_cv_nrmse": s["primary"].get("nested_validation", {}).get("nrmse"),
               "accepted": s["primary"].get("accepted", False)} for s in summaries])
    write_json(output / "analysis_manifest.json", {
        "analyzer_version": VERSION, "package_source_hashes": package_source_hashes(),
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "configuration": {"seed": SEED, "min_r2": settings['min_r2'], "max_nrmse": settings['max_nrmse'],
                          "bootstrap_draws": settings['bootstraps'], "min_residual_df": MIN_RESIDUAL_DF},
        "software": {"python": sys.version.split()[0], "numpy": np.__version__, "pandas": pd.__version__,
                     "scipy": scipy.__version__, "scikit_learn": sklearn.__version__, "matplotlib": matplotlib.__version__},
        "campaign_inventory": inventory, "campaigns": summaries, "errors": errors})
    print(f"Completed {len(summaries)} campaigns; {len(all_availability)} SRP availability entries. Results: {output}", flush=True)
    return 1 if errors else 0
