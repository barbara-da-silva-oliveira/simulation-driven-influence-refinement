function checkVMConnectivity(cfg)
    disp('Opening SFTP connection to VM...');
    try
        sftpObj = sftp(cfg.vmIP, cfg.vmUser, 'Password', cfg.vmPassword);
        close(sftpObj);
    catch ME
        error('Could not connect to VM. Check credentials.\n%s', ME.message);
    end
end
