# Snakefile Command Audit

This audit compares the command-line calls in `pipelines/editing/Snakefile` and
`pipelines/WGS/Snakefile.yaml` with the Singularity images found in
`/Volumes/X9Pro/container_data/singularity_images`.

## Existing Images

The local image directory contains SIFs for JACUSA2, LoDEI, RED, REDItools,
SAILOR, and SPRINT. SAILOR is intentionally ignored in the current workflow
review.

## Corrections Applied

- `samtools calmd` in the editing workflow now writes BAM output to the declared
  file and stderr to the log. The previous command redirected stdout twice,
  which would have sent the BAM stream to the log instead of the Snakemake
  output.
- JACUSA2 now runs from `/opt/jacusa2/jacusa2.jar`, matching the `jacusa2.sif`
  build, and its pair inputs use MD-tagged BAMs when the configured pair paths
  match known samples.
- REDItools2 now calls `/opt/reditools2/src/cineca/reditools.py` from
  `reditools.sif` and produces a declared TSV output instead of treating the
  output as an opaque directory.
- Downstream DeepRed, EditPredict, and REDInet rules now declare logs and call
  stable wrapper commands supplied by their container contexts.
- The WGS workflow now uses a dedicated `wgs.sif` container path for BWA,
  SAMtools, BCFtools, and tabix calls.
- The WGS duplicate-marking pipeline now name-sorts reads before `samtools
  fixmate`, then coordinate-sorts before `samtools markdup`.
- The WGS BAM and VCF indexing rules now declare their `.bai` and `.tbi`
  outputs, matching the files targeted by `rule all`.

## Missing Images And Dockerfiles

No matching SIF was present for these Snakefile dependencies:

- WGS preprocessing: `bwa`, `samtools`, `bcftools`, and `tabix`.
- Picard duplicate marking.
- DeepRed prediction.
- EditPredict scoring.
- REDInet classification.

Docker build contexts were added under `containers/wgs`, `containers/deepred`,
`containers/editpredict`, `containers/redinet`, and `containers/picard`. Build
them with:

```bash
TOOLS="wgs deepred editpredict redinet picard" scripts/validate_containers.sh
```

The DeepRed container is intentionally a scaffold because this repository does
not include a concrete upstream source checkout or trained model artifact. The
wrapper exits with a clear message until those assets are installed. EditPredict
and REDInet include upstream source checkouts and stable wrappers, but their
input expectations should be validated on real workflow data.

## `editing_wgs` Updates

The combined RNA/WGS workflow in `pipelines/editing_wgs` was checked with the
same approach. Its DAG validates with placeholder inputs and contains 17 jobs:
two STAR RNA alignments, two BWA WGS alignments, four Picard duplicate-marking
jobs, four MD-tagging jobs, two REDItools DNA/RNA calls, two JACUSA2 DNA/RNA
calls, and the aggregate `all` rule.

Corrections applied there:

- STAR now moves `*.Aligned.sortedByCoord.out.bam` to the declared Snakemake
  output and uses `zcat` for gzipped FASTQs.
- BWA/SAMtools, STAR, Picard, SAMtools `calmd`, REDItools, and JACUSA2 rules now
  declare container images through `config.yaml`.
- REDItools DNA/RNA mode now calls the script path installed in
  `reditools.sif` and writes a declared TSV output.
- JACUSA2 now calls `/opt/jacusa2/jacusa2.jar`, matching `jacusa2.sif`.
- Sample `rna` and `wgs` entries now accept either a single FASTQ string or a
  two-item FASTQ list so STAR and BWA can run single-end or paired-end reads.
