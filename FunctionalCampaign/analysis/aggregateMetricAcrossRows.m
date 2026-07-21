function [aggVal, aggValidity] = aggregateMetricAcrossRows(rows, metric)
    validities = strings(numel(rows),1);
    vals = nan(numel(rows),1);
    for i = 1:numel(rows)
        validityField = [metric '_validity'];
        if isfield(rows(i), validityField)
            validities(i) = rows(i).(validityField);
        else
            validities(i) = "INVALID_TECHNICAL";
        end
        if isfield(rows(i), metric)
            vals(i) = rows(i).(metric);
        end
    end
    usableMask = isUsableMetricValidity(validities);
    if any(usableMask)
        usableVals = vals(usableMask);
        usableVals = usableVals(~isnan(usableVals));
        if isempty(usableVals)
            aggVal = NaN; aggValidity = "VALID_BEHAVIORAL_NAN"; return;
        end
        if strcmp(metric, 'completed')
            aggVal = mean(usableVals) >= 0.5; aggValidity = "VALID_BOOLEAN";
        else
            aggVal = mean(usableVals, 'omitnan');
            if all(validities(usableMask) == "VALID_ZERO") && abs(aggVal) < eps
                aggValidity = "VALID_ZERO";
            else
                aggValidity = "VALID";
            end
        end
        return;
    end
    aggVal = NaN;
    if any(validities == "VALID_BEHAVIORAL_NAN")
        aggValidity = "VALID_BEHAVIORAL_NAN";
    elseif any(validities == "INVALID_MISSING_REQUIRED_LOGS")
        aggValidity = "INVALID_MISSING_REQUIRED_LOGS";
    else
        aggValidity = "INVALID_TECHNICAL";
    end
end
