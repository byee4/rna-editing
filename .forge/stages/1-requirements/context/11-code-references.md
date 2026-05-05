# Code References

## Key File Paths

| File | Absolute Path |
|------|---------------|
| Morales Snakefile | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/Morales_et_all/Snakefile` |
| Morales preprocessing.smk | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/Morales_et_all/preprocessing.smk` |
| Morales tools.smk | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/Morales_et_all/tools.smk` |
| Morales downstream.smk | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/Morales_et_all/downstream.smk` |
| Morales config.yaml | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/Morales_et_all/config.yaml` |
| editing_wgs Snakefile (pattern) | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/editing_wgs/Snakefile` |
| editing_wgs config.yaml (pattern) | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/editing_wgs/config.yaml` |
| editing_wgs rna_editing.smk (rule pattern) | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/pipelines/editing_wgs/rna_editing.smk` |
| picard Dockerfile | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/containers/picard/Dockerfile` |
| picard wrapper | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/containers/picard/picard` |
| picard validate.sh | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/containers/picard/validate.sh` |
| wgs Dockerfile | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/containers/wgs/Dockerfile` |
| jacusa2 Dockerfile | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/containers/jacusa2/Dockerfile` |
| sprint Dockerfile | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/containers/sprint/Dockerfile` |
| TSCC profile | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/profiles/tscc2/config.yaml` |

## Canonical Pattern: container_for() Helper

**Source**: `pipelines/editing_wgs/Snakefile` lines 14-25

```python
SIF_DIR = config.get("singularity_image_dir", "/Volumes/X9Pro/container_data/singularity_images")
CONTAINERS = config.get("containers", {})

def container_for(tool):
    """Return the configured Singularity image path for a workflow tool."""
    return CONTAINERS.get(tool, f"{SIF_DIR}/{tool}.sif")
```

**Copy this exactly** into `pipelines/Morales_et_all/Snakefile`, updating the default path as appropriate.

## Canonical Pattern: Rule with container/log/resources

**Source**: `pipelines/editing_wgs/rna_editing.smk` lines 6-29

```python
rule jacusa2_dnarna:
    input: ...
    output: ...
    threads: config["jacusa2"]["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 33350 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 400 * (2 ** (attempt - 1))
    container: container_for("jacusa2")
    log:
        stdout=WORKDIR + "/logs/{sample}.jacusa2.out",
        stderr=WORKDIR + "/logs/{sample}.jacusa2.err"
    params: ...
    shell:
        "java -jar /opt/jacusa2/jacusa2.jar call-2 ..."
```

## Shell Command Before/After Reference

### mark_duplicates
```bash
# BEFORE:
java -jar {params.picard} INPUT={input.bam} OUTPUT={output.rmdup_bam} \
     METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true

# AFTER:
picard MarkDuplicates INPUT={input.bam} OUTPUT={output.rmdup_bam} \
     METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true
```

### reditools
```bash
# BEFORE:
python {params.script} -S -C -bq 20 -q 20 -f {input.bam} -r {params.ref} -o {output}

# AFTER:
reditools.py -S -C -bq 20 -q 20 -f {input.bam} -r {params.ref} -o {output}
```

### sprint
```bash
# BEFORE:
{params.sprint_bin} -rp {params.rmsk} {input.bam} {params.ref} {output} {params.samtools_bin}

# AFTER:
python /opt/sprint/sprint_from_bam.py -rp {params.rmsk} {input.bam} {params.ref} {output} samtools
```

### red_ml
```bash
# BEFORE:
perl {params.script} --rnabam {input.bam} --reference {params.ref} \
     --dbsnp {params.dbsnp} --simpleRepeat {params.simple_repeat} \
     --alu {params.alu} --outdir {output} -p {params.pval}

# AFTER:
red_ML.pl --rnabam {input.bam} --reference {params.ref} \
     --dbsnp {params.dbsnp} --simpleRepeat {params.simple_repeat} \
     --alu {params.alu} --outdir {output} -p {params.pval}
```

### jacusa2
```bash
# BEFORE:
java -jar {params.jacusa_jar} call-2 -a {params.pileup} -p {threads} -r {output} $wt_list $ko_list

# AFTER:
java -jar /opt/jacusa2/jacusa2.jar call-2 -a {params.pileup} -p {threads} -r {output} $wt_list $ko_list
```

### bcftools (add pipefail)
```bash
# BEFORE:
bcftools mpileup -Ou --max-depth {params.max_depth} -q {params.map_q} -Q {params.base_q} -f {params.ref} {input.bam} | \
bcftools call -mv -O b -o {output}

# AFTER:
set -euo pipefail
bcftools mpileup -Ou --max-depth {params.max_depth} -q {params.map_q} -Q {params.base_q} -f {params.ref} {input.bam} | \
bcftools call -mv -O b -o {output}
```

### downstream rules (example: run_downstream_parsers)
```bash
# BEFORE:
python Downstream/REDItools2.py
python Downstream/SPRINT.py
python Downstream/REDML.py
python Downstream/BCFtools.py
python Downstream/JACUSA2.py

# AFTER:
python {params.downstream_dir}/REDItools2.py
python {params.downstream_dir}/SPRINT.py
python {params.downstream_dir}/REDML.py
python {params.downstream_dir}/BCFtools.py
python {params.downstream_dir}/JACUSA2.py
```

## Container Installation Paths (for shell commands)

| Container | Tool | Path in Container |
|-----------|------|-------------------|
| picard | picard JAR | `/opt/picard/picard.jar` (via `/usr/local/bin/picard` wrapper) |
| jacusa2 | JACUSA2 JAR | `/opt/jacusa2/jacusa2.jar` |
| sprint | sprint_from_bam.py | `/opt/sprint/sprint_from_bam.py` |
| reditools | reditools.py | On PATH (from existing container) |
| wgs | samtools, bcftools | On PATH (apt install) |
| star (new) | STAR, samtools | On PATH |
| red_ml (new) | red_ML.pl | On PATH (at `/opt/red_ml/bin/`) |
| fastx (new) | fastx_trimmer | On PATH |
| morales_downstream (new) | python3, pandas, numpy | On PATH |
