function w = normalizeWeightsMax(mu)
    mu = double(mu(:))'; mu(mu < 0) = 0;
    if isempty(mu) || all(mu == 0)
        w = ones(size(mu));
    else
        w = mu ./ max(mu);
    end
end

