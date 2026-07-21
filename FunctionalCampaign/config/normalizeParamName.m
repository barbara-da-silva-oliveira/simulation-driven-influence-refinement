function x = normalizeParamName(x)
    x = lower(string(x));
    x = replace(x, '_', '');
    x = replace(x, 'nominal', '');
    x = replace(x, 'coef', '');
    x = replace(x, 'ambient', '');
    x = replace(x, 'lighting', 'luminosity');
    x = replace(x, 'blobsize', 'size');
    x = replace(x, 'wgain', 'w');
end
