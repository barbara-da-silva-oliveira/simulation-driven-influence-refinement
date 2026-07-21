function field = normalizeSummaryFieldName(name)
switch lower(name)
    case 'v', field = 'v_nominal';
    case 'w', field = 'w_gain';
    case 'size', field = 'target_blob_size';
    case 'friction', field = 'friction_surface';
    case 'luminosity', field = 'luminosity_level';
    case 'transparency', field = 'wall_transparency';
    otherwise, field = matlab.lang.makeValidName(name);
end
end
