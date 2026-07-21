function killRemoteGazebo(vmIP, vmUser, vmPassword, simPID)
    if isempty(simPID) || strlength(string(simPID)) == 0
        return;
    end

    killCmd = sprintf('kill -INT %s', string(simPID));
    sshKillCmd = sprintf( ...
        'sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s "%s"', ...
        vmPassword, vmUser, vmIP, killCmd);

    system(sshKillCmd);
end
