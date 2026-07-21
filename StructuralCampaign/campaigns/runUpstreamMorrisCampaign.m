function runUpstreamMorrisCampaign(cfg, spec)
    fprintf('=== Running Campaign %s ===\n', spec.name);

    samples_exec = buildMorrisSamples(spec.param_names, spec.bounds_matrix, cfg.N_trajectories, cfg.num_levels);
    num_generated_runs = size(samples_exec, 1);

    planTable = array2table(samples_exec, 'VariableNames', spec.param_names);
    writetable(planTable, fullfile(spec.outRoot, 'morris_plan_check.csv'));

    runs = struct([]);
    idx = 1;
    for design_id = 1:num_generated_runs
        for rep = 1:cfg.replicates
            in = struct();
            for p = 1:numel(spec.param_names)
                pname = spec.param_names{p};
                val = samples_exec(design_id, p);
                if strcmp(pname, 'size')
                    val = round(val);
                end
                in.(pname) = val;
            end
            runs(idx).run_id = idx;
            runs(idx).design_id = design_id;
            runs(idx).rep = rep;
            runs(idx).scenario_id = cfg.scenario_id;
            runs(idx).inputs = fillMissingInputsWithNominal(in, cfg);
            idx = idx + 1;
        end
    end

    summary_template = makeEmptySummaryRow();
    summary_rows = repmat(summary_template, numel(runs), 1);
    campaign_results = repmat(struct('meta', struct(), 'srp', struct(), 'eval_info', struct(), 'status', "", 'error', "", 'attempts_used', NaN), numel(runs), 1);

    checkVMConnectivity(cfg);
    load_system(cfg.modelName);

    simPID = "";
    for run_idx = 1:numel(runs)
        [summary_rows(run_idx), campaign_results(run_idx), simPID] = ...
            executeSingleRun(cfg, spec.campaign_id, runs(run_idx), spec.target_srp, simPID, spec.outRoot);

        save(fullfile(spec.outRoot, 'campaign_checkpoint.mat'), ...
            'campaign_results', 'summary_rows', 'runs', 'samples_exec');
    end

    safeCleanup(cfg, simPID);
    try
        bdclose(cfg.modelName);
    catch
    end

    save(fullfile(spec.outRoot, 'campaign_results_final.mat'), ...
        'campaign_results', 'summary_rows', 'runs', 'samples_exec');

    T_raw = struct2table(summary_rows);
    writetable(T_raw, fullfile(spec.outRoot, 'campaign_summary_runs_raw.csv'));

    design_rows = aggregateByDesignStructural(summary_rows, samples_exec, cfg.replicates, spec.param_names, spec.full_metric_list);
    T_design = struct2table(design_rows);
    writetable(T_design, fullfile(spec.outRoot, 'campaign_summary_design_aggregated.csv'));

    [sensTable, auditTable] = runTargetMorrisFromDesignRows(design_rows, samples_exec, spec.param_names, spec.bounds_matrix, {spec.target_srp}, cfg.num_levels);
    writetable(sensTable, fullfile(spec.outRoot, 'morris_target_sensitivity.csv'));
    writetable(auditTable, fullfile(spec.outRoot, 'morris_metric_validity_audit.csv'));

    fprintf('Campaign %s finished.\n', spec.name);
end


function row = makeEmptySummaryRow()
    row = struct();
    row.campaign_id = ""; row.scenario_id = ""; row.run_id = NaN; row.design_id = NaN; row.replicate_id = NaN; row.attempt_used = NaN; row.seed = NaN; row.timestamp = ""; row.status = ""; row.error_message = ""; row.run_validity = ""; row.missing_required_logs = ""; row.missing_required_logs_count = NaN; row.friction_surface = NaN; row.luminosity_level = NaN; row.wall_transparency = NaN; row.v_nominal = NaN; row.w_gain = NaN; row.target_blob_size = NaN; row.completed = NaN; row.completed_validity = ""; row.completion_time = NaN; row.completion_time_validity = ""; row.average_segment_speed = NaN; row.average_segment_speed_validity = ""; row.sign_detection_quality = NaN; row.sign_detection_quality_validity = ""; row.tracking_error_rms = NaN; row.tracking_error_rms_validity = ""; row.left_distance_to_sign = NaN; row.left_distance_to_sign_validity = ""; row.right_distance_to_sign = NaN; row.right_distance_to_sign_validity = ""; row.stop_distance_to_sign = NaN; row.stop_distance_to_sign_validity = ""; row.time_turning = NaN; row.time_turning_validity = ""; row.time_to_next_blob20_first = NaN; row.time_to_next_blob20_first_validity = ""; row.time_to_next_blob20_count = NaN; row.time_to_next_blob20_count_validity = ""; row.run_dir = ""; row.logsout_file = ""; row.summary_json = "";
end


function checkVMConnectivity(cfg)
    sftpObj = sftp(cfg.vmIP, cfg.vmUser, 'Password', cfg.vmPassword);
    close(sftpObj);
end

function in = fillMissingInputsWithNominal(in, cfg)
    if ~isfield(in, 'v'), in.v = cfg.nominal.v; end
    if ~isfield(in, 'w'), in.w = cfg.nominal.w; end
    if ~isfield(in, 'size'), in.size = cfg.nominal.size; end
    if ~isfield(in, 'friction'), in.friction = cfg.nominal.friction; end
    if ~isfield(in, 'luminosity'), in.luminosity = cfg.nominal.luminosity; end
    if ~isfield(in, 'transparency'), in.transparency = cfg.nominal.transparency; end
end


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