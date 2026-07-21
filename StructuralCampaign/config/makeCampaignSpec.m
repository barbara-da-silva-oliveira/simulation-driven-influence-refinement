function spec = makeCampaignSpec(cfg, name)
    name = upper(string(name));
    spec = struct();
    spec.name = name;

    switch name
        case "M"
            spec.campaign_id = "campaign_M_performance";
            spec.outRoot = fullfile(cfg.base_out_root, 'campaign_M_performance');
            spec.target_srp = 'time_turning';
            spec.param_names = {'friction', 'v', 'w'};
            spec.bounds_matrix = [ ...
                cfg.bounds.friction; ...
                cfg.bounds.v; ...
                cfg.bounds.w];
        
            spec.full_metric_list = { ...
                'completed', 'completion_time', 'average_segment_speed', ...
                'sign_detection_quality', 'tracking_error_rms', ...
                'left_distance_to_sign', 'right_distance_to_sign', ...
                'stop_distance_to_sign', 'time_turning'};



        case "P"
            spec.campaign_id = "campaign_P_perception";
            spec.outRoot = fullfile(cfg.base_out_root, 'campaign_P_perception');
            spec.target_srp = 'sign_detection_quality';
            spec.param_names = {'luminosity', 'size', 'transparency'};
            %spec.param_names = {'luminosity', 'size'};
            %spec.bounds_matrix = [cfg.bounds.luminosity; cfg.bounds.size];
            spec.bounds_matrix = [cfg.bounds.luminosity; cfg.bounds.size; cfg.bounds.transparency];
            spec.full_metric_list = { ...
                'completed', 'completion_time', 'average_segment_speed', ...
                'sign_detection_quality', 'tracking_error_rms', ...
                'left_distance_to_sign', 'right_distance_to_sign', ...
                'stop_distance_to_sign', 'time_turning'};

        case "S"
            spec.campaign_id = "campaign_S_slippery";
            spec.outRoot = fullfile(cfg.base_out_root, 'campaign_S_slippery');
            spec.target_srp = 'average_segment_speed';
            spec.param_names = {'v', 'friction'};
            spec.bounds_matrix = [cfg.bounds.v; cfg.bounds.friction];
            spec.full_metric_list = { ...
                'completed', 'completion_time', 'average_segment_speed', ...
                'sign_detection_quality', 'tracking_error_rms', ...
                'left_distance_to_sign', 'right_distance_to_sign', ...
                'stop_distance_to_sign', 'time_turning'};

        case "C"
            spec.campaign_id = "campaign_C_control";
            spec.outRoot = fullfile(cfg.base_out_root, 'campaign_C_control');
            spec.target_srp = 'tracking_error_rms';

        otherwise
            error('Unsupported campaign spec name: %s', name);
    end

    if ~exist(spec.outRoot, 'dir')
        mkdir(spec.outRoot);
    end
end


