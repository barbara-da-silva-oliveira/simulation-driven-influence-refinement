function [srp, evalInfo] = computeSRPsFromLogs(logs, target_blob_size, params)
    srp = struct();
    evalInfo = makeBaseEvalInfo();
    stop_ts = getTS(logs, {'stopRobot'});
    v_ts    = getTS(logs, {'v'});
    w_ts    = getTS(logs, {'w'});
    bx_ts   = getTS(logs, {'blobX'});
    bs_ts   = getTS(logs, {'blobSize'});
    pose_ts = getTS(logs, {'pose'});
    evalInfo.required_log_stopRobot = ~isempty(stop_ts);
    evalInfo.required_log_v = ~isempty(v_ts);
    evalInfo.required_log_w = ~isempty(w_ts);
    evalInfo.required_log_blobX = ~isempty(bx_ts);
    evalInfo.required_log_blobSize = ~isempty(bs_ts);
    evalInfo.required_log_pose = ~isempty(pose_ts);
    missing = {};
    if isempty(v_ts)
        missing{end+1} = 'v';
    end
    if isempty(w_ts)
        missing{end+1} = 'w';
    end
    if isempty(bx_ts)
        missing{end+1} = 'blobX';
    end
    if isempty(bs_ts)
        missing{end+1} = 'blobSize'; 
    end
    if isempty(pose_ts)
        missing{end+1} = 'pose';
    end
    evalInfo.missing_required_logs = strjoin(missing, ';');
    evalInfo.missing_required_logs_count = numel(missing);
    evalInfo.run_validity = "VALID_RUN";
    srp.completed = false; 
    srp.completion_time = NaN; 
    srp.average_segment_speed = NaN; 
    srp.sign_detection_quality = NaN; 
    srp.tracking_error_rms = NaN; 
    srp.left_distance_to_sign = NaN; 
    srp.right_distance_to_sign = NaN; 
    srp.stop_distance_to_sign = NaN; 
    srp.time_turning = NaN;
    srp.time_to_next_blob20_first = NaN; 
    srp.time_to_next_blob20_count = NaN; 
    srp.safe_distance_ok = true;
    if ~isempty(stop_ts)
        stop_idx_robot = find(stop_ts.Data == 1, 1);
        if ~isempty(stop_idx_robot)
            srp.completed = true; 
            srp.completion_time = stop_ts.Time(stop_idx_robot); 
            evalInfo.metric_validity.completed = "VALID_BOOLEAN"; 
            evalInfo.metric_validity.completion_time = "VALID";
        else
            evalInfo.metric_validity.completed = "VALID_BOOLEAN"; 
            evalInfo.metric_validity.completion_time = "VALID_BEHAVIORAL_NAN";
        end
    else
        evalInfo.metric_validity.completed = "INVALID_MISSING_REQUIRED_LOGS";
        evalInfo.metric_validity.completion_time = "INVALID_MISSING_REQUIRED_LOGS";
    end
    if ~isempty(missing)
        evalInfo.run_validity = "INVALID_MISSING_REQUIRED_LOGS"; 
        evalInfo = markMetricFamilyAsMissing(evalInfo); 
        return;
    end
    bs = bs_ts.Data; 
    bx = bx_ts.Data; 
    pose = pose_ts.Data; 
    v = v_ts.Data; 
    w = w_ts.Data;
    if size(bs,1) == 1 && size(bs,2) > 1
        bs = bs'; 
    end
    if size(bx,1) == 1 && size(bx,2) > 1
        bx = bx'; 
    end
    if isvector(v)
        v = v(:); 
    end
    if isvector(w)
        w = w(:); 
    end
    if size(pose,1) == 1 && size(pose,2) > 1
        pose = pose'; 
    end
    n2 = min([size(bs,1), size(bx,1), size(pose,1), numel(v), numel(w)]);
    if n2 < 2
        evalInfo.run_validity = "INVALID_MISSING_REQUIRED_LOGS"; 
        evalInfo = markMetricFamilyAsMissing(evalInfo);
        return;
    end
    bs = bs(1:n2,:); 
    bx = bx(1:n2,:); 
    pose = pose(1:n2,:); 
    v = v(1:n2); 
    w = w(1:n2);
    t_pose = pose_ts.Time(1:n2);
    x = pose(:,1); 
    y = pose(:,2);
    dt = diff(t_pose); 
    dx = diff(x); dy = diff(y); 
    v_actual = [NaN; sqrt(dx.^2 + dy.^2) ./ dt];
    [bSize, idx] = max(bs, [], 2); 
    bLoc = bx(sub2ind(size(bx), (1:n2)', idx)); 
    detected = bSize >= 20;
    err = bLoc - params.image_center_x;
    if any(detected), srp.tracking_error_rms = rms(err(detected)); 
        evalInfo.metric_validity.tracking_error_rms = "VALID"; 
    else
        evalInfo.metric_validity.tracking_error_rms = "VALID_BEHAVIORAL_NAN"; 
    end
    tracking_indices_actual = detected & (v_actual > 0.01);
    if any(tracking_indices_actual)
        srp.average_segment_speed = mean(v_actual(tracking_indices_actual), 'omitnan'); 
        evalInfo.metric_validity.average_segment_speed = "VALID"; 
    else, srp.average_segment_speed = 0; evalInfo.metric_validity.average_segment_speed = "VALID_ZERO"; 
    end
    centered = abs(bLoc - params.image_center_x) <= params.center_tolerance; 
    at_target_size = abs(bSize - target_blob_size) <= params.blob_size_tolerance; 
    paused = abs(v) <= params.pause_tolerance & abs(w) <= params.pause_tolerance;
    usable_detect = detected;
    verified = usable_detect & paused; 
    is_stop = idx == params.stop_sign_idx; 
    is_right = idx == params.right_sign_idx; 
    is_left = ~(is_stop | is_right);
    k_left_all = find(diff([0; verified & is_left]) == 1); 
    k_right_all = find(diff([0; verified & is_right]) == 1); 
    k_stop_all = find(diff([0; verified & is_stop]) == 1);
    if ~isempty(k_left_all), d = zeros(1,numel(k_left_all)); 
        for i=1:numel(k_left_all)
            d(i)=nearestDistance([pose(k_left_all(i),1) pose(k_left_all(i),2)], params.left_sign_positions); 
        end
        srp.left_distance_to_sign = mean(d); 
        evalInfo.metric_validity.left_distance_to_sign = "VALID";
    else
        evalInfo.metric_validity.left_distance_to_sign = "VALID_BEHAVIORAL_NAN"; 
    end
    if ~isempty(k_right_all), d = zeros(1,numel(k_right_all)); 
        for i=1:numel(k_right_all)
            d(i)=nearestDistance([pose(k_right_all(i),1) pose(k_right_all(i),2)], params.right_sign_positions); 
        end
        srp.right_distance_to_sign = mean(d); 
        evalInfo.metric_validity.right_distance_to_sign = "VALID"; 
    else
        evalInfo.metric_validity.right_distance_to_sign = "VALID_BEHAVIORAL_NAN";
    end
    if ~isempty(k_stop_all), d = zeros(1,numel(k_stop_all)); 
        for i=1:numel(k_stop_all)
            d(i) =nearestDistance([pose(k_stop_all(i),1) pose(k_stop_all(i),2)], params.stop_sign_positions); 
        end
    srp.stop_distance_to_sign = mean(d);
    evalInfo.metric_validity.stop_distance_to_sign = "VALID"; 
    else
        evalInfo.metric_validity.stop_distance_to_sign = "VALID_BEHAVIORAL_NAN"; 
    end
    all_stop_events = sort([k_left_all; k_right_all; k_stop_all]);
    if isempty(all_stop_events)
        srp.sign_detection_quality = 0; 
        evalInfo.metric_validity.sign_detection_quality = "VALID_ZERO";
    else
        segment_qualities = []; start_search_idx = 1;
        for i = 1:numel(all_stop_events)
            end_idx = all_stop_events(i);
            if start_search_idx > end_idx, continue; end
            detect_indices = find(detected(start_search_idx:end_idx));
            if ~isempty(detect_indices)
                start_idx = start_search_idx + detect_indices(1) - 1;
                frames_in_segment = end_idx - start_idx + 1;
                successful_frames = sum(usable_detect(start_idx:end_idx));
                segment_qualities(end+1) = successful_frames / frames_in_segment; %#ok<AGROW>
            end
            start_search_idx = end_idx + 1;
        end
        if ~isempty(segment_qualities)
            srp.sign_detection_quality = mean(segment_qualities); 
            if srp.sign_detection_quality <= eps
                evalInfo.metric_validity.sign_detection_quality = "VALID_ZERO"; 
            else
                evalInfo.metric_validity.sign_detection_quality = "VALID";
            end
        else
            srp.sign_detection_quality = 0; 
            evalInfo.metric_validity.sign_detection_quality = "VALID_ZERO"; 
        end
    end
    t_ref = bs_ts.Time(1:n2); reacq_times = [];
    if ~isempty(all_stop_events)
        for i = 1:numel(all_stop_events)
            k_stop_evt = all_stop_events(i); 
            t_stop_evt = t_ref(k_stop_evt); 
            k_after = (k_stop_evt+1):n2; 
            if isempty(k_after)
                continue; 
            end
            k_reset_rel = find(bs(k_after) < 5, 1, 'first'); 
            if isempty(k_reset_rel)
                continue; 
            end
            k_reset = k_after(k_reset_rel); 
            k_after_reset = (k_reset+1):n2; 
            if isempty(k_after_reset), continue; 
            end
            k_new_rel = find(bs(k_after_reset) >= 20, 1, 'first'); 
            if isempty(k_new_rel), continue; 
            end
            k_new = k_after_reset(k_new_rel); 
            t_new = t_ref(k_new); 
            reacq_times(end+1) = t_new - t_stop_evt; %#ok<AGROW>
        end
    end
    if ~isempty(reacq_times)
        srp.time_turning = mean(reacq_times, 'omitnan'); 
        srp.time_to_next_blob20_first = reacq_times(1); 
        srp.time_to_next_blob20_count = numel(reacq_times); 
        evalInfo.metric_validity.time_turning = "VALID"; 
        evalInfo.metric_validity.time_to_next_blob20_first = "VALID"; 
        evalInfo.metric_validity.time_to_next_blob20_count = "VALID";
    else
        evalInfo.metric_validity.time_turning = "VALID_BEHAVIORAL_NAN"; 
        evalInfo.metric_validity.time_to_next_blob20_first = "VALID_BEHAVIORAL_NAN"; 
        evalInfo.metric_validity.time_to_next_blob20_count = "VALID_BEHAVIORAL_NAN";
    end
end

function ts = getTS(logs, nameList)
    ts = [];
    existing = string(logs.getElementNames);
    for i = 1:numel(nameList)
        nm = string(nameList{i});
        if any(existing == nm)
            el = logs.getElement(char(nm));
            ts = el.Values;
            return;
        end
    end
end

function out = joinMissing(existing, newItem)
    if strlength(string(existing)) == 0
        out = string(newItem);
    else
        out = string(existing) + ";" + string(newItem);
    end
end

function dmin = nearestDistance(robot_xy, sign_positions)
    if isempty(sign_positions) || any(isnan(robot_xy))
        dmin = NaN;
        return;
    end
    d = sqrt(sum((sign_positions - robot_xy).^2, 2));
    dmin = min(d);
end

function evalInfo = makeTechnicalFailureEvalInfo(errMsg)
    evalInfo = makeBaseEvalInfo();
    evalInfo.run_validity = "INVALID_TECHNICAL";
    evalInfo.missing_required_logs = "technical_failure";
    evalInfo.missing_required_logs_count = 0;
    evalInfo.technical_error_message = string(errMsg);
end

function evalInfo = makeBaseEvalInfo()
    evalInfo = struct();
    evalInfo.run_validity = "VALID_RUN";
    evalInfo.missing_required_logs = "";
    evalInfo.missing_required_logs_count = 0;
    evalInfo.required_log_stopRobot = false;
    evalInfo.required_log_v = false;
    evalInfo.required_log_w = false;
    evalInfo.required_log_blobX = false;
    evalInfo.required_log_blobSize = false;
    evalInfo.required_log_pose = false;
    evalInfo.metric_validity = struct( ...
        'completed', "INVALID_TECHNICAL", ...
        'completion_time', "INVALID_TECHNICAL", ...
        'average_segment_speed', "INVALID_TECHNICAL", ...
        'sign_detection_quality', "INVALID_TECHNICAL", ...
        'tracking_error_rms', "INVALID_TECHNICAL", ...
        'left_distance_to_sign', "INVALID_TECHNICAL", ...
        'right_distance_to_sign', "INVALID_TECHNICAL", ...
        'stop_distance_to_sign', "INVALID_TECHNICAL", ...
        'time_turning', "INVALID_TECHNICAL", ...
        'time_to_next_blob20_first', "INVALID_TECHNICAL", ...
        'time_to_next_blob20_count', "INVALID_TECHNICAL");
end


function evalInfo = markMetricFamilyAsMissing(evalInfo)
    metricNames = fieldnames(evalInfo.metric_validity);
    for i = 1:numel(metricNames)
        evalInfo.metric_validity.(metricNames{i}) = "INVALID_MISSING_REQUIRED_LOGS";
    end
end
