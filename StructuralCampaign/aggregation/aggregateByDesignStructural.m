function design_rows = aggregateByDesignStructural(summary_rows, samples_exec, replicates, param_names, metric_list)
    num_generated_runs = size(samples_exec, 1);
    design_template = makeEmptyDesignSummaryRow(param_names, metric_list);
    design_rows = repmat(design_template, num_generated_runs, 1);

    for design_id = 1:num_generated_runs
        design_rows(design_id).design_id = design_id;
        design_rows(design_id).n_target_replicates = replicates;

        for p = 1:numel(param_names)
            design_rows(design_id).(sanitizeFieldName(param_names{p})) = samples_exec(design_id, p);
        end

        matchingIdx = find(arrayfun(@(r) safeGetNumericField(r, 'design_id', NaN) == design_id, summary_rows));
        theseRows = summary_rows(matchingIdx);

        n_valid_runs = sum(arrayfun(@(r) safeGetStringField(r, 'run_validity', "INVALID_TECHNICAL") == "VALID_RUN", theseRows));
        n_missing_logs = sum(arrayfun(@(r) safeGetStringField(r, 'run_validity', "INVALID_TECHNICAL") == "INVALID_MISSING_REQUIRED_LOGS", theseRows));
        n_invalid_technical = sum(arrayfun(@(r) safeGetStringField(r, 'run_validity', "INVALID_TECHNICAL") == "INVALID_TECHNICAL", theseRows));

        design_rows(design_id).n_valid_replicates = n_valid_runs;
        design_rows(design_id).n_missing_logs_replicates = n_missing_logs;
        design_rows(design_id).n_invalid_technical_replicates = n_invalid_technical;

        if n_valid_runs == replicates
            design_rows(design_id).aggregate_status = "OK_ALL_REPLICATES";
        elseif n_valid_runs >= 1
            design_rows(design_id).aggregate_status = "OK_PARTIAL_REPLICATES";
        elseif n_missing_logs >= 1
            design_rows(design_id).aggregate_status = "INVALID_MISSING_REQUIRED_LOGS";
        else
            design_rows(design_id).aggregate_status = "ALL_REPLICATES_CRASHED";
        end

        for m = 1:numel(metric_list)
            metric = metric_list{m};
            [aggVal, aggValidity] = aggregateMetricAcrossRowsSafe(theseRows, metric);
            design_rows(design_id).(metric) = aggVal;
            design_rows(design_id).([metric '_validity']) = aggValidity;
        end
    end
end


function [aggVal, aggValidity] = aggregateMetricAcrossRowsSafe(rows, metric)
    validities = strings(numel(rows), 1);
    vals = nan(numel(rows), 1);
    for i = 1:numel(rows)
        validityField = [metric '_validity'];
        validities(i) = safeGetStringField(rows(i), validityField, "INVALID_TECHNICAL");
        vals(i) = safeGetNumericField(rows(i), metric, NaN);
    end
    usableMask = isUsableMetricValidity(validities);
    if any(usableMask)
        usableVals = vals(usableMask);
        usableVals = usableVals(~isnan(usableVals));
        if isempty(usableVals)
            aggVal = NaN;
            aggValidity = "VALID_BEHAVIORAL_NAN";
            return;
        end
        if strcmp(metric, 'completed')
            aggVal = mean(usableVals) >= 0.5;
            aggValidity = "VALID_BOOLEAN";
        else
            aggVal = mean(usableVals, 'omitnan');
            if all(validities(usableMask) == "VALID_ZERO") && abs(aggVal) < eps
                aggValidity = "VALID_ZERO";
            else
                aggValidity = "VALID";
            end
        end
        return;
    end
    aggVal = NaN;
    if any(validities == "VALID_BEHAVIORAL_NAN")
        aggValidity = "VALID_BEHAVIORAL_NAN";
    elseif any(validities == "INVALID_MISSING_REQUIRED_LOGS")
        aggValidity = "INVALID_MISSING_REQUIRED_LOGS";
    else
        aggValidity = "INVALID_TECHNICAL";
    end
end


function name = sanitizeFieldName(nameIn)
    name = matlab.lang.makeValidName(char(nameIn));
end