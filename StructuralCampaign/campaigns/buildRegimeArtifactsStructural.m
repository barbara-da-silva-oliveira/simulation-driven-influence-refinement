function buildRegimeArtifactsStructural(cfg, spec)
    fprintf('=== Building regimes for %s ===\n', spec.name);

    metric = inferCampaignMetric(spec);
    outRoot = spec.outRoot;
    T = readtable(fullfile(outRoot, 'campaign_summary_design_aggregated.csv'));

    if ~ismember(metric, T.Properties.VariableNames)
        error('Metric column %s not found in aggregated campaign file.', metric);
    end

    validityCol = [metric '_validity'];
    if ismember(validityCol, T.Properties.VariableNames)
        usableMask = isUsableMetricValidity(string(T.(validityCol)));
    else
        usableMask = ~isnan(T.(metric));
    end
    T_valid = T(usableMask, :);
    if isempty(T_valid)
        error('No usable rows found for metric %s.', metric);
    end

    vals = T_valid.(metric);
    vals = vals(~isnan(vals));
    labels = {'Low','High'};
    q = quantile(vals, [0 0.5 1]);

    regimeCol = [metric '_regime'];
    T_valid.(regimeCol) = strings(height(T_valid),1);
    for i = 1:height(T_valid)
        x = T_valid.(metric)(i);
        if ~isnan(x)
            T_valid.(regimeCol)(i) = assignRegimeLabel(x, q, labels);
        else
            T_valid.(regimeCol)(i) = "";
        end
    end
    T_valid.regime_label = T_valid.(regimeCol);

    repRows = selectRepresentativeRows(T_valid, metric);
    if ~isempty(repRows)
        repRows.regime_label = repRows.(regimeCol);
    end

    writetable(T_valid, fullfile(outRoot, sprintf('%s_valid_with_regimes.csv', metric)));
    writetable(repRows, fullfile(outRoot, sprintf('%s_representatives.csv', metric)));
    regimeDef = table(labels(:), q(1:end-1)', q(2:end)', 'VariableNames', {'Regime','LowerBound','UpperBound'});
    writetable(regimeDef, fullfile(outRoot, sprintf('%s_regime_thresholds.csv', metric)));

    fprintf('Regime files written in %s\n', outRoot);
end

function label = assignRegimeLabel(x, q, labels)
    n = numel(labels);
    label = string(labels{end});
    if isnan(x)
        label = "";
        return;
    end
    for k = 1:n
        lo = q(k);
        hi = q(k+1);
        if k < n
            if x >= lo && x < hi
                label = string(labels{k});
                return;
            end
        else
            if x >= lo && x <= hi
                label = string(labels{k});
                return;
            end
        end
    end
end

function repRows = selectRepresentativeRows(T_valid, metric)
    regimeCol = [metric '_regime'];
    repRows = T_valid([],:);
    regimes = unique(string(T_valid.(regimeCol)));
    regimes = regimes(strlength(regimes) > 0);

    for i = 1:numel(regimes)
        T_reg = T_valid(string(T_valid.(regimeCol)) == regimes(i), :);
        vals = double(T_reg.(metric));
        validIdx = ~isnan(vals);
        T_reg = T_reg(validIdx,:);
        vals = vals(validIdx);
        if isempty(T_reg)
            continue;
        end
        targetVal = median(vals, 'omitnan');
        [~, idxBest] = min(abs(vals - targetVal));
        repRows = [repRows; T_reg(idxBest,:)]; %#ok<AGROW>
    end
end



function metric = inferCampaignMetric(spec)
    switch upper(string(spec.name))
        case "M"
            metric = 'time_turning';
        case "P"
            metric = 'sign_detection_quality';
        case "S"
            metric = 'average_segment_speed';
        case "C"
            metric = 'tracking_error_rms';
        otherwise
            error('Could not infer metric for campaign %s', string(spec.name));
    end
end