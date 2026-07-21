function buildRegimeArtifacts(cfg, spec)
    metric = inferMetricFromSpec(spec);
    T = readtable(fullfile(spec.outRoot, 'campaign_summary_design_aggregated.csv'));
    validityCol = [metric '_validity'];
    if ismember(validityCol, T.Properties.VariableNames)
        usableMask = isUsableMetricValidity(string(T.(validityCol)));
    else
        usableMask = ~isnan(T.(metric));
    end
    T_valid = T(usableMask, :);
    if isempty(T_valid), error('No usable design rows found for regime construction in %s', spec.outRoot); end
    vals = T_valid.(metric); vals = vals(~isnan(vals));
    q = quantile(vals, linspace(0,1,cfg.regime_count+1));
    regimeCol = [metric '_regime'];
    T_valid.(regimeCol) = strings(height(T_valid),1);
    for i = 1:height(T_valid)
        T_valid.(regimeCol)(i) = assignRegimeLabel(T_valid.(metric)(i), q, cfg.regime_labels);
    end
    T_valid.regime_label = T_valid.(regimeCol);
    repRows = selectRepresentativeRows(T_valid, metric);
    if ~isempty(repRows), repRows.regime_label = repRows.(regimeCol); end
    writetable(T_valid, fullfile(spec.outRoot, sprintf('%s_valid_with_regimes.csv', metric)));
    writetable(repRows, fullfile(spec.outRoot, sprintf('%s_representatives.csv', metric)));
    regimeDef = table(string(cfg.regime_labels(:)), q(1:end-1)', q(2:end)', 'VariableNames', {'Regime','LowerBound','UpperBound'});
    writetable(regimeDef, fullfile(spec.outRoot, sprintf('%s_regime_thresholds.csv', metric)));
end


function metric = inferMetricFromSpec(spec)
    switch upper(string(spec.name))
        case 'P_FUNC', metric = 'sign_detection_quality';
        case 'S_FUNC', metric = 'average_segment_speed';
        case 'C_FUNC', metric = 'tracking_error_rms';
        otherwise, error('Could not infer metric from spec %s', spec.name);
    end
end
