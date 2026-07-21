function [mu_raw, w_max, w_sum, T_out] = loadStructuralWeights(cfg, spec)
    %This is the case for the C_FUNC, the factors are the regimes of the
    %campaigns, for the others, the factors are the name of the parameters
    %themselves
    if ~isfield(spec, 'structural_factor_names')
        spec.structural_factor_names = spec.weight_names;
    end

    switch upper(string(spec.name))
        case {"P_FUNC","S_FUNC","M_FUNC"}
            mu_raw = readMuStarFromCampaign( ...
                spec.weight_source, ...
                {'morris_target_sensitivity.csv','morris_sensitivity_all_SRPs.csv'}, ...
                spec.structural_factor_names, ...
                spec.mu_metric_hint);

        case "C_FUNC"
             mu_raw = readCampaignCFactorWeights(spec.weight_source, spec.structural_factor_names);

        otherwise
            error('No structural weight loader for %s', spec.name);
    end

    w_max = normalizeWeightsMax(mu_raw);
    w_sum = normalizeWeightsSum(mu_raw);

    T_out = table( ...
        string(spec.weight_names(:)), ...
        string(spec.structural_factor_names(:)), ...
        mu_raw(:), ...
        w_max(:), ...
        w_sum(:), ...
        'VariableNames', {'FunctionalParticipant','StructuralFactor','MuStarRaw','WeightMaxNorm','WeightSumNorm'});
end