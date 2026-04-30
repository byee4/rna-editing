# RNA Editing Workflow

This Snakemake workflow runs container-aware RNA editing callers and downstream
classifiers. Container paths are configured in `config.yaml` and default to
SIFs under `/Volumes/X9Pro/container_data/singularity_images`.

Run with Singularity/Apptainer enabled:

```bash
snakemake --snakefile pipelines/editing/Snakefile --directory pipelines/editing --use-singularity --cores 16
```

The reviewed default DAG excludes SAILOR per project direction. JACUSA2 uses
MD-tagged BAMs when the configured pair BAM paths match entries in `samples`.
REDItools2 writes one TSV per sample, which is then used as REDInet input.
EditPredict scores SPRINT calls after converting SPRINT's BED-like coordinates
to the chromosome/locus list expected by upstream `get_seq.py`.
DeepRed scores SPRINT calls after converting SPRINT's regular RES table to the
four-column candidate SNV input documented by upstream DeepRed
(`#CHROM`, `POS`, `REF`, `ALT`). The DeepRed wrapper then stages that file as
`Raw_Data/<sample>/<sample>.gatk.raw.vcf` and runs the upstream
`Preprocess_input_data_for_DeepRed.pl <project> <sample>` followed by
`Run_DeepRed.pl <project> <sample>`.

DeepRed, EditPredict, and REDInet depend on Docker contexts added under
`containers/`. Build their SIFs before enabling production runs:

```bash
TOOLS="deepred editpredict redinet" scripts/validate_containers.sh
```
