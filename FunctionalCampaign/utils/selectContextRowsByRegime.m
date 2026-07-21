function Tsel = selectContextRowsByRegime(T, metric, nPerRegime)
    if isempty(T)
        Tsel = T;
        return;
    end

    regimeCol = findRegimeColumnLocal(T, metric);

    if ~ismember(metric, T.Properties.VariableNames)
        error('Metric column %s not found. Available columns: %s', ...
            metric, strjoin(T.Properties.VariableNames, ', '));
    end

    regimes = unique(string(T.(regimeCol)));
    regimes = regimes(strlength(regimes) > 0);

    Tsel = T([],:);

    for r = 1:numel(regimes)
        mask = string(T.(regimeCol)) == regimes(r);
        Treg = T(mask, :);

        vals = Treg.(metric);
        good = ~isnan(vals);
        Treg = Treg(good, :);
        vals = vals(good);

        if isempty(Treg)
            continue;
        end

        [~, order] = sort(vals);
        Treg = Treg(order, :);

        if height(Treg) <= nPerRegime
            Tsel = [Tsel; Treg]; %#ok<AGROW>
        else
            idx = unique(round(linspace(1, height(Treg), nPerRegime)));
            Tsel = [Tsel; Treg(idx, :)]; %#ok<AGROW>
        end
    end
end


function regimeCol = findRegimeColumnLocal(T, metric)
    names = string(T.Properties.VariableNames);

    if any(names == "regime_label")
        regimeCol = "regime_label";
        return;
    end

    preferred = string(metric) + "_regime";
    if any(names == preferred)
        regimeCol = preferred;
        return;
    end

    candidates = names(endsWith(names, "_regime"));

    if numel(candidates) == 1
        regimeCol = candidates(1);
    elseif isempty(candidates)
        error('No regime column found. Available columns: %s', ...
            strjoin(names, ', '));
    else
        error('Multiple regime columns found: %s', ...
            strjoin(candidates, ', '));
    end
end
