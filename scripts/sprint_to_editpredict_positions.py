#!/usr/bin/env python
"""Convert SPRINT regular RES output into EditPredict position input.

EditPredict's upstream get_seq.py expects tab-separated rows with chromosome in
the first column and a one-based locus in the second column. SPRINT regular RES
files are BED-like: chromosome, zero-based start, and one-based end. This
adapter strips common chr prefixes and writes the end coordinate as the locus.
"""

import argparse
import os


def normalize_chromosome(raw_chromosome):
    """Return the chromosome token format accepted by EditPredict get_seq.py."""
    chromosome = raw_chromosome.strip()
    if chromosome.lower().startswith("chr"):
        chromosome = chromosome[3:]
    if chromosome == "MT":
        chromosome = "M"

    if chromosome in {"X", "Y", "M"} or chromosome.isdigit():
        return chromosome
    raise ValueError(
        "EditPredict only supports numeric, X, Y, or M chromosomes; got {!r}".format(
            raw_chromosome
        )
    )


def convert_sprint_positions(input_path, output_path):
    """Write EditPredict chromosome/locus rows from a SPRINT regular RES file."""
    converted = 0
    with open(input_path) as source, open(output_path, "w") as target:
        for line_number, line in enumerate(source, start=1):
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n\r").split("\t")
            if len(fields) < 3:
                raise ValueError(
                    "{}:{} has {} columns; expected at least 3".format(
                        input_path, line_number, len(fields)
                    )
                )

            chromosome = normalize_chromosome(fields[0])
            try:
                locus = int(fields[2])
            except ValueError as exc:
                raise ValueError(
                    "{}:{} has a non-integer one-based end coordinate: {!r}".format(
                        input_path, line_number, fields[2]
                    )
                )
            if locus < 1:
                raise ValueError(
                    "{}:{} has a non-positive locus: {}".format(input_path, line_number, locus)
                )

            target.write("{}\t{}\n".format(chromosome, locus))
            converted += 1
    return converted


def main():
    """Run the SPRINT-to-EditPredict position conversion command."""
    parser = argparse.ArgumentParser(
        description="Convert SPRINT regular RES output to EditPredict chromosome/locus TSV."
    )
    parser.add_argument("input", help="SPRINT regular.res or SPRINT_identified_regular.res")
    parser.add_argument("output", help="EditPredict positions TSV to write")
    args = parser.parse_args()

    output_dir = os.path.dirname(args.output)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    convert_sprint_positions(args.input, args.output)


if __name__ == "__main__":
    main()
