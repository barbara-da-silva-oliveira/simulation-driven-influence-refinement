"""
Modify INPUT_FOLDER et OUTPUT_FOLDER.
The numerical parameters can be modified in influence_analyzer/config.py.
"""

from pathlib import Path

from influence_analyzer.config import SETTINGS
from influence_analyzer.pipeline import run_analysis


PROJECT_FOLDER = Path(__file__).resolve().parent
INPUT_FOLDER = PROJECT_FOLDER / "FunctionalCampaign" / "functional_campaign_results"
OUTPUT_FOLDER = PROJECT_FOLDER / "FunctionalCampaign" / "functional_results"


def main():
    return run_analysis(INPUT_FOLDER, OUTPUT_FOLDER, SETTINGS)


if __name__ == "__main__":
    raise SystemExit(main())
