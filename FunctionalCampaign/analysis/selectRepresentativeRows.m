function repRows = selectRepresentativeRows(T_valid, metric)

    regimeCol = [metric '_regime'];
    repRows = T_valid([],:);
    regimes = unique(string(T_valid.(regimeCol)));
    regimes = regimes(strlength(regimes) > 0);
    for i = 1:numel(regimes)
        T_reg = T_valid(string(T_valid.(regimeCol)) == regimes(i), :);
        if isempty(T_reg), continue; end
        targetVal = median(T_reg.(metric), 'omitnan');
        [~, idxBest] = min(abs(T_reg.(metric) - targetVal));
        repRows = [repRows; T_reg(idxBest, :)]; %#ok<AGROW>
    end
end
