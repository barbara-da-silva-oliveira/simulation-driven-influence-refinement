function values = getWeightsForNames(requestedNames, allNames, allValues)
    requestedNames = string(requestedNames(:));
    allNames = string(allNames(:));
    allValues = allValues(:);

    if numel(allNames) ~= numel(allValues)
        error('Number of names (%d) does not match number of values (%d). Names: %s', ...
            numel(allNames), numel(allValues), strjoin(allNames, ', '));
    end

    allNorm = localNormalizeName(allNames);
    values = nan(numel(requestedNames), 1);

    for i = 1:numel(requestedNames)
        req = requestedNames(i);
        aliases = localParticipantAliases(req);
        aliasNorm = localNormalizeName(aliases);

        mask = false(size(allNorm));

        for a = 1:numel(aliasNorm)
            mask = mask | strcmp(allNorm, aliasNorm(a));
        end

        idx = find(mask, 1, 'first');

        if isempty(idx)
            debugTable = table(allNames(:), allNorm(:), ...
                'VariableNames', {'OriginalName','NormalizedName'});
            disp(debugTable);

            fprintf('Requested input: %s\n', req);
            fprintf('Requested aliases after normalization:\n');
            disp(aliasNorm(:));

            error('No weight found for input %s. Available weights: %s', ...
                req, strjoin(allNames, ', '));
        end

        values(i) = allValues(idx);
    end

    values = values(:).';
end

function x = localNormalizeName(x)
    x = lower(strtrim(string(x)));
    x = regexprep(x, '[^a-z0-9]', '');
end

function aliases = localParticipantAliases(name)
    n = localNormalizeName(string(name));

    switch char(n)
        case 'w'
            aliases = ["w", "w_gain", "wgain", "controller_gain"];

        case 'signdetectionquality'
            aliases = ["sign_detection_quality", ...
                       "signdetectionquality", ...
                       "sdq", ...
                       "sdq_regime", ...
                       "p_regime", ...
                       "perception_regime"];

        case 'averagesegmentspeed'
            aliases = ["average_segment_speed", ...
                       "averagesegmentspeed", ...
                       "as", ...
                       "as_regime", ...
                       "s_regime", ...
                       "slippery_regime"];

        otherwise
            aliases = string(name);
    end
end