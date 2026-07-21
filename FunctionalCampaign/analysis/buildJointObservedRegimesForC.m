function buildJointObservedRegimesForC(cfg)
    spec = makeFunctionalSpec(cfg, "C_FUNC");

    TP = readAggregatedCampaignTable(cfg.dirPFunc);
    TS = readAggregatedCampaignTable(cfg.dirSFunc);

    metricSDQ = 'sign_detection_quality';
    metricAS  = 'average_segment_speed';

    sdqVals = getUsableMetricValues(TP, metricSDQ);
    asVals  = getUsableMetricValues(TS, metricAS);

    if isempty(sdqVals)
        error('No usable SDQ values found in P_FUNC aggregated table.');
    end
    if isempty(asVals)
        error('No usable AS values found in S_FUNC aggregated table.');
    end

    q_sdq = quantile(sdqVals, linspace(0, 1, numel(cfg.joint_regime_labels) + 1));
    q_as  = quantile(asVals,  linspace(0, 1, numel(cfg.joint_regime_labels) + 1));

    Tpool = poolObservedRows(TP, TS);

    usableSDQ = getUsableMetricMask(Tpool, metricSDQ);
    usableAS  = getUsableMetricMask(Tpool, metricAS);
    bothMask = usableSDQ & usableAS & ~isnan(Tpool.(metricSDQ)) & ~isnan(Tpool.(metricAS));
    Tpool = Tpool(bothMask, :);

    if isempty(Tpool)
        error('No jointly observed usable rows found after pooling P_FUNC and S_FUNC.');
    end

    Tpool.sdq_regime = strings(height(Tpool),1);
    Tpool.as_regime  = strings(height(Tpool),1);
    Tpool.joint_cell = strings(height(Tpool),1);

    for i = 1:height(Tpool)
        sdq = Tpool.(metricSDQ)(i);
        asv = Tpool.(metricAS)(i);

        Tpool.sdq_regime(i) = assignRegimeLabel(sdq, q_sdq, cfg.joint_regime_labels);
        Tpool.as_regime(i)  = assignRegimeLabel(asv, q_as, cfg.joint_regime_labels);
        Tpool.joint_cell(i) = Tpool.sdq_regime(i) + "__" + Tpool.as_regime(i);
    end

    % Use structural C participant weights to weight representative selection.
    wSDQ = getSingleWeight(spec, 'sign_detection_quality', 'max');
    wAS  = getSingleWeight(spec, 'average_segment_speed', 'max');
    
    Tweights = table( ...
        ["sign_detection_quality"; "average_segment_speed"], ...
        [wSDQ; wAS], ...
        'VariableNames', {'SRPInputParticipant','WeightMaxNorm'});
    
    writetable(Tweights, fullfile(spec.outRoot, 'joint_observed_srp_input_weights.csv'));

    reps = selectJointCellRepresentatives(Tpool, q_sdq, q_as, cfg, metricSDQ, metricAS, wSDQ, wAS);

    occ = groupsummary(Tpool, {'sdq_regime','as_regime','joint_cell'});
    if ismember('GroupCount', occ.Properties.VariableNames)
        occ.Properties.VariableNames{'GroupCount'} = 'NumRows';
    else
        occ.Properties.VariableNames{end} = 'NumRows';
    end

    T_sdq = table(string(cfg.joint_regime_labels(:)), q_sdq(1:end-1)', q_sdq(2:end)', 'VariableNames', {'Regime','LowerBound','UpperBound'});
    T_as = table(string(cfg.joint_regime_labels(:)), q_as(1:end-1)', q_as(2:end)', 'VariableNames', {'Regime','LowerBound','UpperBound'});

    writetable(T_sdq, fullfile(spec.outRoot, 'sdq_regime_thresholds.csv'));
    writetable(T_as,  fullfile(spec.outRoot, 'as_regime_thresholds.csv'));
    writetable(Tpool, fullfile(spec.outRoot, 'joint_observed_candidate_pool.csv'));
    writetable(occ,   fullfile(spec.outRoot, 'joint_observed_cell_occupancy.csv'));
    writetable(reps,  fullfile(spec.outRoot, 'joint_observed_representatives.csv'));

    fprintf('Functional observed joint SRP regimes built in %s\n', spec.outRoot);
end


function mask = getUsableMetricMask(T, metric)
    validityCol = [metric '_validity'];
    if ismember(validityCol, T.Properties.VariableNames)
        mask = isUsableMetricValidity(string(T.(validityCol)));
    elseif ismember(metric, T.Properties.VariableNames)
        warning('Validity column %s not found. Falling back to non-NaN values of %s.', validityCol, metric);
        mask = ~isnan(T.(metric));
    else
        error('Neither metric column %s nor validity column %s exists in the table.', metric, validityCol);
    end
end

function reps = selectJointCellRepresentatives(Tpool, q_sdq, q_as, cfg, metricSDQ, metricAS, wSDQ, wAS)
    reps = Tpool([],:);
    if ~ismember('rep_rank', reps.Properties.VariableNames)
        reps.rep_rank = zeros(0,1);
    end

    % Normalize weights for the weighted distance metric
    wsum = max(wSDQ + wAS, eps);
    wSDQ = wSDQ / wsum;
    wAS  = wAS  / wsum;

    cells = unique(Tpool.joint_cell);
    cells = cells(strlength(cells) > 0);

    for i = 1:numel(cells)
        thisCell = cells(i);
        Tcell = Tpool(Tpool.joint_cell == thisCell, :);

        if height(Tcell) < cfg.min_rows_per_joint_cell
            continue;
        end

        sdqReg = string(Tcell.sdq_regime(1));
        asReg  = string(Tcell.as_regime(1));

        sdqMid = regimeMidpoint(sdqReg, q_sdq, cfg.joint_regime_labels);
        asMid  = regimeMidpoint(asReg, q_as, cfg.joint_regime_labels);

        sdqSpan = max(q_sdq(end) - q_sdq(1), eps);
        asSpan  = max(q_as(end) - q_as(1), eps);

        d = wSDQ * ((Tcell.(metricSDQ) - sdqMid) ./ sdqSpan).^2 + ...
            wAS  * ((Tcell.(metricAS)  - asMid)  ./ asSpan ).^2;

        [~, ord] = sort(d, 'ascend');
        nkeep = min(cfg.n_joint_representatives_per_cell, numel(ord));
        Tkeep = Tcell(ord(1:nkeep), :);
        Tkeep.rep_rank = (1:nkeep)';

        Tkeep = Tkeep(:, reps.Properties.VariableNames);
        reps = [reps; Tkeep]; %#ok<AGROW>
    end
end

function T = readAggregatedCampaignTable(campaignDir)
    f = fullfile(campaignDir, 'campaign_summary_design_aggregated.csv');
    if ~exist(f, 'file')
        error('Missing aggregated campaign table: %s', f);
    end
    T = readtable(f);
end
function vals = getUsableMetricValues(T, metric)
    vcol = [metric '_validity'];
    if ismember(vcol, T.Properties.VariableNames)
        usable = isUsableMetricValidity(string(T.(vcol)));
    else
        usable = ~isnan(T.(metric));
    end

    vals = T.(metric);
    vals = vals(usable);
    vals = vals(~isnan(vals));
end

function Tpool = poolObservedRows(TP, TS)
    TP = addSourceCampaignColumn(TP, "P_FUNC");
    TS = addSourceCampaignColumn(TS, "S_FUNC");

    allVars = union(TP.Properties.VariableNames, TS.Properties.VariableNames, 'stable');
    TP = addMissingTableVars(TP, allVars);
    TS = addMissingTableVars(TS, allVars);

    Tpool = [TP(:, allVars); TS(:, allVars)];
end


function T = addSourceCampaignColumn(T, label)
    T.source_campaign = repmat(string(label), height(T), 1);
end

function T = addMissingTableVars(T, allVars)
    existing = string(T.Properties.VariableNames);

    for i = 1:numel(allVars)
        v = string(allVars{i});
        if ~any(existing == v)
            T.(char(v)) = missingColumnDefault(v, height(T));
        end
    end
end

function x = missingColumnDefault(varName, n)
    varName = string(varName);
    if endsWith(varName, "_validity") || contains(lower(varName), "status") || contains(lower(varName), "campaign") || contains(lower(varName), "scenario")
        x = strings(n,1);
    else
        x = nan(n,1);
    end
end

function mid = regimeMidpoint(label, q, regimeLabels)
    idx = find(string(regimeLabels) == string(label), 1, 'first');
    if isempty(idx)
        mid = mean(q);
    else
        mid = 0.5 * (q(idx) + q(idx+1));
    end
end

