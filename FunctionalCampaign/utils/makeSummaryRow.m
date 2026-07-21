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
