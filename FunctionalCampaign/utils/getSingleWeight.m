function value = getSingleWeight(spec, participantName, normalizationMode)
    switch lower(string(normalizationMode))
        case "max"
            vals = spec.weights_maxnorm;
        case "sum"
            vals = spec.weights_sumnorm;
        otherwise
            error('Unknown normalization mode: %s', normalizationMode);
    end

    value = getWeightsForNames({participantName}, spec.weight_names, vals);
    value = value(1);
end
