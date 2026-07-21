function cleanupVM(vmIP, vmUser, vmPassword)
    killCmd = 'killall -9 gzserver gzclient roslaunch rosmaster; rm -rf ~/.ros/log/*; sleep 2';
    sshKillCmd = sprintf( ...
        'sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s "%s"', ...
        vmPassword, vmUser, vmIP, killCmd);

    system(sshKillCmd);
    pause(3);
end
