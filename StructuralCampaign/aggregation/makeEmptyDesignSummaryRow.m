function row = makeEmptyDesignSummaryRow(param_names, metric_list)
    row = struct();
    row.design_id = NaN;
    row.n_target_replicates = NaN;
    row.n_valid_replicates = NaN;
    row.n_missing_logs_replicates = NaN;
    row.n_invalid_technical_replicates = NaN;
    row.aggregate_status = "";
    for p = 1:numel(param_names)
        row.(sanitizeFieldName(param_names{p})) = NaN;
    end
    for m = 1:numel(metric_list)
        metric = metric_list{m};
        row.(metric) = NaN;
        row.([metric '_validity']) = "";
    end
end
% function name = sanitizeFieldName(nameIn)
%     name = matlab.lang.makeValidName(char(nameIn));
% end
% function row = makeEmptyDesignSummaryRow(active_inputs, metric_list)
%     row = struct();
%     row.design_id = NaN; row.n_target_replicates = NaN; row.n_valid_replicates = NaN; row.n_missing_logs_replicates = NaN; row.n_invalid_technical_replicates = NaN; row.aggregate_status = "";
%     for i = 1:numel(active_inputs), row.(normalizeSummaryFieldName(active_inputs{i})) = NaN; end
%     for m = 1:numel(metric_list), row.(metric_list{m}) = NaN; row.([metric_list{m} '_validity']) = ""; end
% end