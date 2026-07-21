function design_rows = aggregateByDesign(summary_rows, replicates, active_inputs)
    metric_list = {'completed','completion_time','average_segment_speed','sign_detection_quality','tracking_error_rms','left_distance_to_sign','right_distance_to_sign','stop_distance_to_sign','time_turning','time_to_next_blob20_first','time_to_next_blob20_count'};
    design_ids = unique([summary_rows.design_id]);
    design_ids = design_ids(~isnan(design_ids));
    design_rows = repmat(makeEmptyDesignSummaryRow(active_inputs, metric_list), numel(design_ids), 1);
    for d = 1:numel(design_ids)
        design_id = design_ids(d);
        design_rows(d).design_id = design_id;
        design_rows(d).n_target_replicates = replicates;
        matchingIdx = find(arrayfun(@(r) r.design_id == design_id, summary_rows));
        theseRows = summary_rows(matchingIdx);
        r0 = theseRows(1);
        for a = 1:numel(active_inputs)
            f = normalizeSummaryFieldName(active_inputs{a});
            if isfield(r0, f), design_rows(d).(f) = r0.(f); end
        end
        n_valid_runs = sum(arrayfun(@(r) r.run_validity == "VALID_RUN", theseRows));
        n_missing_logs = sum(arrayfun(@(r) r.run_validity == "INVALID_MISSING_REQUIRED_LOGS", theseRows));
        n_invalid_technical = sum(arrayfun(@(r) r.run_validity == "INVALID_TECHNICAL", theseRows));
        design_rows(d).n_valid_replicates = n_valid_runs;
        design_rows(d).n_missing_logs_replicates = n_missing_logs;
        design_rows(d).n_invalid_technical_replicates = n_invalid_technical;
        if n_valid_runs == replicates
            design_rows(d).aggregate_status = "OK_ALL_REPLICATES";
        elseif n_valid_runs >= 1
            design_rows(d).aggregate_status = "OK_PARTIAL_REPLICATES";
        elseif n_missing_logs >= 1
            design_rows(d).aggregate_status = "INVALID_MISSING_REQUIRED_LOGS";
        else
            design_rows(d).aggregate_status = "ALL_REPLICATES_CRASHED";
        end
        for m = 1:numel(metric_list)
            metric = metric_list{m};
            [aggVal, aggValidity] = aggregateMetricAcrossRows(theseRows, metric);
            design_rows(d).(metric) = aggVal;
            design_rows(d).([metric '_validity']) = aggValidity;
        end
    end
end


