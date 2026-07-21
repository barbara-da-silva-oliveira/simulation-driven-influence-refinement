function mu_raw = readFactorMuStarFromCampaign(campaignDir, candidateFiles, names)
    mu_raw = nan(1, numel(names));
    T = [];

    for i = 1:numel(candidateFiles)
        f = fullfile(campaignDir, candidateFiles{i});
        if exist(f, 'file')
            T = readSensitivityTableRobust(f);
            if ~isempty(T)
                break;
            end
        end
    end

    if isempty(T) || width(T) == 0
        return;
    end

    if ismember('Factor', T.Properties.VariableNames)
        factorColRaw = string(T.Factor);
    elseif ismember('Parameter', T.Properties.VariableNames)
        factorColRaw = string(T.Parameter);
    else
        warning('Expected a Factor or Parameter column in %s, but found: %s', ...
            campaignDir, strjoin(T.Properties.VariableNames, ', '));
        return;
    end

    muCol = findMuStarColumn(T, "");
    factorCol = normalizeFactorName(factorColRaw);

    for k = 1:numel(names)
        want = normalizeFactorName(string(names{k}));
        idx = find(factorCol == want, 1, 'first');
        if ~isempty(idx)
            mu_raw(k) = T.(muCol)(idx);
        end
    end
end
