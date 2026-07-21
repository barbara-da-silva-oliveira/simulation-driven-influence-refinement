function [sensitivity_table, metric_audit] = runTargetMorrisFromDesignRows(design_rows, samples_exec, param_names, bounds_matrix, srp_list, num_levels)
    higher_is_better = {'average_segment_speed', 'sign_detection_quality'};
    lower_is_better  = {'tracking_error_rms', 'stop_distance_to_sign', 'time_turning'};
    py_bounds = py.list();
    for p = 1:size(bounds_matrix, 1)
        py_bounds.append(py.list(num2cell(bounds_matrix(p,:))));
    end
    names_py = py.list(param_names);
    py_problem = py.dict(pyargs('num_vars', int32(numel(param_names)), 'names', names_py, 'bounds', py_bounds));
    X_py = py.numpy.array(samples_exec);
    sensitivity_table = table(string(param_names(:)), 'VariableNames', {'Parameter'});
    metric_audit = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'Metric', 'NumUsable', 'NumValidBehavioralNaN', 'NumMissingLogs', 'NumTechnicalInvalid'});
    num_generated_runs = size(samples_exec, 1);
    
    for s_idx = 1:numel(srp_list)
        current_srp = srp_list{s_idx};
        Y_results = nan(num_generated_runs, 1);
        metricValidity = strings(num_generated_runs, 1);
        for i = 1:num_generated_runs
            Y_results(i) = safeGetNumericField(design_rows(i), current_srp, NaN);
            metricValidity(i) = safeGetStringField(design_rows(i), [current_srp '_validity'], "INVALID_TECHNICAL");
        end
        usableMask = isUsableMetricValidity(metricValidity);
        behavioralNaNMask = metricValidity == "VALID_BEHAVIORAL_NAN";
        missingLogsMask = metricValidity == "INVALID_MISSING_REQUIRED_LOGS";
        invalidTechnicalMask = metricValidity == "INVALID_TECHNICAL";
        metric_row = table(string(current_srp), sum(usableMask), sum(behavioralNaNMask), sum(missingLogsMask), sum(invalidTechnicalMask), ...
            'VariableNames', {'Metric', 'NumUsable', 'NumValidBehavioralNaN', 'NumMissingLogs', 'NumTechnicalInvalid'});
        metric_audit = [metric_audit; metric_row]; %#ok<AGROW>
        
        if ~any(usableMask)
            continue;
        end
        if any(~usableMask)
            validVals = Y_results(usableMask);
            fillValue = worstObservedValue(current_srp, validVals, higher_is_better, lower_is_better);
            Y_results(~usableMask) = fillValue;
        end
        try
            Y_py = py.numpy.array(Y_results);
            morris_results = py.SALib.analyze.morris.analyze(py_problem, X_py, Y_py, pyargs('num_levels', num_levels));
            sensitivity_table.(sprintf('%s_MuStar', current_srp)) = double(morris_results{'mu_star'})';
            sensitivity_table.(sprintf('%s_Sigma', current_srp)) = double(morris_results{'sigma'})';
        catch ME
            warning('Failed Morris analysis for %s: %s', current_srp, ME.message);
        end
    end
end


function fillValue = worstObservedValue(metricName, validVals, higher_is_better, lower_is_better)
    if isempty(validVals)
        fillValue = NaN;
        return;
    end
    if any(strcmp(metricName, higher_is_better))
        fillValue = min(validVals);
    elseif any(strcmp(metricName, lower_is_better))
        fillValue = max(validVals);
    else
        fillValue = max(validVals);
    end
end
