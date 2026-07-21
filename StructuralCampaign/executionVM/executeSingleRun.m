function [summaryRow, campaignResult, simPID] = executeSingleRun(cfg, campaign_id, runDef, target_metric, simPID, outRoot)
    runDir = fullfile(outRoot, sprintf('design_%03d_rep%d', runDef.design_id, runDef.rep));
    if ~exist(runDir, 'dir')
        mkdir(runDir);
    end

    inVals = runDef.inputs;
    v_val = inVals.v;
    w_val = inVals.w;
    size_val = round(inVals.size);
    fric_val = inVals.friction;
    lum_val = inVals.luminosity;
    transp_val = inVals.transparency;

    fprintf('\n============================================================\n');
    fprintf('Run %d | design %d | rep %d\n', runDef.run_id, runDef.design_id, runDef.rep);
    fprintf('Params: v=%.4f, w=%.4f, size=%d, friction=%.4f, lum=%.4f, transp=%.4f\n', ...
        v_val, w_val, size_val, fric_val, lum_val, transp_val);

    success = false;
    lastError = "";
    logs_file_final = "";
    json_file_final = "";
    finalMeta = struct();
    finalSrp  = struct();
    finalEvalInfo = struct();
    attempts_used = 0;

    for attempt = 1:(cfg.maxRetriesPerRep + 1)
        attempts_used = attempt;
        fprintf('  Attempt %d/%d for this replicate\n', attempt, cfg.maxRetriesPerRep + 1);
        seed_val = runDef.design_id * 1000 + runDef.rep;
        rng(seed_val, 'twister');

        meta = buildRunMeta(campaign_id, runDef.scenario_id, runDef.run_id, runDef.design_id, runDef.rep, attempt, seed_val, ...
            v_val, w_val, size_val, fric_val, lum_val, transp_val);

        try
            if strlength(string(simPID)) > 0
                fprintf('  Shutting down previous Gazebo (PID: %s)...\n', string(simPID));
                killRemoteGazebo(cfg.vmIP, cfg.vmUser, cfg.vmPassword, simPID);
                simPID = "";
                pause(4);
            end

            fprintf('  Updating remote world file...\n');
            updateVMWorldFile(cfg.vmIP, cfg.vmUser, cfg.vmPassword, cfg.remoteDir, cfg.remoteFile, fric_val, lum_val, transp_val);

            fprintf('  Starting Gazebo in background...\n');
            simPID = startRemoteGazebo(cfg.vmIP, cfg.vmUser, cfg.vmPassword);
            fprintf('  Gazebo launched! Process ID: %s\n', string(simPID));

            fprintf('  Waiting 15 seconds for ROS/Gazebo network to initialize...\n');
            pause(15);

            fprintf('  Resetting Gazebo world...\n');
            resetGazeboWorld(cfg.vmIP, cfg.vmUser, cfg.vmPassword);

            try
                rosshutdown;
            catch
            end

            in = Simulink.SimulationInput(cfg.modelName);
            in = in.setVariable('v_nominal', v_val);
            in = in.setVariable('w_gain', w_val);
            in = in.setVariable('target_blob_size', size_val);
            in = in.setModelParameter('StopTime', num2str(cfg.simStopTime));

            fprintf('  Running Simulink co-simulation...\n');
            simOut = sim(in);
            logs = simOut.logsout;
            [srp, evalInfo] = computeSRPsFromLogs(logs, size_val, cfg.evalParams);

            logs_file = fullfile(runDir, sprintf('logsout_attempt%02d.mat', attempt));
            json_file = fullfile(runDir, sprintf('summary_attempt%02d.json', attempt));
            save(logs_file, 'logs', 'simOut', 'meta', 'evalInfo');
            writelines(jsonencode(struct('meta', meta, 'srp', srp, 'eval_info', evalInfo)), json_file);

            fprintf('  Outcome: target %s = %.6f [%s]\n', target_metric, safeGetNumericField(srp, target_metric, NaN), safeGetStringField(evalInfo.metric_validity, target_metric, "INVALID_TECHNICAL"));

            success = true;
            logs_file_final = logs_file;
            json_file_final = json_file;
            finalMeta = meta;
            finalSrp = srp;
            finalEvalInfo = evalInfo;
            break;

        catch ME
            lastError = string(ME.message);
            errFile = fullfile(runDir, sprintf('error_attempt%02d.txt', attempt));
            writelines("ERROR: " + string(getReport(ME, 'extended', 'hyperlinks', 'off')), errFile);
            fprintf('  Attempt failed: %s\n', string(ME.message));
            if attempt <= cfg.maxRetriesPerRep
                fprintf('  Retrying same configuration for the same replicate...\n');
            else
                fprintf('  No retries left for this replicate.\n');
            end
        end
    end

    if success
        campaignResult.meta = finalMeta;
        campaignResult.srp = finalSrp;
        campaignResult.eval_info = finalEvalInfo;
        campaignResult.status = "OK";
        campaignResult.error = "";
        campaignResult.attempts_used = attempts_used;
        summaryRow = makeSummaryRow(finalMeta, finalSrp, finalEvalInfo, runDir, logs_file_final, json_file_final, "OK", "");
    else
        failMeta = buildRunMeta(campaign_id, runDef.scenario_id, runDef.run_id, runDef.design_id, runDef.rep, attempts_used, seed_val, ...
            v_val, w_val, size_val, fric_val, lum_val, transp_val);
        failEvalInfo = makeTechnicalFailureEvalInfo(lastError);
        campaignResult.meta = failMeta;
        campaignResult.srp = struct();
        campaignResult.eval_info = failEvalInfo;
        campaignResult.status = "CRASH";
        campaignResult.error = lastError;
        campaignResult.attempts_used = attempts_used;
        summaryRow = makeSummaryRow(failMeta, struct(), failEvalInfo, runDir, "", "", "CRASH", lastError);
    end
end

function evalInfo = makeTechnicalFailureEvalInfo(errMsg)
    evalInfo = makeBaseEvalInfo();
    evalInfo.run_validity = "INVALID_TECHNICAL";
    evalInfo.missing_required_logs = "technical_failure";
    evalInfo.missing_required_logs_count = 0;
    evalInfo.technical_error_message = string(errMsg);
end





function meta = buildRunMeta(campaign_id, scenario_id, run_id, design_id, rep, attempt, seed_val, v_val, w_val, size_val, fric_val, lum_val, transp_val)
    meta = struct();
    meta.campaign_id = campaign_id;
    meta.scenario_id = scenario_id;
    meta.run_id = run_id;
    meta.design_id = design_id;
    meta.rep = rep;
    meta.attempt = attempt;
    meta.seed = seed_val;
    meta.timestamp = char(datetime('now'));
    meta.parameters = struct('v_nominal', v_val, 'w_gain', w_val, 'target_blob_size', size_val);
    meta.environment = struct('friction_surface', fric_val, 'luminosity_level', lum_val, 'wall_transparency', transp_val);
end

function pid = startRemoteGazebo(vmIP, vmUser, vmPassword)
    startCmd = ['export DISPLAY=:0; nohup /bin/bash -c "source /opt/ros/noetic/setup.bash; ' ...
                'source ~/catkin_ws/devel/setup.bash; ' ...
                'exec roslaunch mw_vision_example mw_vision_example_newstopsign_cosim.launch gui:=false paused:=false" ' ...
                '> /dev/null 2>&1 & echo $!'];
    sshStartCmd = sprintf('sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s ''%s''', vmPassword, vmUser, vmIP, startCmd);
    [statusStart, cmdoutStart] = system(sshStartCmd);
    if statusStart ~= 0
        error('Failed to start Gazebo: %s', strtrim(cmdoutStart));
    end
    pid = strtrim(cmdoutStart);
 end
% function pid = startRemoteGazebo(vmIP, vmUser, vmPassword)
%     logFile = '/tmp/signfollow_roslaunch.log';
% 
%     startCmd = sprintf([ ...
%         'rm -f %s; ' ...
%         'export DISPLAY=:0; ' ...
%         'export ROS_MASTER_URI=http://%s:11311; ' ...
%         'export ROS_IP=%s; ' ...
%         'unset ROS_HOSTNAME; ' ...
%         'export GAZEBO_PLUGIN_PATH=/home/user/src/GazeboPlugin/export/lib:$GAZEBO_PLUGIN_PATH; ' ...
%         'export LD_LIBRARY_PATH=/home/user/src/GazeboPlugin/export/lib:$LD_LIBRARY_PATH; ' ...
%         'source /opt/ros/noetic/setup.bash; ' ...
%         'source ~/catkin_ws/devel/setup.bash; ' ...
%         'nohup roslaunch mw_vision_example mw_vision_example_newstopsign_cosim.launch gui:=false paused:=false ' ...
%         '> %s 2>&1 & echo $!'], ...
%         logFile, vmIP, vmIP, logFile);
% 
%     sshStartCmd = sprintf( ...
%         'sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s ''%s''', ...
%         vmPassword, vmUser, vmIP, startCmd);
% 
%     [statusStart, cmdoutStart] = system(sshStartCmd);
% 
%     if statusStart ~= 0
%         error('Failed to start Gazebo: %s', strtrim(cmdoutStart));
%     end
% 
%     pid = strtrim(cmdoutStart);
% 
%     if isempty(pid) || isnan(str2double(pid))
%         error('Gazebo launch did not return a valid PID. Output was: %s', cmdoutStart);
%     end
% 
%     fprintf('  Gazebo launched! Process ID: %s\n', pid);
%     fprintf('  Launch log on VM: %s\n', logFile);
% end
% 

function killRemoteGazebo(vmIP, vmUser, vmPassword, simPID)
    if isempty(simPID) || strlength(string(simPID)) == 0
        return;
    end
    killCmd = sprintf('kill -INT %s', string(simPID));
    sshKillCmd = sprintf('sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s "%s"', vmPassword, vmUser, vmIP, killCmd);
    system(sshKillCmd);
end

function resetGazeboWorld(vmIP, vmUser, vmPassword)
    resetCmd = 'source /opt/ros/noetic/setup.bash; rosservice call /gazebo/reset_world "{}"';
    sshResetCmd = sprintf('sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s "%s"', vmPassword, vmUser, vmIP, resetCmd);
    [statusReset, outReset] = system(sshResetCmd);
    if statusReset ~= 0
        error('Failed to reset Gazebo world: %s', strtrim(outReset));
    end
end


function updateVMWorldFile(vmIP, vmUser, vmPassword, remoteDir, remoteFile, newMu, newLum, newTransp)
    sftpObj = sftp(vmIP, vmUser, 'Password', vmPassword);
    try
        cd(sftpObj, remoteDir);
        mget(sftpObj, remoteFile);
        fileText = fileread(remoteFile);
        patternFric = '(<friction>\s*<ode>\s*<mu>)[\d\.]+(</mu>\s*<mu2>)[\d\.]+(</mu2>)';
        replacementFric = sprintf('$1%.6f$2%.6f$3', newMu, newMu);
        fileText = regexprep(fileText, patternFric, replacementFric);
        patternAmbient = '(<ambient>\s*)[\d\.]+\s+[\d\.]+\s+[\d\.]+(\s+[\d\.]+\s*</ambient>)';
        replacementAmbient = sprintf('$1%.6f %.6f %.6f$2', newLum, newLum, newLum);
        fileText = regexprep(fileText, patternAmbient, replacementAmbient);
        patternTransparency = '(<transparency>\s*)[\d\.]+(\s*</transparency>)';
        replacementTransparency = sprintf('$1%.6f$2', newTransp);
        fileText = regexprep(fileText, patternTransparency, replacementTransparency);
        fid = fopen(remoteFile, 'w');
        if fid == -1, error('Cannot open local world file for writing.'); end
        fprintf(fid, '%s', fileText);
        fclose(fid);
        mput(sftpObj, remoteFile);
        delete(remoteFile);
    catch ME
        try
            if exist(remoteFile, 'file'), delete(remoteFile); end
        catch
        end
        close(sftpObj);
        rethrow(ME);
    end
    close(sftpObj);
end

function row = makeEmptySummaryRow()
    row = struct();
    row.campaign_id = "";
    row.scenario_id = "";
    row.run_id = NaN;
    row.design_id = NaN;
    row.replicate_id = NaN;
    row.attempt_used = NaN;
    row.seed = NaN;
    row.timestamp = "";
    row.status = "";
    row.error_message = "";
    row.run_validity = "";
    row.missing_required_logs = "";
    row.missing_required_logs_count = NaN;
    row.friction_surface = NaN;
    row.luminosity_level = NaN;
    row.wall_transparency = NaN;
    row.v_nominal = NaN;
    row.w_gain = NaN;
    row.target_blob_size = NaN;
    row.completed = NaN;
    row.completed_validity = "";
    row.completion_time = NaN;
    row.completion_time_validity = "";
    row.average_segment_speed = NaN;
    row.average_segment_speed_validity = "";
    row.sign_detection_quality = NaN;
    row.sign_detection_quality_validity = "";
    row.tracking_error_rms = NaN;
    row.tracking_error_rms_validity = "";
    row.left_distance_to_sign = NaN;
    row.left_distance_to_sign_validity = "";
    row.right_distance_to_sign = NaN;
    row.right_distance_to_sign_validity = "";
    row.stop_distance_to_sign = NaN;
    row.stop_distance_to_sign_validity = "";
    row.time_turning = NaN;
    row.time_turning_validity = "";
    row.time_to_next_blob20_first = NaN;
    row.time_to_next_blob20_first_validity = "";
    row.time_to_next_blob20_count = NaN;
    row.time_to_next_blob20_count_validity = "";
    row.run_dir = "";
    row.logsout_file = "";
    row.summary_json = "";
end

function row = makeSummaryRow(meta, srp, evalInfo, runDir, logs_file, json_file, status, errMsg)
    row = makeEmptySummaryRow();
    row.campaign_id = string(meta.campaign_id); row.scenario_id = string(meta.scenario_id); row.run_id = meta.run_id; row.design_id = meta.design_id; row.replicate_id = meta.rep; row.attempt_used = meta.attempt; row.seed = meta.seed; row.timestamp = string(meta.timestamp); row.status = string(status); row.error_message = string(errMsg); row.run_validity = string(evalInfo.run_validity); row.missing_required_logs = string(evalInfo.missing_required_logs); row.missing_required_logs_count = evalInfo.missing_required_logs_count;
    if isfield(meta, 'environment')
        if isfield(meta.environment, 'friction_surface'), row.friction_surface = meta.environment.friction_surface; end
        if isfield(meta.environment, 'luminosity_level'), row.luminosity_level = meta.environment.luminosity_level; end
        if isfield(meta.environment, 'wall_transparency'), row.wall_transparency = meta.environment.wall_transparency; end
    end
    if isfield(meta, 'parameters')
        if isfield(meta.parameters, 'v_nominal'), row.v_nominal = meta.parameters.v_nominal; end
        if isfield(meta.parameters, 'w_gain'), row.w_gain = meta.parameters.w_gain; end
        if isfield(meta.parameters, 'target_blob_size'), row.target_blob_size = meta.parameters.target_blob_size; end
    end
    row.completed_validity = string(evalInfo.metric_validity.completed); row.completion_time_validity = string(evalInfo.metric_validity.completion_time); row.average_segment_speed_validity = string(evalInfo.metric_validity.average_segment_speed); row.sign_detection_quality_validity = string(evalInfo.metric_validity.sign_detection_quality); row.tracking_error_rms_validity = string(evalInfo.metric_validity.tracking_error_rms); row.left_distance_to_sign_validity = string(evalInfo.metric_validity.left_distance_to_sign); row.right_distance_to_sign_validity = string(evalInfo.metric_validity.right_distance_to_sign); row.stop_distance_to_sign_validity = string(evalInfo.metric_validity.stop_distance_to_sign); row.time_turning_validity = string(evalInfo.metric_validity.time_turning); row.time_to_next_blob20_first_validity = string(evalInfo.metric_validity.time_to_next_blob20_first); row.time_to_next_blob20_count_validity = string(evalInfo.metric_validity.time_to_next_blob20_count);
    if ~isempty(srp)
        if isfield(srp,'completed'), row.completed = srp.completed; end
        if isfield(srp,'completion_time'), row.completion_time = srp.completion_time; end
        if isfield(srp,'average_segment_speed'), row.average_segment_speed = srp.average_segment_speed; end
        if isfield(srp,'sign_detection_quality'), row.sign_detection_quality = srp.sign_detection_quality; end
        if isfield(srp,'tracking_error_rms'), row.tracking_error_rms = srp.tracking_error_rms; end
        if isfield(srp,'left_distance_to_sign'), row.left_distance_to_sign = srp.left_distance_to_sign; end
        if isfield(srp,'right_distance_to_sign'), row.right_distance_to_sign = srp.right_distance_to_sign; end
        if isfield(srp,'stop_distance_to_sign'), row.stop_distance_to_sign = srp.stop_distance_to_sign; end
        if isfield(srp,'time_turning'), row.time_turning = srp.time_turning; end
        if isfield(srp,'time_to_next_blob20_first'), row.time_to_next_blob20_first = srp.time_to_next_blob20_first; end
        if isfield(srp,'time_to_next_blob20_count'), row.time_to_next_blob20_count = srp.time_to_next_blob20_count; end
    end
    row.run_dir = string(runDir); row.logsout_file = string(logs_file); row.summary_json = string(json_file);
end

