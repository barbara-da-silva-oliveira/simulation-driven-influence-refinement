function runControlWLHSCampaign(cfg)
    spec = makeFunctionalSpec(cfg, "C_FUNC");

    jointFile = fullfile(spec.outRoot, 'joint_observed_representatives.csv');

    if ~exist(jointFile, 'file')
        error(['Missing joint observed representatives file: %s\n' ...
               'Run run_functional_campaign("BUILD_C_REGIMES") before C_FUNC.'], jointFile);
    end

    Tctx = readtable(jointFile);

    requiredCols = {'sign_detection_quality','average_segment_speed','sdq_regime','as_regime','joint_cell'};
    for c = 1:numel(requiredCols)
        if ~ismember(requiredCols{c}, Tctx.Properties.VariableNames)
            error('Missing required column %s in %s.', requiredCols{c}, jointFile);
        end
    end

    [w_samples, param_names, w_norm, shape_params] = ...
        buildWLHSDesign(spec, cfg, cfg.control_N_samples);

    active_mu = getWeightsForNames(spec.active_inputs, spec.weight_names, spec.mu_star_raw);

    metaWLHS = table( ...
        string(param_names(:)), ...
        active_mu(:), ...
        w_norm(:), ...
        shape_params(:), ...
        'VariableNames', {'Input','MuStarRaw','WeightMaxNorm','BetaShape'});

    writetable(metaWLHS, ...
        fullfile(spec.outRoot, 'campaign_wlhs_internal_weights.csv'));

    writetable(spec.weight_table, ...
        fullfile(spec.outRoot, 'functional_all_participant_weights.csv'));

    writetable(Tctx, ...
        fullfile(spec.outRoot, 'selected_joint_observed_contexts.csv'));

    fprintf('C_FUNC joint observed context selection: %d joint contexts x %d w samples x %d replicates = %d runs\n', ...
        height(Tctx), size(w_samples,1), cfg.replicates, ...
        height(Tctx) * size(w_samples,1) * cfg.replicates);

    runs = struct([]);
    run_id = 1;
    design_id = 1;

    for i = 1:height(Tctx)
        for j = 1:size(w_samples, 1)

            in = struct();

            % The joint observed row carries the whole observed context.
            in.luminosity = getAnyTableValue(Tctx, i, ...
                {'luminosity_level','luminosity'}, ...
                cfg.nominal.luminosity);

            in.size = getAnyTableValue(Tctx, i, ...
                {'target_blob_size','size'}, ...
                cfg.nominal.size);

            in.transparency = getAnyTableValue(Tctx, i, ...
                {'wall_transparency','transparency'}, ...
                cfg.nominal.transparency);

            in.v = getAnyTableValue(Tctx, i, ...
                {'v_nominal','v'}, ...
                cfg.nominal.v);

            in.friction = getAnyTableValue(Tctx, i, ...
                {'friction_surface','friction'}, ...
                cfg.nominal.friction);

            % Directly sampled C participant
            in.w = w_samples(j, 1);

            sdqReg = string(Tctx.sdq_regime(i));
            asReg  = string(Tctx.as_regime(i));
            jointCell = string(Tctx.joint_cell(i));

            for rep = 1:cfg.replicates
                runs(run_id).run_id = run_id;
                runs(run_id).design_id = design_id;
                runs(run_id).rep = rep;
                runs(run_id).scenario_id = cfg.scenario_id;
                runs(run_id).inputs = fillMissingInputsWithNominal(in, cfg);

                runs(run_id).label = sprintf( ...
                    'JOINT_%s_w_%03d_rep%d', ...
                    char(makeSafeLabel(jointCell)), j, rep);

                runs(run_id).source_joint_cell = jointCell;
                runs(run_id).joint_cell = jointCell;

                runs(run_id).sdq_regime = sdqReg;
                runs(run_id).as_regime = asReg;

                runs(run_id).source_regime_P = sdqReg;
                runs(run_id).source_regime_S = asReg;

                runs(run_id).source_srp_P = Tctx.sign_detection_quality(i);
                runs(run_id).source_srp_S = Tctx.average_segment_speed(i);

                runs(run_id).source_context_design_id = string(getAnyTableValue(Tctx, i, {'design_id'}, i));
                runs(run_id).source_context_campaign = string(getAnyTableValue(Tctx, i, {'source_campaign'}, ""));

                run_id = run_id + 1;
            end

            design_id = design_id + 1;
        end
    end

    executeCampaignRuns(cfg, spec, runs, {'w','luminosity','size','v','friction'});

    rawFile = fullfile(spec.outRoot, 'campaign_summary_runs_raw.csv');

    if exist(rawFile, 'file')
        Traw = readtable(rawFile);

        validityCol = [spec.target_srp '_validity'];

        if ismember(validityCol, Traw.Properties.VariableNames)
            Tvalid = Traw(isUsableMetricValidity(string(Traw.(validityCol))), :);
        else
            Tvalid = Traw(~isnan(Traw.(spec.target_srp)), :);
        end

        if ~isempty(Tvalid) && all(ismember({'joint_cell','sdq_regime','as_regime','w_gain'}, Tvalid.Properties.VariableNames))
            G = groupsummary(Tvalid, ...
                {'joint_cell','sdq_regime','as_regime','w_gain'}, ...
                'mean', ...
                {spec.target_srp});

            writetable(G, fullfile(spec.outRoot, ...
                'campaign_C_grouped_tracking_error_by_joint_cell_and_w.csv'));

            analyzeCJointCellSensitivity(G, spec, cfg);
        else
            warning('Could not compute C joint-cell grouped sensitivity because required metadata columns are missing.');
        end
    end
end


function val = getAnyTableValue(T, rowIdx, candidateNames, defaultVal)
    val = defaultVal;

    for i = 1:numel(candidateNames)
        nm = candidateNames{i};

        if any(strcmp(T.Properties.VariableNames, nm))
            x = T.(nm)(rowIdx);

            if isempty(x)
                val = defaultVal;
            elseif isnumeric(x) && any(isnan(x))
                val = defaultVal;
            else
                val = x;
            end

            return;
        end
    end
end

function analyzeCJointCellSensitivity(G, spec, cfg)
    yName = ['mean_' spec.target_srp];
    if ~ismember(yName, G.Properties.VariableNames)
        return;
    end

    G.sdq_level = regimeLabelToLevel(string(G.sdq_regime), cfg.joint_regime_labels);
    G.as_level  = regimeLabelToLevel(string(G.as_regime),  cfg.joint_regime_labels);

    wEffects = [];
    cells = unique(string(G.joint_cell));
    cells = cells(strlength(cells) > 0);

    for i = 1:numel(cells)
        Gsub = G(string(G.joint_cell) == cells(i), :);
        Gsub = sortrows(Gsub, 'w_gain');
        if height(Gsub) < 2
            continue;
        end
        eff = diff(Gsub.(yName)) ./ diff(Gsub.w_gain);
        wEffects = [wEffects; eff(:)]; %#ok<AGROW>
    end

    sdqEffects = [];
    asVals = unique(G.as_level(~isnan(G.as_level)));
    wVals = unique(G.w_gain);
    for ia = 1:numel(asVals)
        for iw = 1:numel(wVals)
            mask = G.as_level == asVals(ia) & G.w_gain == wVals(iw);
            Gsub = G(mask, :);
            if height(Gsub) < 2
                continue;
            end
            Gsub = sortrows(Gsub, 'sdq_level');
            eff = diff(Gsub.(yName)) ./ diff(Gsub.sdq_level);
            sdqEffects = [sdqEffects; eff(:)]; %#ok<AGROW>
        end
    end

    asEffects = [];
    sdqVals = unique(G.sdq_level(~isnan(G.sdq_level)));
    for isd = 1:numel(sdqVals)
        for iw = 1:numel(wVals)
            mask = G.sdq_level == sdqVals(isd) & G.w_gain == wVals(iw);
            Gsub = G(mask, :);
            if height(Gsub) < 2
                continue;
            end
            Gsub = sortrows(Gsub, 'as_level');
            eff = diff(Gsub.(yName)) ./ diff(Gsub.as_level);
            asEffects = [asEffects; eff(:)]; %#ok<AGROW>
        end
    end

    factorNames = strings(0,1);
    muStars = [];
    sigmas = [];
    numEffects = [];

    if ~isempty(sdqEffects)
        factorNames(end+1,1) = "SDQ_regime"; %#ok<AGROW>
        muStars(end+1,1) = mean(abs(sdqEffects), 'omitnan'); %#ok<AGROW>
        sigmas(end+1,1) = std(sdqEffects, 0, 'omitnan'); %#ok<AGROW>
        numEffects(end+1,1) = numel(sdqEffects); %#ok<AGROW>
    end

    if ~isempty(asEffects)
        factorNames(end+1,1) = "AS_regime"; %#ok<AGROW>
        muStars(end+1,1) = mean(abs(asEffects), 'omitnan'); %#ok<AGROW>
        sigmas(end+1,1) = std(asEffects, 0, 'omitnan'); %#ok<AGROW>
        numEffects(end+1,1) = numel(asEffects); %#ok<AGROW>
    end

    if ~isempty(wEffects)
        factorNames(end+1,1) = "w_gain"; %#ok<AGROW>
        muStars(end+1,1) = mean(abs(wEffects), 'omitnan'); %#ok<AGROW>
        sigmas(end+1,1) = std(wEffects, 0, 'omitnan'); %#ok<AGROW>
        numEffects(end+1,1) = numel(wEffects); %#ok<AGROW>
    end

    factorSens = table(factorNames, muStars, sigmas, numEffects, ...
        'VariableNames', {'Factor','MuStar','Sigma','NumEffects'});

    writetable(factorSens, fullfile(spec.outRoot, 'campaign_C_functional_factor_sensitivity.csv'));
end

function levels = regimeLabelToLevel(labels, regimeLabels)
    levels = nan(size(labels));
    for i = 1:numel(regimeLabels)
        levels(labels == string(regimeLabels{i})) = i;
    end
end

function values = getWeightsForNames(requestedNames, allNames, allValues)
    values = nan(1, numel(requestedNames));

    allNorm = normalizeFactorName(string(allNames));

    for i = 1:numel(requestedNames)
        reqNorm = normalizeFactorName(string(requestedNames{i}));
        idx = find(allNorm == reqNorm, 1, 'first');

        if isempty(idx)
            error('No weight found for input %s. Available weights: %s', ...
                string(requestedNames{i}), strjoin(string(allNames), ', '));
        end

        values(i) = allValues(idx);
    end
end

function x = normalizeFactorName(x)
    x = lower(string(x));
    x = replace(x, "_", "");
    x = replace(x, " ", "");
    x = replace(x, "-", "");
end

function s = makeSafeLabel(s)
    s = string(s);
    s = replace(s, " ", "_");
    s = replace(s, "-", "_");
    s = replace(s, "__", "_");
    s = regexprep(s, '[^A-Za-z0-9_]', '_');
end