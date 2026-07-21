function T = readSensitivityTableRobust(filePath)
    T = [];

    delimiters = {',', ';', '\t'};

    for i = 1:numel(delimiters)
        try
            opts = detectImportOptions(filePath, 'Delimiter', delimiters{i});
            Ttest = readtable(filePath, opts);

            if width(Ttest) > 1
                T = Ttest;
                return;
            end
        catch
        end
    end

    % fallback
    try
        T = readtable(filePath);
    catch ME
        error('Failed to read sensitivity table %s: %s', filePath, ME.message);
    end
end
