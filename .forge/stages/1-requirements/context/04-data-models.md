# Data Models

## File Types and Naming Conventions

### Input Files
| Pattern | Type | Description |
|---------|------|-------------|
| `data/fastq/{condition}_{sample}_{read}.fastq` | FASTQ | Raw reads; paired-end (R1/R2) |

### Intermediate Files
| Pattern | Type | Description |
|---------|------|-------------|
| `results/trimmed/{condition}_{sample}_{read}_trimmed.fastq.gz` | gzipped FASTQ | After fastx_trimmer |
| `results/mapped/{condition}_{sample}.bam` | BAM | STAR output, filtered and sorted |
| `results/mapped/{condition}_{sample}.bam.bai` | BAI | BAM index |
| `results/mapped/{condition}_{sample}.rmdup.bam` | BAM | After Picard MarkDuplicates |
| `results/mapped/{condition}_{sample}.rmdup_MD.bam` | BAM | After samtools calmd (MD tags added) |
| `results/mapped/{condition}_{sample}.duplication.info` | TSV | Picard duplication metrics |

### Tool Output Files
| Pattern | Type | Description |
|---------|------|-------------|
| `results/tools/reditools/{condition}_{sample}.output` | TSV | REDItools2 editing table |
| `results/tools/sprint/{condition}_{sample}_output` | Directory | SPRINT output directory |
| `results/tools/bcftools/{condition}_{sample}.bcf` | BCF | BCFtools variant calls |
| `results/tools/red_ml/{condition}_{sample}_output` | Directory | RED-ML output directory |
| `results/tools/jacusa2/Jacusa.out` | TSV | JACUSA2 comparison output (single file, all samples) |

### Downstream Sentinel Files
| Pattern | Type | Description |
|---------|------|-------------|
| `results/downstream/parsers.done` | touch file | Signals all 5 parser scripts ran |
| `results/downstream/alu_updated.done` | touch file | Signals Alu.py ran |
| `results/downstream/individual_analysis.done` | touch file | Signals Individual-Analysis.py ran |
| `results/downstream/reanalysis_multiple.done` | touch file | Signals Re-Analysis-Multiple.py ran |
| `results/downstream/multiple_analysis.done` | touch file | Signals Multiple-Analysis.py ran (FINAL target) |

### Log Files (post-task)
| Pattern | Type | Description |
|---------|------|-------------|
| `results/logs/{condition}_{sample}.{rulename}.out` | text | Rule stdout |
| `results/logs/{condition}_{sample}.{rulename}.err` | text | Rule stderr |

## Config Data Model (after this task)

```yaml
# Key additions to config.yaml:
singularity_image_dir: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity"
containers:
  fastx: "{singularity_image_dir}/fastx.sif"
  star: "{singularity_image_dir}/star.sif"
  picard: "{singularity_image_dir}/picard.sif"
  reditools: "{singularity_image_dir}/reditools.sif"
  sprint: "{singularity_image_dir}/sprint.sif"
  wgs: "{singularity_image_dir}/wgs.sif"
  red_ml: "{singularity_image_dir}/red_ml.sif"
  jacusa2: "{singularity_image_dir}/jacusa2.sif"
  morales_downstream: "{singularity_image_dir}/morales_downstream.sif"
downstream_scripts_dir: "Benchmark-of-RNA-Editing-Detection-Tools/Downstream"
# Note: run `git submodule update --init` before executing downstream rules
```

## Wildcard Dimensions

| Wildcard | Values (default) | Source |
|----------|-----------------|--------|
| `{condition}` | WT, ADAR1KO | `config["conditions"]` |
| `{sample}` | clone1, clone2, clone3 | `config["samples"]` |
| `{read}` | R1, R2 | Implicit in FASTQ naming convention |
