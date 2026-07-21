function mu_raw = readCampaignCFactorWeights(campaignDir, factorNames)
    f = fullfile(campaignDir, 'campaign_C_factor_sensitivity.csv');

    if ~exist(f, 'file')
        error('Missing Campaign C factor sensitivity file: %s', f);
    end

    T = readtable(f);

    if ~ismember('Factor', T.Properties.VariableNames)
        error('Expected column Factor in %s. Found columns: %s', ...
            f, strjoin(T.Properties.VariableNames, ', '));
    end

    % Prefer comparable Morris-like effect values.
    % Fall back to MuStar if MuStarComparable is not available.
    if ismember('MuStarComparable', T.Properties.VariableNames)
        valueCol = 'MuStarComparable';
    elseif ismember('MuStar', T.Properties.VariableNames)
        valueCol = 'MuStar';
    else
        error('Expected MuStarComparable or MuStar in %s. Found columns: %s', ...
            f, strjoin(T.Properties.VariableNames, ', '));
    end

    factorsNorm = normalizeFactorName(string(T.Factor));
    mu_raw = nan(1, numel(factorNames));

    for i = 1:numel(factorNames)
        targetNorm = normalizeFactorName(string(factorNames{i}));
        idx = find(factorsNorm == targetNorm, 1, 'first');

        if isempty(idx)
            error('Could not find factor %s in %s. Available factors: %s', ...
                string(factorNames{i}), f, strjoin(string(T.Factor), ', '));
        end

        mu_raw(i) = T.(valueCol)(idx);
    end
end