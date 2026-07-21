function [T_raw, T_design] = executeCampaignRuns(cfg, spec, runs, active_inputs)
    summary_template = makeEmptySummaryRow();
    summary_rows = repmat(summary_template, numel(runs), 1);
    campaign_results = repmat(struct('meta', struct(), 'srp', struct(), 'eval_info', struct(), 'status', "", 'error', "", 'attempts_used', NaN), numel(runs), 1);

    checkVMConnectivity(cfg);
    load_system(cfg.modelName);

    simPID = "";
    for run_idx = 1:numel(runs)
        [summary_rows(run_idx), campaign_results(run_idx), simPID] = executeSingleRun(cfg, spec.campaign_id, runs(run_idx), spec.target_srp, simPID, spec.outRoot);
        save(fullfile(spec.outRoot, 'campaign_checkpoint.mat'), 'campaign_results', 'summary_rows', 'runs');
    end

    safeCleanup(cfg, simPID);
    try
        bdclose(cfg.modelName);
    catch
    end

    T_raw = struct2table(summary_rows);
    T_raw = attachRunMetadataToRawTable(T_raw, runs);
    T_raw = appendRunMetadataToRawTable(T_raw, runs);
    writetable(T_raw, fullfile(spec.outRoot, 'campaign_summary_runs_raw.csv'));

    design_rows = aggregateByDesign(summary_rows, cfg.replicates, active_inputs);
    T_design = struct2table(design_rows);
    writetable(T_design, fullfile(spec.outRoot, 'campaign_summary_design_aggregated.csv'));

    fprintf('Aggregated results written to campaign_summary_design_aggregated.csv\n');
end


function T_raw = appendRunMetadataToRawTable(T_raw, runs)
    metaFields = {'joint_cell','sdq_regime','as_regime','source_campaign','source_design_id','rep_rank','source_regime','source_scenario_id'};

    for f = 1:numel(metaFields)
        field = metaFields{f};
        hasField = arrayfun(@(r) isfield(r, field), runs);

        if any(hasField)
            if strcmp(field, 'rep_rank')
                T_raw.(field) = nan(height(T_raw),1);
            else
                T_raw.(field) = strings(height(T_raw),1);
            end

            for i = 1:min(height(T_raw), numel(runs))
                if isfield(runs(i), field)
                    if strcmp(field, 'rep_rank')
                        T_raw.(field)(i) = double(runs(i).(field));
                    else
                        T_raw.(field)(i) = string(runs(i).(field));
                    end
                end
            end
        end
    end
end


function T_raw = attachRunMetadataToRawTable(T_raw, runs)
    optionalFields = { ...
        'label', ...
        'source_regime', ...
        'source_regime_P', ...
        'source_regime_S', ...
        'source_scenario_id', ...
        'source_scenario_id_P', ...
        'source_scenario_id_S', ...
        'source_srp_P', ...
        'source_srp_S'};

    for f = 1:numel(optionalFields)
        fieldName = optionalFields{f};

        if isfield(runs, fieldName)
            values = strings(height(T_raw), 1);

            for i = 1:height(T_raw)
                if i <= numel(runs) && isfield(runs(i), fieldName)
                    values(i) = string(runs(i).(fieldName));
                else
                    values(i) = "";
                end
            end

            T_raw.(fieldName) = values;
        end
    end
end