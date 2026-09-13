
from .campaigns import participants
from pathlib import Path
import hashlib
import json
import math
import numpy as np
import pandas as pd
import re
from .campaigns import ALIASES, CAMPAIGNS, PHYSICAL_INPUTS, SOURCE_METADATA
from .preparation import finite, stable_groups


def clean_json(value):
    """JSON null represents unavailable values; never emit nonstandard NaN."""
    if isinstance(value, dict):
        return {str(k): clean_json(v) for k, v in value.items()}
    if isinstance(value, (tuple, list, np.ndarray)):
        return [clean_json(v) for v in value]
    if isinstance(value, (np.integer,)):
        return int(value)
    if isinstance(value, (np.bool_,)):
        return bool(value)
    if isinstance(value, (float, np.floating)):
        return float(value) if math.isfinite(value) else None
    if isinstance(value, Path):
        return str(value)
    if value is pd.NA:
        return None
    return value


def write_json(path, value):
    Path(path).write_text(json.dumps(clean_json(value), indent=2, allow_nan=False) + "\n",
                          encoding="utf-8")


def write_csv(path, rows, columns=None):
    frame = rows if isinstance(rows, pd.DataFrame) else pd.DataFrame(rows, columns=columns)
    frame.to_csv(path, index=False, float_format="%.12g")


def read_csv(path):
    frame = pd.read_csv(path)
    frame.columns = frame.columns.str.strip()
    for alias, canonical in ALIASES.items():
        if alias in frame and canonical not in frame:
            frame = frame.rename(columns={alias: canonical})
    return frame


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def locate_campaigns(folder):
    folder = Path(folder)
    candidates = [folder / "FunctionalCampaign" / "functional_campaign_results",
                  folder / "functional_campaign_results", folder]
    roots = [p for p in candidates if p.is_dir()]
    for root in roots:
        entries = []
        own = root / "campaign_summary_design_aggregated.csv"
        paths = [own] if own.exists() else sorted(root.glob("*/campaign_summary_design_aggregated.csv"))
        for path in paths:
            match = re.search(r"campaign_([PSCM])_functional", path.parent.name, re.I)
            if match:
                entries.append((CAMPAIGNS[match.group(1).upper()], path))
        if entries:
            return root, sorted(entries, key=lambda x: ("PSCM".index(x[0]['code']), str(x[1])))
    raise FileNotFoundError("No recognized campaign_summary_design_aggregated.csv found. "
                            "Pass the extracted results folder, its parent, or one campaign folder.")


def load_campaign(path, spec):
    data = read_csv(path).sort_values("design_id").reset_index(drop=True)
    if data.design_id.isna().any() or data.design_id.duplicated().any():
        raise ValueError("Aggregate design_id must be present and unique.")
    warnings, checks = [], []
    raw_path = path.with_name("campaign_summary_runs_raw.csv")
    raw = read_csv(raw_path) if raw_path.exists() else None
    if raw is not None:
        rep_col = "replicate_id" if "replicate_id" in raw else "rep"
        if rep_col not in raw or raw[["design_id", rep_col]].isna().any().any():
            raise ValueError("Raw rows require nonmissing design_id and replicate_id/rep.")
        if raw.duplicated(["design_id", rep_col]).any():
            raise ValueError("Raw design/replicate duplicates need explicit attempt selection; not guessed.")
        if set(raw.design_id) != set(data.design_id):
            raise ValueError("Raw and aggregate design identifiers do not match.")
        recovered = []
        for col in PHYSICAL_INPUTS + SOURCE_METADATA:
            if col not in raw:
                continue
            if raw.groupby("design_id")[col].nunique(dropna=False).gt(1).any():
                raise ValueError(f"{col} changes between replicates of the same design.")
            mapping = raw.groupby("design_id", sort=False)[col].first()
            values = data.design_id.map(mapping)
            if col in data:
                both = data[col].notna() & values.notna()
                if pd.api.types.is_numeric_dtype(values):
                    same = np.isclose(finite(data.loc[both, col]), finite(values[both]), rtol=1e-9, atol=1e-10)
                else:
                    same = data.loc[both, col].astype(str).to_numpy() == values[both].astype(str).to_numpy()
                if not np.all(same):
                    raise ValueError(f"Raw and aggregate values conflict for {col}.")
                data[col] = data[col].combine_first(values)
            else:
                data[col] = values
                recovered.append(col)
        checks.append({"check": "metadata_join", "status": "OK", "details": ";".join(recovered)})
    else:
        warnings.append("Raw run CSV absent: metadata recovery and replicate checks unavailable.")

    # Group C by its actual fixed background, not by labels pooled across backgrounds.
    missing = [x for x in participants(spec) if x not in data]
    if spec['code'] == "C":
        background = [x for x in ("target_blob_size", "luminosity_level", "v_nominal", "friction_surface") if x in data]
        if len(background) == 4:
            data["representative_id"] = stable_groups(data, background) + 1
        elif all(x in data for x in spec['srp_inputs']):
            data["representative_id"] = stable_groups(data, spec['srp_inputs']) + 1
            warnings.append("Representative IDs inferred from the recorded upstream SRP pair only.")
        if all(x in data for x in ("source_regime_P", "source_regime_S")):
            composed = data.source_regime_P.astype(str) + "__" + data.source_regime_S.astype(str)
            if "joint_cell" not in data:
                data["joint_cell"] = composed
            elif not data.joint_cell.eq(composed).all():
                raise ValueError("Joint regime labels conflict with source_regime_P/S.")
        if "representative_id" in data:
            for col in spec['srp_inputs'] + ("joint_cell",):
                if col in data and data.groupby("representative_id")[col].nunique(dropna=False).gt(1).any():
                    raise ValueError(f"{col} conflicts within a C representative.")
    if missing:
        warnings.append("Primary model unavailable: required participants missing: " + ", ".join(missing))
    return data, raw, checks, warnings


def package_source_hashes():
    package = Path(__file__).resolve().parent
    return {path.name: sha256(path) for path in sorted(package.glob("*.py"))}