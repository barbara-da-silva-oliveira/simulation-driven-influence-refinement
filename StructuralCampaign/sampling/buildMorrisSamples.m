function samples_exec = buildMorrisSamples(param_names, bounds_matrix, N_trajectories, num_levels)
    py_bounds = py.list();
    for p = 1:size(bounds_matrix, 1)
        py_bounds.append(py.list(num2cell(bounds_matrix(p,:))));
    end
    names_py = py.list(param_names);
    py_problem = py.dict(pyargs('num_vars', int32(numel(param_names)), 'names', names_py, 'bounds', py_bounds));
    py_samples = py.SALib.sample.morris.sample(py_problem, N_trajectories, pyargs('num_levels', num_levels));
    samples_exec = double(py_samples);
    for p = 1:numel(param_names)
        if strcmp(param_names{p}, 'size')
            samples_exec(:, p) = round(samples_exec(:, p));
        end
    end
end
