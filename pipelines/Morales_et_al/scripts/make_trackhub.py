#!/usr/bin/env python3
"""
make_trackhub.py — Build a UCSC trackhub from BigWig and BigBed files.

Uses the daler/trackhub library (pip install trackhub).

Hub structure:
  hub.txt
  genomes.txt
  {assembly}/
    trackDb.txt
    (BigWig and BigBed files are referenced by absolute or relative path)

Track organization:
  One composite superTrack per sample, containing:
    - One BigWig track per aligner (coverage)
    - One BigBed track per tool per aligner (edit sites)

Run via:
  module load python3essential
  python3 make_trackhub.py \\
      --bigwig-dir results/bigwig/ \\
      --bigbed-dir results/bigbed/ \\
      --outdir results/trackhub/ \\
      --assembly hg38 \\
      --hub-name "Morales_et_al RNA Editing" \\
      --email your@email.com \\
      --aligners star bwa hisat2 \\
      --tools reditools sprint red_ml reditools3 redinet marine bcftools \\
      --conditions WT ADAR1KO \\
      --samples clone1 clone2 clone3
"""

import argparse
import os
import sys


# Colour palette for aligners / tools (UCSC hex, no #)
_ALIGNER_COLOURS = {
    "star":   "31,119,180",
    "bwa":    "255,127,14",
    "hisat2": "44,160,44",
}
_TOOL_COLOURS = {
    "reditools":  "214,39,40",
    "reditools2": "214,39,40",
    "reditools3": "148,103,189",
    "sprint":     "140,86,75",
    "red_ml":     "227,119,194",
    "redml":      "227,119,194",
    "bcftools":   "127,127,127",
    "jacusa2":    "188,189,34",
    "redinet":    "23,190,207",
    "marine":     "174,199,232",
}
_DEFAULT_COLOUR = "100,100,100"


def colour(name, palette):
    return palette.get(name, _DEFAULT_COLOUR)


def build_hub(args):
    try:
        import trackhub
    except ImportError:
        sys.exit(
            "trackhub not installed. Run: pip install --user trackhub\n"
            "Or: pip install trackhub"
        )

    hub, genomes_file, genome, trackdb = trackhub.default_hub(
        hub_name=args.hub_name,
        short_label=args.hub_name,
        long_label=args.hub_name,
        genome=args.assembly,
        email=args.email,
    )

    for condition in args.conditions:
        for sample in args.samples:
            sample_id = f"{condition}_{sample}"
            super_track = trackhub.SuperTrack(
                name=f"super_{sample_id}",
                short_label=sample_id,
                long_label=f"RNA editing — {sample_id}",
            )
            trackdb.add_tracks(super_track)

            for aligner in args.aligners:
                # --- BigWig coverage track ---
                bw_path = os.path.join(
                    args.bigwig_dir, aligner, f"{sample_id}.bw"
                )
                if os.path.exists(bw_path):
                    bw_track = trackhub.Track(
                        name=f"bw_{sample_id}_{aligner}",
                        short_label=f"{aligner} coverage",
                        long_label=f"{sample_id} {aligner} CPM coverage",
                        tracktype="bigWig",
                        source=os.path.abspath(bw_path),
                        visibility="full",
                        color=colour(aligner, _ALIGNER_COLOURS),
                        autoScale="on",
                        windowingFunction="mean",
                    )
                    super_track.add_tracks(bw_track)

                # --- BigBed edit-site tracks (one per tool) ---
                for tool in args.tools:
                    bb_path = os.path.join(
                        args.bigbed_dir, tool, aligner, f"{sample_id}.bb"
                    )
                    if os.path.exists(bb_path):
                        bb_track = trackhub.Track(
                            name=f"bb_{sample_id}_{aligner}_{tool}",
                            short_label=f"{tool}/{aligner}",
                            long_label=f"{sample_id} {tool} ({aligner}) edit sites",
                            tracktype="bigBed 6",
                            source=os.path.abspath(bb_path),
                            visibility="pack",
                            color=colour(tool, _TOOL_COLOURS),
                        )
                        super_track.add_tracks(bb_track)

    os.makedirs(args.outdir, exist_ok=True)
    trackhub.upload.stage_hub(hub, staging=args.outdir)
    hub_txt = os.path.join(args.outdir, "hub.txt")
    print(f"Hub written to {hub_txt}", file=sys.stderr)
    print(f"Load in UCSC: https://genome.ucsc.edu/cgi-bin/hgTracks?hubUrl=<URL>/hub.txt",
          file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bigwig-dir", required=True)
    ap.add_argument("--bigbed-dir", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--assembly", default="hg38")
    ap.add_argument("--hub-name", default="Morales_et_al RNA Editing")
    ap.add_argument("--email", default="user@example.com")
    ap.add_argument("--aligners", nargs="+", default=["star"])
    ap.add_argument("--tools", nargs="+",
                    default=["reditools", "sprint", "red_ml",
                             "reditools3", "redinet", "marine"])
    ap.add_argument("--conditions", nargs="+", required=True)
    ap.add_argument("--samples", nargs="+", required=True)
    args = ap.parse_args()

    build_hub(args)


if __name__ == "__main__":
    main()
