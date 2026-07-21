function evalInfo = makeTechnicalFailureEvalInfo(errMsg)
    evalInfo = makeBaseEvalInfo();
    evalInfo.run_validity = "INVALID_TECHNICAL";
    evalInfo.missing_required_logs = "technical_failure";
    evalInfo.missing_required_logs_count = 0;
    evalInfo.technical_error_message = string(errMsg);
end
