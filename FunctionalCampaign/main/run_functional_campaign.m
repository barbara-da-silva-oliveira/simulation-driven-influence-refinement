function run_functional_campaign(mode)
% Functional refinement with automatic WLHS weights loaded fromstructural campaigns.
% 
% Modes:
%   P_FUNC
%   S_FUNC
%   BUILD_C_REGIMES
%   C_FUNC
%   M_FUNC
%   ALL

    if nargin < 1
        error('Provide a mode, e.g. signfollow_functional_hierarchical_auto_v2("P_FUNC").');
    end
    
    cfg = defaultConfigFunctional();
    mode = upper(string(mode));
    
    switch mode
        case "P_FUNC"
            spec = makeFunctionalSpec(cfg, "P_FUNC");
            runWLHSCampaign(cfg, spec);
        case "S_FUNC"
            spec = makeFunctionalSpec(cfg, "S_FUNC");
            runWLHSCampaign(cfg, spec);
        case "BUILD_C_REGIMES"
            buildJointObservedRegimesForC(cfg);
        case "C_FUNC"
            runControlWLHSCampaign(cfg);
       case "M_FUNC"
            spec = makeFunctionalSpec(cfg, "M_FUNC");
            runWLHSCampaign(cfg, spec);
        case "ALL"
            spec = makeFunctionalSpec(cfg, "P_FUNC");
            runWLHSCampaign(cfg, spec);
    
            spec = makeFunctionalSpec(cfg, "S_FUNC");
            runWLHSCampaign(cfg, spec);
        
            buildJointObservedRegimesForC(cfg);
            runControlWLHSCampaign(cfg);

            spec = makeFunctionalSpec(cfg, "M_FUNC");
            runWLHSCampaign(cfg, spec);

        otherwise
            error('Unknown mode: %s', mode);
    end
end