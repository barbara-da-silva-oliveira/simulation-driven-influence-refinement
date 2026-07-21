function checkVMConnectivity(cfg)
sftpObj = sftp(cfg.vmIP, cfg.vmUser, 'Password', cfg.vmPassword);
close(sftpObj);
end
