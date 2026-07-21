function resetGazeboWorld(vmIP, vmUser, vmPassword)
    resetCmd = 'source /opt/ros/noetic/setup.bash; rosservice call /gazebo/reset_world "{}"';
    sshResetCmd = sprintf( ...
        'sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s "%s"', ...
        vmPassword, vmUser, vmIP, resetCmd);

    [statusReset, outReset] = system(sshResetCmd);

    if statusReset ~= 0
        error('Failed to reset Gazebo world: %s', strtrim(outReset));
    end
end
