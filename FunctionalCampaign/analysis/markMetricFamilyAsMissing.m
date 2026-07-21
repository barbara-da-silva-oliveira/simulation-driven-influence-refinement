function evalInfo = markMetricFamilyAsMissing(evalInfo)
    metricNames = fieldnames(evalInfo.metric_validity);
    for i = 1:numel(metricNames)
        evalInfo.metric_validity.(metricNames{i}) = "INVALID_MISSING_REQUIRED_LOGS";
    end
end