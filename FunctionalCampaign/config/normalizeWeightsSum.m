function w = normalizeWeightsSum(mu)
    mu = double(mu(:))'; mu(mu < 0) = 0;
    if isempty(mu) || all(mu == 0)
        w = ones(size(mu)) ./ max(1, numel(mu));
    else
        w = mu ./ sum(mu);
    end
end
