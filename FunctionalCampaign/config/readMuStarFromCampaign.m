function mu_raw = readMuStarFromCampaign(campaignDir, candidateFiles, names, metricHint)
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
        error('Could not read a structural sensitivity table in %s', campaignDir);
    end

    if ismember('Parameter', T.Properties.VariableNames)
        paramCol = string(T.Parameter);
    elseif ismember('Factor', T.Properties.VariableNames)
        paramCol = string(T.Factor);
    else
        error('Expected a Parameter or Factor column in %s. Found: %s', ...
            campaignDir, strjoin(T.Properties.VariableNames, ', '));
    end
    muCol = findMuStarColumn(T, metricHint);

    for k = 1:numel(names)
        idx = find(normalizeParamName(paramCol) == normalizeParamName(string(names{k})), 1, 'first');
        if isempty(idx)
            error('Parameter %s not found in structural sensitivity table %s', ...
                names{k}, campaignDir);
        end
        mu_raw(k) = T.(muCol)(idx);
    end
end
