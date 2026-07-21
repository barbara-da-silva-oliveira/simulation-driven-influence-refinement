function row = makeEmptyDesignSummaryRow(active_inputs, metric_list)
    row = struct();
    row.design_id = NaN; 
    row.n_target_replicates = NaN; 
    row.n_valid_replicates = NaN; 
    row.n_missing_logs_replicates = NaN; 
    row.n_invalid_technical_replicates = NaN; 
    row.aggregate_status = "";
    for i = 1:numel(active_inputs), row.(normalizeSummaryFieldName(active_inputs{i})) = NaN; end
    for m = 1:numel(metric_list), row.(metric_list{m}) = NaN; row.([metric_list{m} '_validity']) = ""; end
end
