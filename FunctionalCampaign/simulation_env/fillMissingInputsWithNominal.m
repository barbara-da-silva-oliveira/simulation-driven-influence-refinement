function in = fillMissingInputsWithNominal(in, cfg)
    if ~isfield(in, 'v'), in.v = cfg.nominal.v; end
    if ~isfield(in, 'w'), in.w = cfg.nominal.w; end
    if ~isfield(in, 'size'), in.size = cfg.nominal.size; end
    if ~isfield(in, 'friction'), in.friction = cfg.nominal.friction; end
    if ~isfield(in, 'luminosity'), in.luminosity = cfg.nominal.luminosity; end
    if ~isfield(in, 'transparency'), in.transparency = cfg.nominal.transparency; end
end
