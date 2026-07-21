function runControlRegimeCampaign(cfg)
    spec = makeCampaignSpec(cfg, "C");
    outRoot = spec.outRoot;
    if ~exist(outRoot, 'dir')
        mkdir(outRoot);
    end

    repFileP = fullfile(cfg.base_out_root, 'campaign_P_perception', 'sign_detection_quality_representatives.csv');
    repFileS = fullfile(cfg.base_out_root, 'campaign_S_slippery', 'average_segment_speed_representatives.csv');
    if ~exist(repFileP, 'file')
        error('Missing representative scenarios from P: %s', repFileP);
    end
    if ~exist(repFileS, 'file')
        error('Missing representative scenarios from S: %s', repFileS);
    end

    TrepP = readtable(repFileP);
    TrepS = readtable(repFileS);
    regimeColP = char(findRegimeColumn(TrepP));
    regimeColS = char(findRegimeColumn(TrepS));
    w_grid = cfg.control_w_grid;

    fprintf('Campaign C planned runs: %d P reps x %d S reps x %d w values x %d replicates = %d runs\n', ...
        height(TrepP), height(TrepS), numel(w_grid), cfg.replicates, ...
        height(TrepP) * height(TrepS) * numel(w_grid) * cfg.replicates);

    runs = struct([]);
    idx = 1;
    for i = 1:height(TrepP)
        for k = 1:height(TrepS)
            for j = 1:numel(w_grid)
                in = struct();
                in.luminosity = getAnyTableValue(TrepP, i, {'luminosity_level','luminosity'}, cfg.nominal.luminosity);
                in.size = getAnyTableValue(TrepP, i, {'target_blob_size','size'}, cfg.nominal.size);
                in.transparency = getAnyTableValue(TrepP, i, {'wall_transparency','transparency'}, cfg.nominal.transparency);
                in.v = getAnyTableValue(TrepS, k, {'v_nominal','v'}, cfg.nominal.v);
                in.friction = getAnyTableValue(TrepS, k, {'friction_surface','friction'}, cfg.nominal.friction);
                in.w = w_grid(j);

                for rep = 1:cfg.replicates
                    runs(idx).run_id = idx;
                    runs(idx).design_id = idx;
                    runs(idx).rep = rep;
                    runs(idx).scenario_id = cfg.scenario_id;
                    runs(idx).inputs = fillMissingInputsWithNominal(in, cfg);
                    pReg = string(TrepP.(regimeColP)(i));
                    sReg = string(TrepS.(regimeColS)(k));
                    runs(idx).label = sprintf('Preg_%s_Sreg_%s_w_%02d_rep%d', char(pReg), char(sReg), j, rep);
                    runs(idx).source_regime_P = pReg;
                    runs(idx).source_regime_S = sReg;
                    runs(idx).source_scenario_id_P = string(getAnyTableValue(TrepP, i, {'design_id'}, i));
                    runs(idx).source_scenario_id_S = string(getAnyTableValue(TrepS, k, {'design_id'}, k));
                    idx = idx + 1;
                end
            end
        end
    end

    summary_template = makeEmptySummaryRow();
    summary_rows = repmat(summary_template, numel(runs), 1);
    campaign_results = repmat(struct('meta', struct(), 'srp', struct(), 'eval_info', struct(), 'status', "", 'error', "", 'attempts_used', NaN), numel(runs), 1);

    checkVMConnectivity(cfg);
    load_system(cfg.modelName);

    simPID = "";
    for run_idx = 1:numel(runs)
        [summary_rows(run_idx), campaign_results(run_idx), simPID] = ...
            executeSingleRun(cfg, spec.campaign_id, runs(run_idx), spec.target_srp, simPID, outRoot);
        save(fullfile(outRoot, 'campaign_checkpoint.mat'), 'campaign_results', 'summary_rows', 'runs');
    end

    safeCleanup(cfg, simPID);
    try
        bdclose(cfg.modelName);
    catch
    end

    save(fullfile(outRoot, 'campaign_results_final.mat'), 'campaign_results', 'summary_rows', 'runs');

    T_raw = struct2table(summary_rows);
    T_raw.source_regime_P = strings(height(T_raw),1);
    T_raw.source_regime_S = strings(height(T_raw),1);
    T_raw.source_scenario_id_P = strings(height(T_raw),1);
    T_raw.source_scenario_id_S = strings(height(T_raw),1);
    for i = 1:height(T_raw)
        T_raw.source_regime_P(i) = runs(i).source_regime_P;
        T_raw.source_regime_S(i) = runs(i).source_regime_S;
        T_raw.source_scenario_id_P(i) = runs(i).source_scenario_id_P;
        T_raw.source_scenario_id_S(i) = runs(i).source_scenario_id_S;
    end
    writetable(T_raw, fullfile(outRoot, 'campaign_summary_runs_raw.csv'));

    validityCol = 'tracking_error_rms_validity';
    if ismember(validityCol, T_raw.Properties.VariableNames)
        T_valid = T_raw(ismember(string(T_raw.(validityCol)), ["VALID", "VALID_ZERO"]), :);
    else
        T_valid = T_raw(~isnan(T_raw.tracking_error_rms), :);
    end
    writetable(T_valid, fullfile(outRoot, 'campaign_summary_valid_only.csv'));

    if ~isempty(T_valid)
        G = groupsummary(T_valid, {'source_regime_P', 'source_regime_S', 'w_gain'}, 'mean', {'tracking_error_rms'});
        writetable(G, fullfile(outRoot, 'campaign_grouped_tracking_error_by_Pregime_Sregime_and_w.csv'));
        analyzeControlRegimeSensitivity(G, outRoot);
    else
        warning('Campaign C produced no valid tracking_error_rms rows.');
    end

    fprintf('Campaign C finished.\n');
end

function analyzeControlRegimeSensitivity(G, outRoot)
    yName = 'mean_tracking_error_rms';
    if ~ismember(yName, G.Properties.VariableNames)
        error('Expected grouped column %s not found.', yName);
    end

    wMin = min(G.w_gain);
    wMax = max(G.w_gain);

    pairRows = table(strings(0,1), strings(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'source_regime_P','source_regime_S', ...
        'MuStarWComparable','SigmaWComparable', ...
        'MuStarWRawChange','SigmaWRawChange', ...
        'MuStarWOriginalUnitSlope','SigmaWOriginalUnitSlope', ...
        'NumEffects'});

    pRegs = sortOrderedLevels(unique(string(G.source_regime_P)));
    sRegs = sortOrderedLevels(unique(string(G.source_regime_S)));

    for ip = 1:numel(pRegs)
        for is = 1:numel(sRegs)
            mask = string(G.source_regime_P) == pRegs(ip) & string(G.source_regime_S) == sRegs(is);
            Gsub = sortrows(G(mask, :), 'w_gain');
            if height(Gsub) < 2
                continue;
            end

            dy = diff(Gsub.(yName));
            rawEff = dy;
            dz = diff(normalizeToUnitInterval(Gsub.w_gain, wMin, wMax));
            compEff = dy ./ dz;
            dw = diff(Gsub.w_gain);
            slopeEff = dy ./ dw;

            stats = summarizeEffectSet(compEff, rawEff, slopeEff);

            pairRows = [pairRows; table(pRegs(ip), sRegs(is), ...
                stats.MuStarComparable, stats.SigmaComparable, ...
                stats.MuStarRawChange, stats.SigmaRawChange, ...
                stats.MuStarOriginalUnitSlope, stats.SigmaOriginalUnitSlope, ...
                stats.NumEffects, ...
                'VariableNames', {'source_regime_P','source_regime_S', ...
                'MuStarWComparable','SigmaWComparable', ...
                'MuStarWRawChange','SigmaWRawChange', ...
                'MuStarWOriginalUnitSlope','SigmaWOriginalUnitSlope', ...
                'NumEffects'})]; %#ok<AGROW>
        end
    end
    writetable(pairRows, fullfile(outRoot, 'campaign_C_regime_pair_sensitivity.csv'));

    pComp = [];
    pRaw = [];
    sComp = [];
    sRaw = [];
    wComp = [];
    wRaw = [];
    wSlope = [];

    wVals = unique(G.w_gain);

    % Ordered adjacent effects for P_regime at fixed S_regime and w_gain
    for is = 1:numel(sRegs)
        for iw = 1:numel(wVals)
            mask = string(G.source_regime_S) == sRegs(is) & G.w_gain == wVals(iw);
            Gsub = G(mask, :);
            if height(Gsub) < 2
                continue;
            end

            presentP = sortOrderedLevels(unique(string(Gsub.source_regime_P)));
            for k = 1:(numel(presentP) - 1)
                lblA = presentP(k);
                lblB = presentP(k + 1);
                idxA = find(string(Gsub.source_regime_P) == lblA, 1, 'first');
                idxB = find(string(Gsub.source_regime_P) == lblB, 1, 'first');
                if isempty(idxA) || isempty(idxB)
                    continue;
                end

                dy = Gsub.(yName)(idxB) - Gsub.(yName)(idxA);
                rawEff = dy;
                zA = orderedLevelToUnitInterval(lblA, pRegs);
                zB = orderedLevelToUnitInterval(lblB, pRegs);
                dz = zB - zA;
                compEff = dy / dz;

                pRaw(end+1,1) = rawEff; %#ok<AGROW>
                pComp(end+1,1) = compEff; %#ok<AGROW>
            end
        end
    end

    % Ordered adjacent effects for S_regime at fixed P_regime and w_gain
    for ip = 1:numel(pRegs)
        for iw = 1:numel(wVals)
            mask = string(G.source_regime_P) == pRegs(ip) & G.w_gain == wVals(iw);
            Gsub = G(mask, :);
            if height(Gsub) < 2
                continue;
            end

            presentS = sortOrderedLevels(unique(string(Gsub.source_regime_S)));
            for k = 1:(numel(presentS) - 1)
                lblA = presentS(k);
                lblB = presentS(k + 1);
                idxA = find(string(Gsub.source_regime_S) == lblA, 1, 'first');
                idxB = find(string(Gsub.source_regime_S) == lblB, 1, 'first');
                if isempty(idxA) || isempty(idxB)
                    continue;
                end

                dy = Gsub.(yName)(idxB) - Gsub.(yName)(idxA);
                rawEff = dy;
                zA = orderedLevelToUnitInterval(lblA, sRegs);
                zB = orderedLevelToUnitInterval(lblB, sRegs);
                dz = zB - zA;
                compEff = dy / dz;

                sRaw(end+1,1) = rawEff; %#ok<AGROW>
                sComp(end+1,1) = compEff; %#ok<AGROW>
            end
        end
    end

    % w_gain effects inside each joint regime cell
    for ip = 1:numel(pRegs)
        for is = 1:numel(sRegs)
            mask = string(G.source_regime_P) == pRegs(ip) & string(G.source_regime_S) == sRegs(is);
            Gsub = sortrows(G(mask, :), 'w_gain');
            if height(Gsub) < 2
                continue;
            end

            dy = diff(Gsub.(yName));
            rawEff = dy;
            dz = diff(normalizeToUnitInterval(Gsub.w_gain, wMin, wMax));
            compEff = dy ./ dz;
            dw = diff(Gsub.w_gain);
            slopeEff = dy ./ dw;

            wRaw = [wRaw; rawEff]; %#ok<AGROW>
            wComp = [wComp; compEff]; %#ok<AGROW>
            wSlope = [wSlope; slopeEff]; %#ok<AGROW>
        end
    end

    factorNames = strings(0,1);
    muStarsComparable = [];
    sigmasComparable = [];
    muStarsRawChange = [];
    sigmasRawChange = [];
    muStarsOriginalUnitSlope = [];
    sigmasOriginalUnitSlope = [];
    numEffects = [];

    if ~isempty(pComp)
        stats = summarizeEffectSet(pComp, pRaw, []);
        factorNames(end+1,1) = "P_regime"; %#ok<AGROW>
        muStarsComparable(end+1,1) = stats.MuStarComparable; %#ok<AGROW>
        sigmasComparable(end+1,1) = stats.SigmaComparable; %#ok<AGROW>
        muStarsRawChange(end+1,1) = stats.MuStarRawChange; %#ok<AGROW>
        sigmasRawChange(end+1,1) = stats.SigmaRawChange; %#ok<AGROW>
        muStarsOriginalUnitSlope(end+1,1) = stats.MuStarOriginalUnitSlope; %#ok<AGROW>
        sigmasOriginalUnitSlope(end+1,1) = stats.SigmaOriginalUnitSlope; %#ok<AGROW>
        numEffects(end+1,1) = stats.NumEffects; %#ok<AGROW>
    end

    if ~isempty(sComp)
        stats = summarizeEffectSet(sComp, sRaw, []);
        factorNames(end+1,1) = "S_regime"; %#ok<AGROW>
        muStarsComparable(end+1,1) = stats.MuStarComparable; %#ok<AGROW>
        sigmasComparable(end+1,1) = stats.SigmaComparable; %#ok<AGROW>
        muStarsRawChange(end+1,1) = stats.MuStarRawChange; %#ok<AGROW>
        sigmasRawChange(end+1,1) = stats.SigmaRawChange; %#ok<AGROW>
        muStarsOriginalUnitSlope(end+1,1) = stats.MuStarOriginalUnitSlope; %#ok<AGROW>
        sigmasOriginalUnitSlope(end+1,1) = stats.SigmaOriginalUnitSlope; %#ok<AGROW>
        numEffects(end+1,1) = stats.NumEffects; %#ok<AGROW>
    end

    if ~isempty(wComp)
        stats = summarizeEffectSet(wComp, wRaw, wSlope);
        factorNames(end+1,1) = "w_gain"; %#ok<AGROW>
        muStarsComparable(end+1,1) = stats.MuStarComparable; %#ok<AGROW>
        sigmasComparable(end+1,1) = stats.SigmaComparable; %#ok<AGROW>
        muStarsRawChange(end+1,1) = stats.MuStarRawChange; %#ok<AGROW>
        sigmasRawChange(end+1,1) = stats.SigmaRawChange; %#ok<AGROW>
        muStarsOriginalUnitSlope(end+1,1) = stats.MuStarOriginalUnitSlope; %#ok<AGROW>
        sigmasOriginalUnitSlope(end+1,1) = stats.SigmaOriginalUnitSlope; %#ok<AGROW>
        numEffects(end+1,1) = stats.NumEffects; %#ok<AGROW>
    end

    weightMaxNorm = normalizeNonnegativeMax(muStarsComparable);
    weightSumNorm = normalizeNonnegativeSum(muStarsComparable);

    % MuStar / Sigma are kept as aliases to the comparable values so
    % downstream code can keep reading the same column names.
    factorSens = table(factorNames, muStarsComparable, sigmasComparable, ...
        muStarsComparable, sigmasComparable, ...
        muStarsRawChange, sigmasRawChange, ...
        muStarsOriginalUnitSlope, sigmasOriginalUnitSlope, ...
        weightMaxNorm, weightSumNorm, numEffects, ...
        'VariableNames', {'Factor','MuStar','Sigma', ...
        'MuStarComparable','SigmaComparable', ...
        'MuStarRawChange','SigmaRawChange', ...
        'MuStarOriginalUnitSlope','SigmaOriginalUnitSlope', ...
        'WeightMaxNorm','WeightSumNorm','NumEffects'});

    writetable(factorSens, fullfile(outRoot, 'campaign_C_factor_sensitivity.csv'));
end

function regimeCol = findRegimeColumn(T)
    names = string(T.Properties.VariableNames);
    if any(names == "regime_label")
        regimeCol = "regime_label";
        return;
    end
    regimeCandidates = names(endsWith(names, "_regime"));
    if numel(regimeCandidates) == 1
        regimeCol = regimeCandidates(1);
    elseif isempty(regimeCandidates)
        error('No regime column found.');
    else
        error('Multiple regime columns found: %s', strjoin(cellstr(regimeCandidates), ', '));
    end
end


function val = getAnyTableValue(T, rowIdx, candidateNames, defaultVal)
    val = defaultVal;
    for i = 1:numel(candidateNames)
        nm = candidateNames{i};
        if any(strcmp(T.Properties.VariableNames, nm))
            x = T.(nm)(rowIdx);
            if isempty(x) || (isnumeric(x) && any(isnan(x)))
                val = defaultVal;
            else
                val = x;
            end
            return;
        end
    end
end

function in = fillMissingInputsWithNominal(in, cfg)
    if ~isfield(in, 'v'), in.v = cfg.nominal.v; end
    if ~isfield(in, 'w'), in.w = cfg.nominal.w; end
    if ~isfield(in, 'size'), in.size = cfg.nominal.size; end
    if ~isfield(in, 'friction'), in.friction = cfg.nominal.friction; end
    if ~isfield(in, 'luminosity'), in.luminosity = cfg.nominal.luminosity; end
    if ~isfield(in, 'transparency'), in.transparency = cfg.nominal.transparency; end
end

