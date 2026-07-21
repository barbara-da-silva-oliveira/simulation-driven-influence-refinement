function muCol = findMuStarColumn(T, metricHint)
    vars = string(T.Properties.VariableNames);

    varsNorm = lower(vars);
    varsNorm = replace(varsNorm, "_", "");
    varsNorm = replace(varsNorm, " ", "");

    metricNorm = lower(string(metricHint));
    metricNorm = replace(metricNorm, "_", "");
    metricNorm = replace(metricNorm, " ", "");

    % 1) exact generic names
    genericCandidates = ["mustar", "mustarraw", "mustarvalue", "mustarmean", "mustaravg", "mustarabsolute"];
    idx = find(ismember(varsNorm, genericCandidates), 1, 'first');
    if ~isempty(idx)
        muCol = char(vars(idx));
        return;
    end

    % 2) metric-specific names like sign_detection_quality_MuStar
    idx = find(contains(varsNorm, metricNorm) & contains(varsNorm, "mustar"), 1, 'first');
    if ~isempty(idx)
        muCol = char(vars(idx));
        return;
    end

    % 3) looser fallback: any column containing both "mu" and "star"
    idx = find(contains(varsNorm, "mu") & contains(varsNorm, "star"), 1, 'first');
    if ~isempty(idx)
        muCol = char(vars(idx));
        return;
    end

    error('No MuStar column found. Available columns are: %s', strjoin(vars, ', '));
end
