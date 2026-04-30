#!/usr/bin/env python3
"""Convert SPRINT regular RES output into DeepRed candidate SNVs.

DeepRed's upstream README documents a VCF-like input table with chromosome,
position, reference base, and alternate base columns. SPRINT regular RES files
use chromosome, zero-based start, one-based end, and edit type columns, so this
adapter writes the one-based end coordinate and splits edit types such as
``AG`` into REF ``A`` and ALT ``G``.
"""

import argparse
import os


VALID_BASES = {"A", "C", "G", "T"}


def parse_edit_type(raw_type, input_path, line_number):
    """Return REF and ALT bases from a SPRINT edit type token."""
    edit_type = raw_type.strip().upper()
    if len(edit_type) != 2 or any(base not in VALID_BASES for base in edit_type):
        raise ValueError(
            "{}:{} has invalid SPRINT edit type {!r}; expected two A/C/G/T bases".format(
                input_path, line_number, raw_type
            )
        )
    return edit_type[0], edit_type[1]


def convert_sprint_res_to_deepred_vcf(input_path, output_path):
    """Write DeepRed chromosome/position/ref/alt rows from SPRINT RES calls."""
    converted = 0
    with open(input_path) as source, open(output_path, "w") as target:
        target.write("#CHROM\tPOS\tREF\tALT\n")
        for line_number, line in enumerate(source, start=1):
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n\r").split("\t")
            if len(fields) < 4:
                raise ValueError(
                    "{}:{} has {} columns; expected at least 4".format(
                        input_path, line_number, len(fields)
                    )
                )

            chromosome = fields[0].strip()
            if not chromosome:
                raise ValueError("{}:{} has an empty chromosome".format(input_path, line_number))
            try:
                position = int(fields[2])
            except ValueError as exc:
                raise ValueError(
                    "{}:{} has a non-integer one-based end coordinate: {!r}".format(
                        input_path, line_number, fields[2]
                    )
                ) from exc
            if position < 1:
                raise ValueError(
                    "{}:{} has a non-positive position: {}".format(
                        input_path, line_number, position
                    )
                )

            ref, alt = parse_edit_type(fields[3], input_path, line_number)
            target.write("{}\t{}\t{}\t{}\n".format(chromosome, position, ref, alt))
            converted += 1
    return converted


def main():
    """Run the SPRINT-to-DeepRed VCF conversion command."""
    parser = argparse.ArgumentParser(
        description="Convert SPRINT regular RES output to DeepRed candidate SNV input."
    )
    parser.add_argument("input", help="SPRINT regular.res or SPRINT_identified_regular.res")
    parser.add_argument("output", help="DeepRed candidate VCF-like table to write")
    args = parser.parse_args()

    output_dir = os.path.dirname(args.output)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    convert_sprint_res_to_deepred_vcf(args.input, args.output)


if __name__ == "__main__":
    main()
