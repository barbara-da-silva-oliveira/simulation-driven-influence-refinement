function z = orderedLevelToUnitInterval(label, orderedLevels)
    orderedLevels = sortOrderedLevels(orderedLevels);
    idx = find(orderedLevels == string(label), 1, 'first');
    if isempty(idx)
        error('Level %s was not found in ordered level list.', string(label));
    end

    if numel(orderedLevels) <= 1
        z = 0.0;
    else
        z = (idx - 1) / (numel(orderedLevels) - 1);
    end
end