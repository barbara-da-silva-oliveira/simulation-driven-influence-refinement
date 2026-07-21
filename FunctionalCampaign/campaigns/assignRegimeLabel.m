function label = assignRegimeLabel(x, q, labels)
    label = string(labels{end});
    for k = 1:numel(labels)
        lo = q(k); hi = q(k+1);
        if k < numel(labels)
            if x >= lo && x < hi, label = string(labels{k}); return; end
        else
            if x >= lo && x <= hi, label = string(labels{k}); return; end
        end
    end
end
