function spec = makeFunctionalSpec(cfg, campaignName)
    spec = struct();
    spec.name = upper(string(campaignName));

    switch spec.name
        case "P_FUNC"
            spec.campaign_id = "campaign_P_functional_WLHS";
        
            spec.active_inputs = {'luminosity','size'};
            spec.weight_names = {'luminosity','size'};
            spec.structural_factor_names = {'luminosity','size'};
        
            spec.target_srp = 'sign_detection_quality';
        
            spec.fixed = struct( ...
                'v', cfg.nominal.v, ...
                'w', cfg.nominal.w, ...
                'friction', cfg.nominal.friction, ...
                'transparency', cfg.nominal.transparency);
        
            spec.bounds = struct( ...
                'luminosity', cfg.bounds.luminosity, ...
                'size', cfg.bounds.size);
        
            spec.mu_metric_hint = 'sign_detection_quality';
            spec.weight_source = fullfile(cfg.structural_results_root, 'campaign_P_perception');
        case "S_FUNC"
            spec.campaign_id = "campaign_S_functional_WLHS";
        
            spec.active_inputs = {'v','friction'};
            spec.weight_names = {'v','friction'};
            spec.structural_factor_names = {'v','friction'};
        
            spec.target_srp = 'average_segment_speed';
        
            spec.fixed = struct( ...
                'w', cfg.nominal.w, ...
                'size', cfg.nominal.size, ...
                'luminosity', cfg.nominal.luminosity, ...
                'transparency', cfg.nominal.transparency);
        
            spec.bounds = struct( ...
                'v', cfg.bounds.v, ...
                'friction', cfg.bounds.friction);
        
            spec.mu_metric_hint = 'average_segment_speed';
            spec.weight_source = fullfile(cfg.structural_results_root, 'campaign_S_slippery');
        case "C_FUNC"
            spec.campaign_id = "campaign_C_functional_joint_regime_WLHS";
        
            spec.active_inputs = {'w'};
            spec.srp_input_names = {'sign_detection_quality', 'average_segment_speed'};
        
            spec.target_srp = 'tracking_error_rms';
            spec.bounds = struct('w', cfg.bounds.w);
        
            spec.weight_names = {'w', 'sign_detection_quality', 'average_segment_speed'};
            spec.structural_factor_names = {'w_gain', 'P_regime', 'S_regime'};
        
            spec.mu_metric_hint = 'tracking_error_rms';
            spec.weight_source = fullfile(cfg.structural_results_root, 'campaign_C_control');

        case "M_FUNC"
            spec.campaign_id = "campaign_M_functional_WLHS";
        
            spec.active_inputs = {'friction','v','w'};
            spec.weight_names = {'friction','v','w'};
            spec.structural_factor_names = {'friction','v','w'};
        
            spec.target_srp = 'time_turning';
        
            spec.fixed = struct( ...
                'size', cfg.nominal.size, ...
                'luminosity', cfg.nominal.luminosity, ...
                'transparency', cfg.nominal.transparency);
        
            spec.bounds = struct( ...
                'friction', cfg.bounds.friction, ...
                'v', cfg.bounds.v, ...
                'w', cfg.bounds.w);
        
            spec.mu_metric_hint = 'time_turning';
            spec.weight_source = fullfile(cfg.structural_results_root, 'campaign_M_performance');
    end

    spec.outRoot = fullfile(cfg.base_out_root, char(spec.campaign_id));
    if ~exist(spec.outRoot, 'dir')
        mkdir(spec.outRoot);
    end

    [spec.mu_star_raw, spec.weights_maxnorm, spec.weights_sumnorm, spec.weight_table] = loadStructuralWeights(cfg, spec);
    writetable(spec.weight_table, fullfile(spec.outRoot, 'functional_weights_from_structural.csv'));
end
