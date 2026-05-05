# Business Logic

## Rule-by-Rule Containerization Specification

### Preprocessing Rules (`preprocessing.smk`)

#### `trim_reads`
- **Container**: `container_for("fastx")`
- **Tool call (before)**: `fastx_trimmer -Q{params.q} -l {params.l} -z -i {input.reads} -o {output}`
- **Tool call (after)**: Same — `fastx_trimmer` will be on PATH in the fastx container
- **Log**: `results/logs/{condition}_{sample}_{read}.trim_reads.out`, `.err`
- **Resources**: `mem_mb=4000, runtime=30`
- **No params changes needed**

#### `star_mapping`
- **Container**: `container_for("star")`
- **Tool call (before)**: `STAR ... ; samtools view ... | samtools sort ...`
- **Tool call (after)**: Same binaries — STAR and samtools will be in the star container
- **Shell safety**: Add `set -euo pipefail` at the top of the shell block (pipe used)
- **Log**: `results/logs/{condition}_{sample}.star_mapping.out`, `.err`
- **Resources**: `mem_mb=32000, runtime=120`

#### `mark_duplicates`
- **Container**: `container_for("picard")`
- **Tool call (before)**: `java -jar {params.picard} INPUT=... OUTPUT=... METRICS_FILE=... REMOVE_DUPLICATES=true`
- **Tool call (after)**: `picard MarkDuplicates INPUT=... OUTPUT=... METRICS_FILE=... REMOVE_DUPLICATES=true`
  - Uses the `/usr/local/bin/picard` wrapper script that calls `exec java -jar /opt/picard/picard.jar "$@"`
- **Params change**: Remove `picard=config["tools"]["picard_jar"]`
- **Log**: `results/logs/{condition}_{sample}.mark_duplicates.out`, `.err`
- **Resources**: `mem_mb=8000, runtime=30`

### Tool Rules (`tools.smk`)

#### `reditools`
- **Container**: `container_for("reditools")`
- **Tool call (before)**: `python {params.script} -S -C -bq 20 -q 20 -f {input.bam} -r {params.ref} -o {output}`
- **Tool call (after)**: `reditools.py -S -C -bq 20 -q 20 -f {input.bam} -r {params.ref} -o {output}`
  - `reditools.py` is on PATH in the reditools container
- **Params change**: Remove `script=config["tools"]["reditools_script"]`
- **Log**: `results/logs/{condition}_{sample}.reditools.out`, `.err`
- **Resources**: `mem_mb=8000, runtime=120`

#### `sprint`
- **Container**: `container_for("sprint")`
- **Tool call (before)**: `{params.sprint_bin} -rp {params.rmsk} {input.bam} {params.ref} {output} {params.samtools_bin}`
- **Tool call (after)**: `python /opt/sprint/sprint_from_bam.py -rp {params.rmsk} {input.bam} {params.ref} {output} samtools`
  - The SPRINT container has SPRINT at `/opt/sprint/` (from `containers/sprint/Dockerfile`)
  - `samtools_bin` positional arg replaced with literal `samtools` (on PATH in sprint container)
- **Params change**: Remove `sprint_bin` and `samtools_bin` params
- **Log**: `results/logs/{condition}_{sample}.sprint.out`, `.err`
- **Resources**: `mem_mb=12000, runtime=240`

#### `bcftools`
- **Container**: `container_for("wgs")`
- **Tool call (before)**: `bcftools mpileup ... | bcftools call ...` (no pipefail)
- **Tool call (after)**: Add `set -euo pipefail` before the pipe; tool calls unchanged
  - `bcftools` is in the `wgs` container
- **Log**: `results/logs/{condition}_{sample}.bcftools.out`, `.err`
- **Resources**: `mem_mb=4000, runtime=60`

#### `red_ml`
- **Container**: `container_for("red_ml")`
- **Tool call (before)**: `perl {params.script} --rnabam ... --outdir {output} -p {params.pval}`
- **Tool call (after)**: `red_ML.pl --rnabam ... --outdir {output} -p {params.pval}`
  - `red_ML.pl` on PATH in the red_ml container
- **Params change**: Remove `script=config["tools"]["red_ml_script"]`
- **Log**: `results/logs/{condition}_{sample}.red_ml.out`, `.err`
- **Resources**: `mem_mb=16000, runtime=120`

#### `add_md_tag`
- **Container**: `container_for("wgs")` (C-005: use wgs, not jacusa2)
- **Tool call (before)**: `samtools calmd {input.bam} {params.ref} > {output.bam}`
- **Tool call (after)**: Same — `samtools` is in the wgs container
- **Log**: `results/logs/{condition}_{sample}.add_md_tag.out`, `.err`
- **Resources**: `mem_mb=4000, runtime=30`

#### `jacusa2`
- **Container**: `container_for("jacusa2")`
- **Tool call (before)**: `java -jar {params.jacusa_jar} call-2 ...`
- **Tool call (after)**: `java -jar /opt/jacusa2/jacusa2.jar call-2 ...`
  - Confirmed path from `containers/jacusa2/Dockerfile`: JAR installed to `/opt/jacusa2/jacusa2.jar`
- **Params change**: Remove `jacusa_jar=config["tools"]["jacusa2_jar"]`
- **Log**: `results/tools/jacusa2/Jacusa.out.log` or `results/logs/jacusa2.out`, `.err`
  - Note: jacusa2 has no wildcards (aggregate rule); log path uses literal name
- **Resources**: `mem_mb=32000, runtime=60`

### Downstream Rules (`downstream.smk`)

All 5 downstream rules use `container_for("morales_downstream")`.

**Shell command change pattern (same for all 5)**:
- **Before**: `python Downstream/REDItools2.py`
- **After**: `python {params.downstream_dir}/REDItools2.py`
- **New params block for each rule**: `params: downstream_dir=config["downstream_scripts_dir"]`

**Rule-specific downstream scripts**:
| Rule | Scripts |
|------|---------|
| `run_downstream_parsers` | REDItools2.py, SPRINT.py, REDML.py, BCFtools.py, JACUSA2.py |
| `update_alu` | Alu.py |
| `individual_analysis` | Individual-Analysis.py |
| `reanalysis_multiple` | Re-Analysis-Multiple.py |
| `multiple_analysis` | Multiple-Analysis.py |

**Log** for downstream rules (no wildcards except multiple_analysis): `results/logs/{rulename}.out`, `.err`
**Resources**: `mem_mb=4000, runtime=60` for each downstream rule

## Config Changes Summary

### Remove from `config.yaml`:
```yaml
tools:  # entire section
  picard_jar: ...
  reditools_script: ...
  sprint_bin: ...
  jacusa2_jar: ...
  red_ml_script: ...
  samtools_bin: ...
```

### Add to `config.yaml`:
```yaml
singularity_image_dir: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity"
containers:
  fastx: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/fastx.sif"
  star: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/star.sif"
  picard: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/picard.sif"
  reditools: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/reditools.sif"
  sprint: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/sprint.sif"
  wgs: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/wgs.sif"
  red_ml: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/red_ml.sif"
  jacusa2: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/jacusa2.sif"
  morales_downstream: "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity/morales_downstream.sif"
downstream_scripts_dir: "Benchmark-of-RNA-Editing-Detection-Tools/Downstream"
# Note: Run 'git submodule update --init' before executing downstream rules
```
