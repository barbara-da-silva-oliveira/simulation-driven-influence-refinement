function runs = buildRunList(samples_exec, spec, cfg, regime_label)
    runs = struct([]); idx = 1;
    for design_id = 1:size(samples_exec,1)
        row_inputs = spec.fixed;
        for j = 1:numel(spec.active_inputs)
            row_inputs.(spec.active_inputs{j}) = samples_exec(design_id, j);
        end
        for rep = 1:cfg.replicates
            runs(idx).run_id = idx;
            runs(idx).design_id = design_id;
            runs(idx).rep = rep;
            runs(idx).scenario_id = cfg.scenario_id;
            runs(idx).inputs = fillMissingInputsWithNominal(row_inputs, cfg);
            runs(idx).label = sprintf('wlhs_%03d_rep%d', design_id, rep);
            runs(idx).source_regime = regime_label;
            runs(idx).source_scenario_id = "";
            idx = idx + 1;
        end
    end
end
