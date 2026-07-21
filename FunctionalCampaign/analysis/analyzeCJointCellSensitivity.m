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
