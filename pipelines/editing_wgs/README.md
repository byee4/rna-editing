# Matched RNA/WGS Editing Workflow

This Snakemake workflow aligns matched RNA-seq and WGS inputs, marks
duplicates, adds MD tags, and runs DNA/RNA comparison callers.

Run with Singularity/Apptainer enabled:

```bash
snakemake --snakefile pipelines/editing_wgs/Snakefile --directory pipelines/editing_wgs --use-singularity --cores 24
```

The config maps each sample to RNA and WGS FASTQs. Each `rna` or `wgs` entry can
be either a single FASTQ path for single-end data or a two-item list for paired
R1/R2 data:

```yaml
samples:
  single_end_sample:
    rna: "raw/sample_rna.fastq.gz"
    wgs: "raw/sample_wgs.fastq.gz"
  paired_end_sample:
    rna:
      - "raw/sample_rna_R1.fastq.gz"
      - "raw/sample_rna_R2.fastq.gz"
    wgs:
      - "raw/sample_wgs_R1.fastq.gz"
      - "raw/sample_wgs_R2.fastq.gz"
```

Container paths are defined in `config.yaml`; existing local SIFs cover STAR
through `lodei.sif`, REDItools, and JACUSA2. The WGS and Picard images need to
be built from `containers/wgs` and `containers/picard` before a full production
run:

```bash
TOOLS="wgs picard" scripts/validate_containers.sh
```

The DAG dry-run was verified with placeholder configured inputs. Real runs still
require the configured FASTQs, reference FASTA, and STAR genome index at
`refs/genome.fa_idx`.
