function name = sanitizeFieldName(nameIn)
    name = matlab.lang.makeValidName(char(nameIn));
end
