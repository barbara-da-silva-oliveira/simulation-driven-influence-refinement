function meta = buildRunMeta(campaign_id, scenario_id, run_id, design_id, rep, attempt, seed_val, v_val, w_val, size_val, fric_val, lum_val, transp_val)
    meta = struct();
    meta.campaign_id = campaign_id;
    meta.scenario_id = scenario_id;
    meta.run_id = run_id;
    meta.design_id = design_id;
    meta.rep = rep;
    meta.attempt = attempt;
    meta.seed = seed_val;
    meta.timestamp = char(datetime('now'));
    meta.parameters = struct('v_nominal', v_val, 'w_gain', w_val, 'target_blob_size', size_val);
    meta.environment = struct('friction_surface', fric_val, 'luminosity_level', lum_val, 'wall_transparency', transp_val);
end
