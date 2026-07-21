function run_structural_campaign(mode)
    cfg = defaultConfigStructural();

    mode = upper(string(mode));
    disp('All cfg fields:');
    disp(fieldnames(cfg));
    switch mode
        case "P"
            runUpstreamMorrisCampaign(cfg, makeCampaignSpec(cfg, "P"));
        case "S"
            runUpstreamMorrisCampaign(cfg, makeCampaignSpec(cfg, "S"));
        case "M"
            runUpstreamMorrisCampaign(cfg, makeCampaignSpec(cfg, "M"));
        case "BUILD_P_REGIMES"
            buildRegimeArtifactsStructural(cfg, makeCampaignSpec(cfg, "P"));
        case "BUILD_S_REGIMES"
            buildRegimeArtifactsStructural(cfg, makeCampaignSpec(cfg, "S"));
        case "C"
            runControlRegimeCampaignStructural(cfg);
        case "ALL"
          % runUpstreamMorrisCampaign(cfg, makeCampaignSpec(cfg, "M"));
            runUpstreamMorrisCampaign(cfg, makeCampaignSpec(cfg, "P"));
            runUpstreamMorrisCampaign(cfg, makeCampaignSpec(cfg, "S"));
            buildRegimeArtifactsStructural(cfg, makeCampaignSpec(cfg, "P"));
            buildRegimeArtifactsStructural(cfg, makeCampaignSpec(cfg, "S"));
            runControlRegimeCampaignStructural(cfg);
        otherwise
            error("Unknown mode: %s", mode);
    end
end

