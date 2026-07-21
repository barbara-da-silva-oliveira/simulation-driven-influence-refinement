function ordered = sortOrderedLevels(levels)
    levels = unique(string(levels));
    levels = levels(strlength(levels) > 0);
    if isempty(levels)
        ordered = levels;
        return;
    end

    score = zeros(numel(levels), 1);
    for i = 1:numel(levels)
        li = lower(strtrim(levels(i)));
        if contains(li, "very") && contains(li, "low")
            score(i) = 1;
        elseif contains(li, "low")
            score(i) = 2;
        elseif contains(li, "medium") || contains(li, "moderate")
            score(i) = 3;
        elseif contains(li, "high") && contains(li, "very")
            score(i) = 5;
        elseif contains(li, "high")
            score(i) = 4;
        else
            score(i) = 100 + i;
        end
    end

    [~, idx] = sort(score);
    ordered = levels(idx);
end