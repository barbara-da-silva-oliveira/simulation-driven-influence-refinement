function cfg = defaultConfigStructural()
    cfg.vmIP       = '192.168.61.129';
    cfg.vmUser     = 'user';
    cfg.vmPassword = 'password';
    cfg.remoteDir  = 'catkin_ws/src/mw_vision_example/worlds';
    cfg.remoteFile = 'mw_vision_world_newstopsign_cosim.world';
    cfg.modelName = 'signFollowingRobotROSCoSim';
    cfg.scenario_id = "gazebo";

    mainDir = fileparts(which('run_structural_campaign'));

    cfg.structural_root = fileparts(mainDir);
    cfg.project_root = fileparts(cfg.structural_root);
    
    cfg.base_out_root = fullfile(cfg.structural_root, 'results_structural_campaign');  
    
    if ~exist(cfg.base_out_root, 'dir')
        mkdir(cfg.base_out_root);
    end
    if ~exist(cfg.base_out_root, 'dir')
        mkdir(cfg.base_out_root);
    end
    if ~exist(cfg.base_out_root, 'dir')
        mkdir(cfg.base_out_root);
    end

    cfg.simStopTime = 30;
    cfg.replicates = 2;
    cfg.maxRetriesPerRep = 3;
    cfg.num_levels = int32(4);
    cfg.N_trajectories = int32(4);

    cfg.bounds.v = [0.2, 0.4];
    cfg.bounds.w = [0.2, 0.4];
    cfg.bounds.size = [90, 140];
    cfg.bounds.friction = [0.2, 0.7];
    cfg.bounds.luminosity = [0.3, 0.5];
    cfg.bounds.transparency = [0.0, 0.3];

    cfg.nominal.v = mean(cfg.bounds.v);
    cfg.nominal.w = mean(cfg.bounds.w);
    cfg.nominal.size = round(mean(cfg.bounds.size));
    cfg.nominal.friction = mean(cfg.bounds.friction);
    cfg.nominal.luminosity = mean(cfg.bounds.luminosity);
    cfg.nominal.transparency = 0.0;

    cfg.control_w_grid = linspace(cfg.bounds.w(1), cfg.bounds.w(2), 4); %before linpace(..., 5)

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

    disp('All cfg fields:');
    disp(fieldnames(cfg));

end
