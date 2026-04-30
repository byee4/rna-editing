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
- DeepRed prediction.
- EditPredict scoring.
- REDInet classification.

Docker build contexts were added under `containers/wgs`, `containers/deepred`,
`containers/editpredict`, and `containers/redinet`. Build them with:

```bash
TOOLS="wgs deepred editpredict redinet" scripts/validate_containers.sh
```

The DeepRed container is intentionally a scaffold because this repository does
not include a concrete upstream source checkout or trained model artifact. The
wrapper exits with a clear message until those assets are installed. EditPredict
and REDInet include upstream source checkouts and stable wrappers, but their
input expectations should be validated on real workflow data.
