# User Guide: Morales_et_al RNA Editing Pipeline

## Overview

The `pipelines/Morales_et_all/` pipeline is a Snakemake 9+ workflow for comparative RNA editing analysis. It reproduces the Morales et al. benchmarking approach, running five RNA editing callers (REDItools2, SPRINT, RED-ML, BCFtools, JACUSA2) on paired WT vs. ADAR1KO samples and comparing results with an Alu and HEK293T SNP database.

**Input**: RNA-seq paired-end FASTQs (listed in a samplesheet CSV) plus optional WGS FASTQs for SNP database generation.
**Output**: Per-tool calling results in `results/tools/`, reference JSON databases in the configured `db_path`, and final comparison outputs in `results/downstream/`.

---

## Getting Started

### 1. Set Up the Environment

```bash
# Load Apptainer (required on TSCC)
module load singularitypro

# Activate the Snakemake 9 environment
conda activate snakemake9
```

### 2. Build Required Containers

The pipeline requires nine SIF files in `singularity/`. Four are new to this pipeline; five are shared with `pipelines/editing_wgs/`. Build the new ones:

```bash
# From the repository root
TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
```

Copy the resulting `.sif` files to `singularity/`, or set `singularity_image_dir` in `config.yaml` to point to the output directory.

### 3. Prepare the Samplesheet

Create `pipelines/Morales_et_all/samplesheet.csv` with columns:

| Column | Description |
|--------|-------------|
| `conditions` | Experimental condition label, e.g., `WT` or `ADAR1KO` |
| `samples` | Sample replicate identifier, e.g., `rep1` |
| `fastq_1` | Absolute path to R1 FASTQ.GZ |
| `fastq_2` | Absolute path to R2 FASTQ.GZ (leave blank for single-end) |

Example:

```csv
conditions,samples,fastq_1,fastq_2
WT,rep1,/path/to/WT_rep1_R1.fastq.gz,/path/to/WT_rep1_R2.fastq.gz
WT,rep2,/path/to/WT_rep2_R1.fastq.gz,/path/to/WT_rep2_R2.fastq.gz
ADAR1KO,rep1,/path/to/ADAR1KO_rep1_R1.fastq.gz,/path/to/ADAR1KO_rep1_R2.fastq.gz
ADAR1KO,rep2,/path/to/ADAR1KO_rep2_R1.fastq.gz,/path/to/ADAR1KO_rep2_R2.fastq.gz
```

### 4. Configure `config.yaml`

Edit `pipelines/Morales_et_all/config.yaml` to set correct paths for your cluster:

- `references.fasta` — GRCh38 FASTA (no-alt analysis set)
- `references.star_index` — STAR index directory (pre-built for GRCh38 + Gencode v40)
- `references.rmsk` — RepeatMasker `rmsk.txt` (raw UCSC download)
- `references.dbsnp` — dbSNP `snp151CodingDbSnp.txt.gz`
- `references.db_path` — output directory for JSON reference databases
- `wgs_samples` — (optional) map of WGS sample name to FASTQ paths for SNP database generation

### 5. Initialize the Downstream Submodule

The downstream Python scripts live in a git submodule:

```bash
git submodule update --init pipelines/Morales_et_all/Benchmark-of-RNA-Editing-Detection-Tools
```

### 6. Run the Pipeline

```bash
cd pipelines/Morales_et_all
unset SLURM_JOB_ID   # required on interactive SLURM nodes

snakemake -kps Snakefile \
  --configfile config.yaml \
  --profile /tscc/nfs/home/bay001/projects/codebase/rna-editing/profiles/tscc2 \
  --use-singularity
```

---

## Pipeline Stages

### Preprocessing

| Rule | Container | Input | Output |
|------|-----------|-------|--------|
| `prepare_fastq` | (localrule) | samplesheet FASTQ.GZ | `data/fastq/{condition}_{sample}_{read}.fastq` |
| `trim_reads` | `fastx.sif` | `.fastq` | `results/trimmed/{condition}_{sample}_{read}_trimmed.fastq.gz` |
| `star_mapping` | `star.sif` | trimmed FASTQs | `results/mapped/{condition}_{sample}.bam[.bai]` |
| `mark_duplicates` | `picard.sif` | `.bam` | `.rmdup.bam`, `.duplication.info` |

### RNA Editing Callers (per sample)

| Rule | Container | Output |
|------|-----------|--------|
| `reditools` | `reditools.sif` | `results/tools/reditools/{condition}_{sample}.output` |
| `sprint` | `sprint.sif` | `results/tools/sprint/{condition}_{sample}_output` |
| `bcftools` | `wgs.sif` | `results/tools/bcftools/{condition}_{sample}.bcf` |
| `red_ml` | `red_ml.sif` | `results/tools/red_ml/{condition}_{sample}_output/` |
| `add_md_tag` | `wgs.sif` | `results/mapped/{condition}_{sample}.rmdup_MD.bam` |
| `jacusa2` | `jacusa2.sif` | `results/tools/jacusa2/Jacusa.out` (aggregates all samples) |

### Reference Database Generation

| Rule | Container | Description |
|------|-----------|-------------|
| `generate_simple_repeat` | `wgs.sif` | Converts raw UCSC `simpleRepeat.txt` to merged BED |
| `generate_alu_bed` | `wgs.sif` | Extracts Alu elements from `rmsk.txt` to BED |
| `wgs_bwa_mem` | `wgs.sif` | BWA-MEM alignment of WGS FASTQs |
| `wgs_deduplicate` | `wgs.sif` | Samtools markdup on WGS BAM |
| `wgs_md_tags` | `wgs.sif` | Adds MD tags to WGS BAM |
| `wgs_call_variants` | `wgs.sif` | BCFtools germline variant calling |
| `wgs_vcf_to_ag_tc_bed` | `wgs.sif` | Filters A>G and T>C SNPs to BED |
| `build_dbrna_editing` | `morales_downstream.sif` | Builds three JSON databases |

### Downstream Analysis

All five downstream rules use `morales_downstream.sif` and the Benchmark submodule scripts:

| Rule | Script | Input | Output |
|------|--------|-------|--------|
| `run_downstream_parsers` | REDItools2.py, SPRINT.py, REDML.py, BCFtools.py, JACUSA2.py | All tool outputs | `results/downstream/parsers.done` |
| `update_alu` | Alu.py | parsers.done | `results/downstream/alu_updated.done` |
| `individual_analysis` | Individual-Analysis.py | alu_updated.done | `results/downstream/individual_analysis.done` |
| `reanalysis_multiple` | Re-Analysis-Multiple.py | individual_analysis.done | `results/downstream/reanalysis_multiple.done` |
| `multiple_analysis` | Multiple-Analysis.py | reanalysis_multiple.done | `results/downstream/multiple_analysis.done` |

---

## Configuration Reference

All settings are in `pipelines/Morales_et_all/config.yaml`.

| Key | Default / Example | Description |
|-----|-------------------|-------------|
| `threads` | `8` | CPU threads per STAR and BWA-MEM rule |
| `samplesheet` | `samplesheet.csv` | Path to CSV with conditions, samples, and FASTQ paths |
| `singularity_image_dir` | `/tscc/.../singularity` | Fallback SIF search directory |
| `containers.*` | (9 explicit SIF paths) | Override path for a specific container by tool name |
| `references.fasta` | (TSCC path) | GRCh38 reference FASTA |
| `references.star_index` | (TSCC path) | STAR genome index directory |
| `references.rmsk` | (TSCC path) | RepeatMasker `rmsk.txt` |
| `references.dbsnp` | (TSCC path) | dbSNP `.txt.gz` |
| `references.simple_repeat_src` | (TSCC path) | Raw UCSC `simpleRepeat.txt` |
| `references.simple_repeat` | (TSCC path) | Output merged BED (generated by pipeline) |
| `references.alu_bed` | (TSCC path) | Output Alu BED (generated by pipeline) |
| `references.rediportal_hg38` | (TSCC path) | REDIportal hg38 table `.txt.gz` |
| `references.db_path` | (TSCC path) | Output directory for three JSON databases |
| `wgs_samples` | (sample map) | WGS sample name → FASTQ path list for SNP DB generation |
| `downstream_scripts_dir` | `Benchmark-of-RNA-Editing-Detection-Tools/Downstream` | Path to downstream Python scripts |
| `params.fastx_trimmer.quality` | `33` | Phred quality offset for `fastx_trimmer` |
| `params.fastx_trimmer.length` | `130` | Truncation length for `fastx_trimmer` |
| `params.star.map_quality` | `20` | Minimum MAPQ for samtools filter after STAR |
| `params.bcftools.max_depth` | `10000` | `--max-depth` for `bcftools mpileup` |
| `params.bcftools.map_quality` | `20` | Minimum mapping quality for BCFtools |
| `params.bcftools.base_quality` | `20` | Minimum base quality for BCFtools |
| `params.red_ml.p_value` | `0.5` | P-value threshold for RED-ML calls |
| `params.jacusa2.pileup_filter` | `"D"` | JACUSA2 `-a` pileup filter option |

---

## FAQ / Troubleshooting

**Q: The dry-run exits 0, but I see 7 `snakemake --lint` warnings. Should I be concerned?**

No. All 7 warnings are known and benign: two are false positives for comment-embedded paths in `rules/wgs.smk`, two flag the config fallback default path in `Snakefile` (not an actual hardcoded workflow path), one is for the exempt `prepare_fastq` localrule, one is for the `add_md_tag`/`bcftools` sentinel log pattern, and one is a style advisory. None indicate a functional defect.

**Q: `multiple_analysis.done` fails with a "file not found" error on one of the JSON databases.**

The downstream scripts require three JSON files in `references.db_path`: `HEK293T_hg38_clean.json`, `REDIportal.json`, `Alu_GRCh38.json`. These are generated by `build_dbrna_editing`, which only runs when `wgs_samples` is configured in `config.yaml`. If `wgs_samples` is absent, the databases must be provided externally before running downstream rules.

**Q: STAR fails with "Genome directory not found".**

`references.star_index` must be an existing pre-built STAR index directory, not a FASTA file. The Morales pipeline does not build the index; it must exist at the configured path before the pipeline runs. The `editing_wgs` pipeline has a `star_genome_generate` rule that can build it.

**Q: Container rule fails with "SIF not found".**

The pipeline does not build SIFs. Run `TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh` to build the four new SIFs, then copy them to `singularity/` (or set `singularity_image_dir` in `config.yaml`).

**Q: `prepare_fastq` hangs on a compute node.**

`prepare_fastq` is a `localrule` — it runs on the head node. For production FASTQs larger than ~1 GB, this can be slow. See the comment at the top of `preprocessing.smk` for how to convert it to a regular rule dispatched via SLURM.

**Q: The downstream scripts reference `/binf-isilon/...` paths.**

Those defaults are in the Benchmark submodule's Python scripts (e.g., `Alu.py`). When called from the pipeline, the scripts read from `DB_PATH` environment variable. The pipeline sets `db_path` in `config.yaml`; the `build_dbrna_editing` rule writes the JSON databases there. Ensure `references.db_path` is set to a writable directory on TSCC.

**Q: How do I run only the preprocessing steps?**

Use Snakemake's `--until` flag:

```bash
snakemake --until mark_duplicates --snakefile Snakefile --configfile config.yaml ...
```
