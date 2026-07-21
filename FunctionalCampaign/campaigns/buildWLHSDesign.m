function [samples_exec, param_names, w_norm, shape_params] = buildWLHSDesign(spec, cfg, N)
    param_names = spec.active_inputs;

    % Only retrieve the weights corresponding to directly sampled inputs
    % For C_FUNC, this means only w is used in WLHS, the others are SRP
    w_norm = getWeightsForNames(spec.active_inputs, spec.weight_names, spec.weights_maxnorm);

    shape_params = 1 + cfg.wlhs_shape_gain .* w_norm;

    lhs_raw = lhsdesign(N, numel(param_names), ...
        'criterion', 'maximin', ...
        'iterations', 50);

    samples_exec = zeros(N, numel(param_names));

    for i = 1:numel(param_names)
        p = param_names{i};
        val_bounds = spec.bounds.(p);
        lo = val_bounds(1);
        hi = val_bounds(2);

        shape = shape_params(i);

        if abs(shape - 1.0) < 1e-12
            u = lhs_raw(:, i);
        else
            u = betainv(lhs_raw(:, i), shape, shape);
        end

        vals = lo + u .* (hi - lo);

        if strcmp(p, 'size')
            vals = round(vals);
        end

        samples_exec(:, i) = vals;
    end
end
