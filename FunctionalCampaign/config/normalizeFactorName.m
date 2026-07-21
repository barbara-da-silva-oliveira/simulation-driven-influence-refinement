function x = normalizeFactorName(x)
    x = lower(string(x));
    x = replace(x, '_', '');
    x = replace(x, ' ', '');
    x = replace(x, "-", "");

    switch x
        case {"signdetectionquality","sdq","sdqregime"}
            x = "sdqregime";
        case {"averagesegmentspeed","as","asregime"}
            x = "asregime";
        case {"w","wgain"}
            x = "wgain";
    end
end
