function s = sanitizeLabel(x)
    s = char(string(x));
    s = strrep(s, '__', '_');
    s = strrep(s, ' ', '_');
end
