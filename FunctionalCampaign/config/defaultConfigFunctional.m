function cfg = defaultConfigFunctional()
    cfg = struct();
    cfg.vmIP       = '192.168.61.129';
    cfg.vmUser     = 'user';
    cfg.vmPassword = 'password';
    cfg.remoteDir  = 'catkin_ws/src/mw_vision_example/worlds';
    cfg.remoteFile = 'mw_vision_world_newstopsign_cosim.world';
    cfg.modelName   = 'signFollowingRobotROSCoSim';
    cfg.scenario_id = "gazebo_func_refine";
    
    functionalMainFile = which('run_functional_campaign');
    functionalMainDir = fileparts(functionalMainFile);      % .../FunctionalCampaign/main
    cfg.functional_root = fileparts(functionalMainDir);     % .../FunctionalCampaign
    cfg.project_root = fileparts(cfg.functional_root);      % .../SignFollowingCampaign
    
    cfg.base_out_root = fullfile(cfg.functional_root, 'functional_campaign_results');
    
    cfg.structural_results_root = fullfile( ...
        cfg.project_root, ...
        'StructuralCampaign', ...
        'results_structural_campaign');
    
    if ~exist(cfg.base_out_root, 'dir')
        mkdir(cfg.base_out_root);
    end
    
    fprintf('Functional results root: %s\n', cfg.base_out_root);
    fprintf('Structural results root: %s\n', cfg.structural_results_root);

    cfg.simStopTime = 20;
    cfg.replicates = 2;
    cfg.maxRetriesPerRep = 3;

    cfg.bounds.v            = [0.2, 0.4];
    cfg.bounds.w            = [0.2, 0.4];
    cfg.bounds.size         = [90, 140];
    cfg.bounds.friction     = [0.2, 0.7];
    cfg.bounds.luminosity   = [0.3, 0.5];
    cfg.bounds.transparency = [0.0, 0.0]; %We prunned it in the first part

    cfg.nominal.v            = mean(cfg.bounds.v);
    cfg.nominal.w            = mean(cfg.bounds.w);
    cfg.nominal.size         = round(mean(cfg.bounds.size));
    cfg.nominal.friction     = mean(cfg.bounds.friction);
    cfg.nominal.luminosity   = mean(cfg.bounds.luminosity);
    cfg.nominal.transparency = 0.0;

    % Budgets aligned with structural stage
    cfg.N_samples_P = 16;      % 16 x 2 reps = 32 executions
    cfg.N_samples_S = 12;      % 12 x 2 reps = 24 executions
    cfg.N_samples_M = 16;   % 16 x 2 reps = 32 executions
    cfg.target_runs_C = 54;    % target total executions for C to save budget of sim runs
    
    cfg.control_N_samples = 12; % fallback only
    cfg.control_base_contexts_per_regime = 2; % by default, when srp has higher weight, it receives more representatives 
    cfg.wlhs_shape_gain = 6.0;
    cfg.regime_labels = {'Low','Moderate','High','VeryHigh'};
    cfg.regime_count = numel(cfg.regime_labels);

    % Joint SRP cells used in functional C
    cfg.joint_regime_labels = {'Low','Medium','High'};
    cfg.n_joint_representatives_per_cell = 2;
    cfg.min_rows_per_joint_cell = 1;

    cfg.dirPFunc = fullfile(cfg.base_out_root, 'campaign_P_functional_WLHS');
    cfg.dirSFunc = fullfile(cfg.base_out_root, 'campaign_S_functional_WLHS');
    cfg.dirCFunc = fullfile(cfg.base_out_root, 'campaign_C_functional_joint_regime_WLHS');
    cfg.evalParams.image_center_x = 320;
    cfg.evalParams.center_tolerance = 20;
    cfg.evalParams.blob_size_tolerance = 20;
    cfg.evalParams.pause_tolerance = 1e-6;
    cfg.evalParams.stop_sign_idx  = 1;
    cfg.evalParams.right_sign_idx = 2;
    cfg.evalParams.left_sign_positions  = [1.55963 0.175611; 2.96136 1.04790; 4.19986 3.01241];
    cfg.evalParams.right_sign_positions = [1.23470 1.90712; 2.58044 3.34167];
    cfg.evalParams.stop_sign_positions  = [3.69568 4.31208];
    cfg.evalParams.target_stop_distance = 0.80;
    cfg.evalParams.distance_tolerance   = 0.30;
end
