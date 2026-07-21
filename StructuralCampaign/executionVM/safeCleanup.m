function safeCleanup(cfg, simPID)
    fprintf('\nCleaning up VM environment...\n');
    try
        if strlength(string(simPID)) > 0
            killRemoteGazebo(cfg.vmIP, cfg.vmUser, cfg.vmPassword, simPID);
        end
    catch
    end
    cleanupVM(cfg.vmIP, cfg.vmUser, cfg.vmPassword);
end

