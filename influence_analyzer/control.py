"""Application service for chained campaign C and upstream-SRP diagnostics."""

import itertools
from .analysis import response_analysis
from .io import write_csv
from .plotting import plot_control_regimes
from .preparation import numeric_mask


def control_diagnostics(data, spec, output, settings):
    """Keep source SRPs distinct from those re-observed during C executions."""
    if "representative_id" not in data:
        return
    summaries = []
    if "joint_cell" in data:
        for cell, sub in data.groupby("joint_cell"):
            summaries.append({"joint_cell": cell, "n_designs": len(sub),
                              "n_representatives": sub.representative_id.nunique(),
                              "n_w_levels": sub.w_gain.nunique(),
                              "tracking_error_mean": sub[spec['output_srp']].mean(),
                              "tracking_error_min": sub[spec['output_srp']].min(),
                              "tracking_error_max": sub[spec['output_srp']].max()})
        write_csv(output / "joint_regime_summary.csv", summaries)
        coverage = []
        for p, s in itertools.product(("Low", "Medium", "High"), repeat=2):
            cell = p + "__" + s
            sub = data.loc[data.joint_cell.eq(cell)]
            coverage.append({"sdq_regime": p, "speed_regime": s, "joint_cell": cell,
                             "n_designs": len(sub), "n_representatives": sub.representative_id.nunique(),
                             "status": "observed" if len(sub) else "not_sampled"})
        write_csv(output / "joint_regime_coverage.csv", coverage)
    metadata = [x for x in ("design_id", "representative_id", "joint_cell", "w_gain") if x in data]
    drift = data[metadata].copy()
    for source, actual in (("source_srp_P", "sign_detection_quality"), ("source_srp_S", "average_segment_speed")):
        if source in data and actual in data:
            drift[source] = data[source]
            drift[actual] = data[actual].where(numeric_mask(data, actual))
            drift[actual + "_minus_source"] = drift[actual] - drift[source]
    write_csv(output / "upstream_srp_drift.csv", drift)
    # actual_features = ("w_gain", "sign_detection_quality", "average_segment_speed")
    # response_analysis(data, actual_features, spec['output_srp'], spec,
    #                   output / "realized_srp_diagnostic", settings, primary=False, plots=False)
    if not settings['no_plots'] and "joint_cell" in data:
        plot_control_regimes(data, spec, output)
