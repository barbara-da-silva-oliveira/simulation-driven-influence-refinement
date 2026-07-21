function val = getTableValueOrDefault(T, rowIdx, varName, defaultVal)
    if any(strcmp(T.Properties.VariableNames, varName))
        x = T.(varName)(rowIdx);
        if isempty(x) || (isnumeric(x) && any(isnan(x)))
            val = defaultVal;
        else
            val = x;
        end
    else
        val = defaultVal;
    end
end
