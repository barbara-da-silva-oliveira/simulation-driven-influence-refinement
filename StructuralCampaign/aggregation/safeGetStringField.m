function s = safeGetStringField(row, fieldName, defaultValue)
    if isfield(row, fieldName)
        value = row.(fieldName);
        if isstring(value)
            s = value;
        elseif ischar(value)
            s = string(value);
        else
            s = string(value);
        end
    else
        s = string(defaultValue);
    end
end
