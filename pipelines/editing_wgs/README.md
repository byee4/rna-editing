# Matched RNA/WGS Editing Workflow

This Snakemake workflow aligns matched RNA-seq and WGS inputs, marks
duplicates, adds MD tags, and runs both DNA/RNA comparison callers and RNA-only
editing callers. The DNA/RNA branch uses matched WGS to help remove inherited
variants, while the RNA-only branch provides SPRINT, REDItools2 serial,
DeepRED, editPredict, and REDI-NET outputs from the deduplicated RNA BAM.

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

The workflow passes those one- or two-file FASTQ lists directly to STAR and
BWA-MEM. Downstream caller rules consume BAMs, so SPRINT, REDItools2 serial,
DeepRED, editPredict, and REDI-NET work the same way for single-end and
paired-end samples after alignment.

Primary outputs include:

- `results/reditools2_dnarna/{sample}.tsv`: REDItools DNA/RNA comparison calls.
- `results/jacusa2_dnarna/{sample}.out`: JACUSA2 RNA-DNA difference calls.
- `results/sprint/{sample}/regular.res`: SPRINT RNA-only editing candidates.
- `results/reditools2/{sample}.tsv`: REDItools2 serial RNA-only calls.
- `results/deepred/{sample}_predictions.txt`: DeepRED scores for SPRINT calls.
- `results/editpredict/{sample}_scores.txt`: editPredict scores for SPRINT calls.
- `results/redinet/{sample}_classified.txt`: REDI-NET classes for REDItools2 calls.
- `results/wgs_coverage/{sample}.cov`: WGS-only coverage from `{sample}.wgs.md.bam`.
- `results/germline/{sample}_germline.vcf.gz`: WGS-only germline SNVs from `{sample}.wgs.md.bam`.

Container paths and caller thresholds are defined in `config.yaml`; existing
local SIFs cover STAR through `lodei.sif`, REDItools, JACUSA2, SPRINT, DeepRED,
editPredict, and REDI-NET. The WGS and Picard images need to be built from
`containers/wgs` and `containers/picard` before a full production run:

```bash
TOOLS="wgs picard sprint deepred editpredict redinet" scripts/validate_containers.sh
```

Use `reditools2.min_cov` for both DNA/RNA and RNA-only REDItools2 coverage, and
the `redinet` block to tune REDI-NET minimum coverage, A-to-G frequency, and
minimum A-to-G substitution count. DNA coverage and germline variant rules are
restricted to the MD-tagged WGS BAM path, `results/mapped/{sample}.wgs.md.bam`,
so they are not scheduled for RNA BAMs. Real runs require the configured FASTQs,
reference FASTA, and STAR genome index at `refs/genome.fa_idx`.
