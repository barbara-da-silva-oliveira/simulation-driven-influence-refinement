"""Sign-following robot case-study definitions."""

SRPS = (
    "completed", "completion_time", "average_segment_speed",
    "sign_detection_quality", "tracking_error_rms", "left_distance_to_sign",
    "right_distance_to_sign", "stop_distance_to_sign", "time_turning",
    "time_to_next_blob20_first", "time_to_next_blob20_count",
)


PHYSICAL_INPUTS = (
    "target_blob_size", "luminosity_level", "v_nominal", "friction_surface",
    "w_gain", "wall_transparency",
)


SOURCE_METADATA = (
    "source_regime", "source_regime_P", "source_regime_S", "source_srp_P",
    "source_srp_S", "joint_cell", "sdq_regime", "as_regime",
)


NUMERIC_VALID = {"VALID", "VALID_ZERO", "VALID_BOOLEAN", "OK",
                 "OK_ALL_REPLICATES", "OK_PARTIAL_REPLICATES"}


ALIASES = {"size": "target_blob_size", "luminosity": "luminosity_level",
           "v": "v_nominal", "friction": "friction_surface", "w": "w_gain",
           "transparency": "wall_transparency"}


UNITS = {"completion_time": "s", "average_segment_speed": "m/s",
         "sign_detection_quality": "dimensionless", "tracking_error_rms": "pixel",
         "time_turning": "s", "time_to_next_blob20_first": "s",
         "time_to_next_blob20_count": "count", "completed": "Boolean",
         **{x: "m" for x in SRPS if "distance_to_sign" in x}}


SHORT = {"target_blob_size": "Blob size", "luminosity_level": "Luminosity",
         "v_nominal": "Nominal velocity", "friction_surface": "Friction",
         "w_gain": "Angular gain", "source_srp_P": "Upstream SDQ",
         "source_srp_S": "Upstream speed"}


CAMPAIGNS = {
    "P": {
        "code": "P", "influence": "I_Perception", "output_srp": "sign_detection_quality",
        "artifacts": ("target_blob_size",), "envFactors": ("luminosity_level",),
        "srp_inputs": (), "objective": "maximize",
    },
    "S": {
        "code": "S", "influence": "I_Locomotion", "output_srp": "average_segment_speed",
        "artifacts": ("v_nominal",), "envFactors": ("friction_surface",),
        "srp_inputs": (), "objective": "maximize",
    },
    "C": {
        "code": "C", "influence": "I_Control", "output_srp": "tracking_error_rms",
        "artifacts": ("w_gain",), "envFactors": (),
        "srp_inputs": ("source_srp_P", "source_srp_S"), "objective": "minimize",
    },
    "M": {
        "code": "M", "influence": "I_SignSearch", "output_srp": "time_turning",
        "artifacts": ("v_nominal", "w_gain"), "envFactors": ("friction_surface",),
        "srp_inputs": (), "objective": "minimize",
    },
}


def participants(spec):
    """Retourner les noms des participants, dans l'ordre des colonnes du modèle."""
    return spec["artifacts"] + spec["envFactors"] + spec["srp_inputs"]


def participant_role(spec, participant):
    """Retourner le rôle d'un participant déclaré dans cette campagne."""
    if participant in spec["artifacts"]:
        return "DesignArtifact"
    if participant in spec["envFactors"]:
        return "EnvironmentalFactor"
    return "SRPInputParticipant"
