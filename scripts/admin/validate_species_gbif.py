#!/usr/bin/env python3
"""
Validate species names against GBIF taxonomic backbone.

This script checks species definitions in data/lookups/species.csv
against the GBIF Species API to ensure scientific names are standardized
and identify potential issues (synonyms, typos, unknown species).

Usage:
    python validate_species_gbif.py              # Validate all species
    python validate_species_gbif.py --verbose    # Show detailed output
    python validate_species_gbif.py --fix        # Generate suggested corrections CSV

Requirements:
    pip install pygbif

GBIF API Documentation: https://techdocs.gbif.org/en/data-use/pygbif
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

try:
    from pygbif import species as gbif_species
except ImportError:
    print("❌ pygbif not installed. Install with: pip install pygbif")
    sys.exit(1)

# Configuration
SPECIES_CSV = Path(__file__).parent.parent.parent / "data" / "lookups" / "species.csv"
OUTPUT_DIR = Path(__file__).parent.parent.parent / "data" / "lookups"


class Colors:
    """ANSI color codes for terminal output."""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def validate_species(scientific_name: str, verbose: bool = False) -> dict:
    """
    Validate a scientific name against GBIF backbone taxonomy.

    Returns:
        dict with validation results including:
        - status: 'valid', 'synonym', 'misspelling', 'unknown'
        - gbif_key: GBIF usage key if matched
        - accepted_name: GBIF accepted name
        - confidence: match confidence (0-100)
        - issues: list of any issues found
    """
    result = {
        "original_name": scientific_name,
        "status": "unknown",
        "gbif_key": None,
        "accepted_name": None,
        "confidence": 0,
        "match_type": None,
        "taxonomic_status": None,
        "kingdom": None,
        "family": None,
        "rank": None,
        "issues": [],
    }

    try:
        # Query GBIF backbone
        match = gbif_species.name_backbone(
            scientificName=scientific_name,
            kingdom="Plantae",  # Restrict to plants
            strict=False,
            verbose=True,
        )

        if verbose:
            print(f"  GBIF response: {match}")

        # Handle verbose response structure (nested in 'usage' and 'diagnostics')
        usage = match.get("usage", match)
        diagnostics = match.get("diagnostics", {})
        classification = match.get("classification", [])

        # Check match type from diagnostics
        match_type = diagnostics.get("matchType", usage.get("matchType", "NONE"))
        result["match_type"] = match_type

        if match_type == "NONE" or not usage.get("key"):
            result["status"] = "unknown"
            result["issues"].append("No match found in GBIF backbone")
            return result

        # Extract key fields from usage
        result["gbif_key"] = usage.get("key")
        result["confidence"] = diagnostics.get("confidence", 0)
        result["taxonomic_status"] = usage.get("status")
        result["rank"] = usage.get("rank")

        # Extract kingdom and family from classification
        for taxon in classification:
            if taxon.get("rank") == "KINGDOM":
                result["kingdom"] = taxon.get("name")
            elif taxon.get("rank") == "FAMILY":
                result["family"] = taxon.get("name")

        # Check if this is a synonym
        accepted_usage = match.get("acceptedUsage")
        is_synonym = match.get("synonym", False)

        if is_synonym and accepted_usage:
            result["accepted_name"] = accepted_usage.get("canonicalName")
            result["status"] = "synonym"
            result["issues"].append(
                f"Name is a synonym. Accepted name: {result['accepted_name']}"
            )
        else:
            result["accepted_name"] = usage.get("canonicalName")

        # Check for fuzzy matches (potential misspellings)
        if match_type == "FUZZY":
            result["status"] = "misspelling"
            canonical = usage.get("canonicalName", "")
            result["issues"].append(f"Fuzzy match - did you mean '{canonical}'?")
        elif match_type == "HIGHERRANK":
            result["status"] = "partial"
            result["issues"].append(
                f"Only matched to higher rank: {usage.get('rank', 'unknown')}"
            )
        elif result["status"] != "synonym":
            result["status"] = "valid"

        # Check if the returned name differs from input (case/formatting)
        canonical = usage.get("canonicalName", "")
        if canonical and canonical.lower() != scientific_name.lower():
            if result["status"] == "valid":
                result["issues"].append(f"Canonical name differs: '{canonical}'")

    except Exception as e:
        result["status"] = "error"
        result["issues"].append(f"API error: {str(e)}")

    return result


def print_result(species_name: str, result: dict, verbose: bool = False) -> None:
    """Print validation result with colored output."""
    status = result["status"]

    # Status indicator with color
    if status == "valid":
        status_str = f"{Colors.GREEN}✓ VALID{Colors.RESET}"
    elif status == "synonym":
        status_str = f"{Colors.YELLOW}⚠ SYNONYM{Colors.RESET}"
    elif status == "misspelling":
        status_str = f"{Colors.YELLOW}⚠ MISSPELLING{Colors.RESET}"
    elif status == "partial":
        status_str = f"{Colors.YELLOW}⚠ PARTIAL{Colors.RESET}"
    elif status == "unknown":
        status_str = f"{Colors.RED}✗ UNKNOWN{Colors.RESET}"
    else:
        status_str = f"{Colors.RED}✗ ERROR{Colors.RESET}"

    # Print main result
    print(f"  {species_name}: {status_str}")

    # Print issues if any
    if result["issues"]:
        for issue in result["issues"]:
            print(f"    └─ {issue}")

    # Print additional details in verbose mode
    if verbose and result["gbif_key"]:
        print(f"    └─ GBIF Key: {result['gbif_key']}")
        print(f"    └─ Confidence: {result['confidence']}%")
        print(f"    └─ Family: {result.get('family', 'N/A')}")


def validate_all_species(verbose: bool = False) -> list:
    """Validate all species from the CSV file."""
    if not SPECIES_CSV.exists():
        print(f"{Colors.RED}Error: Species file not found: {SPECIES_CSV}{Colors.RESET}")
        sys.exit(1)

    # Load species CSV
    df = pd.read_csv(SPECIES_CSV)
    print(
        f"{Colors.BOLD}Validating {len(df)} species against GBIF backbone...{Colors.RESET}"
    )
    print()

    results = []
    valid_count = 0
    issue_count = 0

    for _, row in df.iterrows():
        scientific_name = row["ScientificName"]
        common_name = row.get("CommonName", "")

        if verbose:
            print(f"\n{Colors.BLUE}Checking: {scientific_name}{Colors.RESET}")

        result = validate_species(scientific_name, verbose=verbose)
        result["common_name"] = common_name
        results.append(result)

        print_result(scientific_name, result, verbose=verbose)

        if result["status"] == "valid":
            valid_count += 1
        else:
            issue_count += 1

    return results


def generate_fix_csv(results: list) -> Path:
    """Generate a CSV with suggested corrections."""
    rows = []
    for r in results:
        rows.append(
            {
                "CommonName": r.get("common_name", ""),
                "OriginalScientificName": r["original_name"],
                "Status": r["status"],
                "GBIFAcceptedName": r.get("accepted_name", ""),
                "GBIFKey": r.get("gbif_key", ""),
                "Confidence": r.get("confidence", ""),
                "MatchType": r.get("match_type", ""),
                "TaxonomicStatus": r.get("taxonomic_status", ""),
                "Kingdom": r.get("kingdom", ""),
                "Family": r.get("family", ""),
                "Issues": "; ".join(r.get("issues", [])),
            }
        )

    output_df = pd.DataFrame(rows)
    output_path = OUTPUT_DIR / "species_gbif_validation.csv"
    output_df.to_csv(output_path, index=False)

    return output_path


def print_summary(results: list) -> None:
    """Print validation summary."""
    valid = sum(1 for r in results if r["status"] == "valid")
    synonyms = sum(1 for r in results if r["status"] == "synonym")
    misspellings = sum(1 for r in results if r["status"] == "misspelling")
    unknown = sum(1 for r in results if r["status"] == "unknown")
    errors = sum(1 for r in results if r["status"] == "error")
    partial = sum(1 for r in results if r["status"] == "partial")

    print()
    print("=" * 60)
    print(f"{Colors.BOLD}VALIDATION SUMMARY{Colors.RESET}")
    print("=" * 60)
    print(f"  {Colors.GREEN}Valid names:{Colors.RESET}     {valid}")
    print(f"  {Colors.YELLOW}Synonyms:{Colors.RESET}        {synonyms}")
    print(f"  {Colors.YELLOW}Misspellings:{Colors.RESET}    {misspellings}")
    print(f"  {Colors.YELLOW}Partial match:{Colors.RESET}   {partial}")
    print(f"  {Colors.RED}Unknown:{Colors.RESET}         {unknown}")
    print(f"  {Colors.RED}Errors:{Colors.RESET}          {errors}")
    print("=" * 60)
    print(f"  Total: {len(results)}")

    if synonyms + misspellings + unknown > 0:
        print()
        print(
            f"{Colors.YELLOW}Tip: Run with --fix to generate a corrections CSV{Colors.RESET}"
        )


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Validate species names against GBIF taxonomic backbone"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show detailed GBIF responses"
    )
    parser.add_argument(
        "--fix",
        "-f",
        action="store_true",
        help="Generate CSV with suggested corrections",
    )
    args = parser.parse_args()

    print()
    print(f"{Colors.BOLD}GBIF Species Name Validation{Colors.RESET}")
    print(f"Source: {SPECIES_CSV}")
    print()

    # Validate all species
    results = validate_all_species(verbose=args.verbose)

    # Print summary
    print_summary(results)

    # Generate fix CSV if requested
    if args.fix:
        output_path = generate_fix_csv(results)
        print()
        print(f"{Colors.GREEN}Generated corrections file: {output_path}{Colors.RESET}")
        print("Review this file and update species.csv as needed.")

    # Return exit code based on issues
    issues = sum(1 for r in results if r["status"] != "valid")
    return 1 if issues > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
