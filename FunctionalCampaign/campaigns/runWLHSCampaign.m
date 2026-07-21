function runWLHSCampaign(cfg, spec)
    fprintf('\n=== Running Functional Campaign %s ===\n', spec.name);

    switch upper(string(spec.name))
        case "P_FUNC"
            N = cfg.N_samples_P;
        case "S_FUNC"
            N = cfg.N_samples_S;
        case "M_FUNC"
            N = cfg.N_samples_M;
        otherwise
            error('runWLHSCampaign is only intended for P_FUNC, S_FUNC and M_FUNC. Got %s', spec.name);
    end

    [samples_exec, param_names, w_norm, shape_params] = buildWLHSDesign(spec, cfg, N);

    planTable = array2table(samples_exec, 'VariableNames', param_names);
    writetable(planTable, fullfile(spec.outRoot, 'campaign_plan_wlhs.csv'));

    active_mu = getWeightsForNames(param_names, spec.weight_names, spec.mu_star_raw);
    
    metaWLHS = table( ...
        string(param_names(:)), ...
        active_mu(:), ...
        w_norm(:), ...
        shape_params(:), ...
        'VariableNames', {'Input','MuStarRaw','WeightMaxNorm','BetaShape'});
        writetable(metaWLHS, fullfile(spec.outRoot, 'campaign_wlhs_internal_weights.csv'));

    runs = buildRunList(samples_exec, spec, cfg, "WLHS_FUNC");
    executeCampaignRuns(cfg, spec, runs, param_names);

    fprintf('Campaign %s used %d design points x %d replicates = %d executions\n', ...
        spec.name, N, cfg.replicates, N * cfg.replicates);
end
