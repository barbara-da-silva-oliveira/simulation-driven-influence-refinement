function tf = isUsableMetricValidity(validityArray)
    tf = (validityArray == "VALID") | (validityArray == "VALID_ZERO") | (validityArray == "VALID_BOOLEAN");
end