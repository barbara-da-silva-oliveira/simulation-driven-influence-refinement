function runMissionScenarioCampaign(cfg)
    outRoot = fullfile(cfg.base_out_root, 'campaign_M_functional_scenario_matrix');
    if ~exist(outRoot, 'dir'), 
        mkdir(outRoot); 
    end
    repCFile = fullfile(cfg.base_out_root, 'campaign_C_functional_regime_WLHS', 'tracking_error_rms_representatives.csv');
    repSFile = fullfile(cfg.base_out_root, 'campaign_S_functional_WLHS', 'average_segment_speed_representatives.csv');
    if ~exist(repCFile, 'file'), 
        error('Missing C_FUNC representatives: %s', repCFile); 
    end
    if ~exist(repSFile, 'file'), 
        error('Missing S_FUNC representatives: %s', repSFile); 
    end
    TC = readtable(repCFile);
    TS = readtable(repSFile);
    runs = struct([]); idx = 1;
    for i = 1:height(TC)
        for j = 1:height(TS)
            in = struct();
            in.w = TC.w_gain(i);
            in.luminosity = TC.luminosity_level(i);
            in.transparency = cfg.nominal.transparency;
            in.size = TC.target_blob_size(i);
            in.v = TS.v_nominal(j);
            in.friction = TS.friction_surface(j);
            for rep = 1:cfg.replicates
                runs(idx).run_id = idx;
                runs(idx).design_id = idx;
                runs(idx).rep = rep;
                runs(idx).scenario_id = cfg.scenario_id;
                runs(idx).inputs = fillMissingInputsWithNominal(in, cfg);
                runs(idx).label = sprintf('ctrl_%s_speed_%s_rep%d', string(TC.regime_label(i)), string(TS.regime_label(j)), rep);
                runs(idx).source_regime = string(TC.regime_label(i)) + "_x_" + string(TS.regime_label(j));
                runs(idx).source_scenario_id = string(TC.design_id(i)) + "_x_" + string(TS.design_id(j));
                idx = idx + 1;
            end
        end
    end
    spec = struct();
    spec.campaign_id = "campaign_M_functional_scenario_matrix";
    spec.target_srp = 'time_turning';
    spec.outRoot = outRoot;
    executeCampaignRuns(cfg, spec, runs, {'w','luminosity','size','v','friction'});
end
