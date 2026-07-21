function x = safeGetNumericField(row, fieldName, defaultValue)
    if isfield(row, fieldName)
        value = row.(fieldName);
        if isempty(value)
            x = defaultValue;
        else
            x = double(value);
        end
    else
        x = defaultValue;
    end
end
