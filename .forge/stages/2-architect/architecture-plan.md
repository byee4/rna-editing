# Architecture Plan: Morales_et_al Pipeline — Snakemake 9+ Compliance and Containerization

Stage: 2-architect
Generated: 2026-05-05T22:15:00Z
Pipeline ID: forge-8a8d6b83
Status: READY_FOR_BUILD

This plan operationalizes the requirements package at `.forge/stages/1-requirements/architect-prompt.md`. It evaluates three approaches, selects one, defines exact contracts for every modified file, decomposes the work into 8 ordered tasks with measurable acceptance criteria, and traces every requirement to a concrete task.

## 1. Problem Statement

The `pipelines/Morales_et_all/` Snakemake pipeline currently violates four invariants enforced everywhere else in this repository:

1. **No `container:` directives** on any of its 14 rules, so Snakemake 9 with `software-deployment-method: apptainer` cannot dispatch the rules into the correct images. Tools resolve from the host SLURM environment, not from a versioned, reproducible SIF.
2. **No `log:` directives**, so SLURM stderr is the only sink for tool diagnostics. Rule failures are hard to triage on TSCC.
3. **No `resources:` directives**, so the TSCC profile defaults (`mem_mb=20000`, `runtime=30`) are applied to every rule including `star_mapping` (needs 32 GB) and `jacusa2` (also needs 32 GB). Default-resourced rules will OOM.
4. **User-specific tool paths** (`~/bin/picard-tools/MarkDuplicates.jar`, `~/bin/SPRINT/bin/sprint_from_bam`, `/binf-isilon/...`). These break for any user other than the original author and are non-reproducible.

In addition, the `downstream.smk` rules invoke `python Downstream/REDItools2.py` with a bare relative path that resolves to an empty git submodule, so dry-run succeeds but execution fails silently.

## 2. Goals and Non-Goals

### Goals (in scope)
- All 14 rules across `preprocessing.smk`, `tools.smk`, and `downstream.smk` gain `container:`, `log:`, and `resources:` directives.
- All `~/bin/`, `/binf-isilon/`, and other user/cluster-specific paths are removed from `pipelines/Morales_et_all/`.
- `Snakefile` gains the `container_for()` helper and globals from `editing_wgs/Snakefile`.
- `config.yaml` gains a `singularity_image_dir:` key, a `containers:` block, and a `downstream_scripts_dir:` key. The `tools:` section is deleted.
- Four new container build contexts are created: `containers/star/`, `containers/red_ml/`, `containers/fastx/`, `containers/morales_downstream/`. Each ships a `Dockerfile` and a `validate.sh`.
- `snakemake --lint` passes with 0 errors and `snakemake -n` (dry-run) passes with 0 errors.

### Non-Goals (out of scope, do not perform)
- Any modification to `pipelines/editing_wgs/`.
- Any modification to existing containers `picard`, `reditools`, `sprint`, `wgs`, `jacusa2`.
- Building or pushing SIF files (this is a post-commit human step running `scripts/validate_containers.sh`).
- Initializing or populating the `Benchmark-of-RNA-Editing-Detection-Tools/` submodule.
- Running the pipeline on real data.
- Adding alignment options beyond STAR (the unused `aligners:` config keys `bwa`/`hisat2` are preserved but no rules are added).

## 3. Approaches Evaluated

### Approach A: Direct Retrofit (selected)

Apply the changes in-place rule-by-rule, mirroring the `editing_wgs/Snakefile` pattern exactly. The `container_for()` helper, log/resource lambdas, and SIF naming convention are copied verbatim. Each new Dockerfile is a thin, single-tool image that follows the existing `containers/picard/Dockerfile` skeleton (FROM, LABEL, install, validate.sh, WORKDIR /work).

**Pros**:
- Zero conceptual divergence from editing_wgs. New maintainers see one pattern, applied twice.
- Smallest possible change surface — every diff is mechanical and reviewable.
- New Dockerfiles are independently buildable by `scripts/validate_containers.sh` (which already enumerates `containers/*/`).
- Rollback is trivial: `git revert` on the architect's commit.
- Preserves the existing `aligners:` config key for forward compatibility.

**Cons**:
- Does not factor common header logic into a shared Python module — each Snakefile re-declares `container_for()`. Acceptable: the helper is 10 lines and only two pipelines exist.
- `mark_duplicates` switches from `java -jar` to the `picard` wrapper, which is a behavioral change that depends on the wrapper being on PATH inside the picard SIF. Mitigation: the wrapper is verified at line 17 of `containers/picard/Dockerfile`.
- Each new Dockerfile is built and validated separately by the human running `validate_containers.sh`; no orchestration of cross-image dependencies.

### Approach B: Shared Workflow Module

Extract `container_for()`, `SIF_DIR`, `CONTAINERS`, and the resource lambdas into a `pipelines/_common/snakemake_helpers.smk` (or a Python module under `pipelines/_common/`) included by both `editing_wgs/Snakefile` and `Morales_et_all/Snakefile`. Both pipelines lose ~12 lines each.

**Pros**:
- DRY: a single source of truth for container resolution.
- Future pipelines get the helpers for free.

**Cons**:
- Modifies `pipelines/editing_wgs/Snakefile` (the include line and removed copy of helpers), which is explicitly out of scope per requirements §5.4 ("Existing containers ... must not be modified" extended to canonical patterns by the no-change list). Even a one-line `include:` change in editing_wgs would fail review under FM-01 (scope expansion).
- Adds a new directory `pipelines/_common/` whose lifecycle and CI ownership are undefined.
- The win is small (10-line helper) versus the cost of cross-pipeline coupling.

**Verdict**: Rejected. Violates the explicit out-of-scope rule.

### Approach C: Snakemake Wrapper Library

Use Snakemake's `wrapper:` directive to call community-maintained wrappers (e.g., `bio/picard/markduplicates`, `bio/star/align`) from snakemake-wrappers. This eliminates all custom container build contexts for the standard tools (picard, star, samtools, bcftools, jacusa2) and dramatically shortens each rule.

**Pros**:
- Fewer Dockerfiles to maintain (zero for picard, star, jacusa2, bcftools).
- Wrapper-managed conda environments handle tool installation and updates.
- Aligns with one common Snakemake idiom.

**Cons**:
- The TSCC profile uses `software-deployment-method: apptainer` (not conda alone). Wrapper resolution would require either falling back to conda envs, or pulling each wrapper's prebuilt biocontainer dynamically, which conflicts with the existing apptainer SIF discipline used by editing_wgs.
- Requires building four new Dockerfiles anyway for `red_ml`, `fastx`, `morales_downstream`, and the rare combination of `red_ml` plus host PATH dependencies — the savings are smaller than they appear.
- `sprint`, `red_ml`, and `morales_downstream` have no community wrappers; wrappers cannot be applied uniformly across all 14 rules.
- Diverges architecturally from editing_wgs, fragmenting the pipeline-style policy.
- `wrapper:` and `container:` interact nontrivially; mixing them in the same pipeline complicates the apptainer caching story on TSCC.

**Verdict**: Rejected. Inconsistent with the existing repo policy and incomplete coverage of the 14 rules.

### Selection

**Chosen: Approach A (Direct Retrofit).** It minimizes risk, matches the in-repo convention enforced by editing_wgs, requires no out-of-scope changes, and produces deterministic, mechanically verifiable diffs. Approach B is the strictly correct DRY answer for a future refactor but requires touching editing_wgs which is out of scope for this task.

## 4. High-Level Design

### 4.1 Component Map

```
pipelines/Morales_et_all/                 [MODIFY]
  Snakefile          -> add SIF_DIR, CONTAINERS, container_for() (mirrors editing_wgs lines 14-25)
  preprocessing.smk  -> add container/log/resources to 3 rules; rewrite mark_duplicates shell
  tools.smk          -> add container/log/resources to 6 rules; rewrite reditools, sprint, red_ml,
                        jacusa2 shells; add set -euo pipefail to bcftools and star_mapping
  downstream.smk     -> add container/log/resources to 5 rules; replace bare 'python Downstream/'
                        with 'python {params.downstream_dir}/'
  config.yaml        -> add singularity_image_dir, containers block, downstream_scripts_dir;
                        delete tools: section

containers/                              [CREATE 4 new]
  star/Dockerfile, star/validate.sh
  red_ml/Dockerfile, red_ml/validate.sh
  fastx/Dockerfile, fastx/validate.sh
  morales_downstream/Dockerfile, morales_downstream/validate.sh

profiles/tscc2/config.yaml               [READ-ONLY] (already correct)
pipelines/editing_wgs/*                  [READ-ONLY] (out of scope)
containers/{picard,reditools,sprint,wgs,jacusa2}/  [READ-ONLY] (existing, reused)
```

### 4.2 Container-to-Rule Assignment Matrix

| Rule | File | Container Key | SIF Source | Tool Invocation |
|------|------|---------------|------------|-----------------|
| `trim_reads` | preprocessing.smk | `fastx` | NEW `fastx.sif` | `fastx_trimmer` (PATH) |
| `star_mapping` | preprocessing.smk | `star` | NEW `star.sif` | `STAR`, `samtools` (PATH) |
| `mark_duplicates` | preprocessing.smk | `picard` | EXISTING `picard.sif` | `picard MarkDuplicates` (wrapper at `/usr/local/bin/picard`) |
| `reditools` | tools.smk | `reditools` | EXISTING `reditools.sif` | `reditools.py` (PATH; resolves to `/opt/reditools2/src/cineca/reditools.py`) |
| `sprint` | tools.smk | `sprint` | EXISTING `sprint.sif` | `python /opt/sprint/sprint_from_bam.py` |
| `bcftools` | tools.smk | `wgs` | EXISTING `wgs.sif` | `bcftools mpileup`, `bcftools call` (PATH) |
| `red_ml` | tools.smk | `red_ml` | NEW `red_ml.sif` | `red_ML.pl` (PATH at `/opt/red_ml/bin/`) |
| `add_md_tag` | tools.smk | `wgs` | EXISTING `wgs.sif` | `samtools calmd` (PATH) |
| `jacusa2` | tools.smk | `jacusa2` | EXISTING `jacusa2.sif` | `java -jar /opt/jacusa2/jacusa2.jar call-2` |
| `run_downstream_parsers` | downstream.smk | `morales_downstream` | NEW `morales_downstream.sif` | `python {params.downstream_dir}/REDItools2.py` (etc., 5 scripts) |
| `update_alu` | downstream.smk | `morales_downstream` | NEW `morales_downstream.sif` | `python {params.downstream_dir}/Alu.py` |
| `individual_analysis` | downstream.smk | `morales_downstream` | NEW `morales_downstream.sif` | `python {params.downstream_dir}/Individual-Analysis.py` |
| `reanalysis_multiple` | downstream.smk | `morales_downstream` | NEW `morales_downstream.sif` | `python {params.downstream_dir}/Re-Analysis-Multiple.py` |
| `multiple_analysis` | downstream.smk | `morales_downstream` | NEW `morales_downstream.sif` | `python {params.downstream_dir}/Multiple-Analysis.py` |

Total: 14 rules. 9 unique `containers:` keys (5 reused + 4 new).

### 4.3 Trust Boundaries

```
[Host filesystem (TSCC bind mounts)]
    /tscc/projects/, /tscc/nfs/home/, /cm, /etc/passwd
                  |
                  | apptainer --bind (read+write where allowed)
                  v
[Apptainer container] (one per rule invocation)
    /work (WORKDIR; rule cwd is bind-mounted to pipeline dir)
    /opt/<tool>/ (read-only tool installation)
    /usr/local/bin/<tool> (read-only wrapper scripts)
                  |
                  | tool reads input files, writes outputs to bind-mounted host dir
                  v
[SLURM job sandbox]
    Captures stdout/stderr to {log.stdout}, {log.stderr}
```

There is one trust boundary per rule: the host -> container mount surface. The threat model in `threat-model.md` enumerates STRIDE concerns at this boundary.

### 4.4 Data Flow (unchanged from current pipeline; only directives added)

```
data/fastq/{condition}_{sample}_{R1,R2}.fastq
  -> trim_reads (fastx)
  -> results/trimmed/{condition}_{sample}_{R1,R2}_trimmed.fastq.gz
  -> star_mapping (star)
  -> results/mapped/{condition}_{sample}.bam[.bai]
  -> mark_duplicates (picard)
  -> results/mapped/{condition}_{sample}.rmdup.bam, .duplication.info
  -> {reditools, sprint, bcftools, red_ml} (per-sample, parallel)
  -> add_md_tag (wgs)
  -> results/mapped/{condition}_{sample}.rmdup_MD.bam
  -> jacusa2 (jacusa2; aggregates all WT and ADAR1KO BAMs)
  -> results/tools/jacusa2/Jacusa.out
  -> run_downstream_parsers (morales_downstream)
  -> update_alu -> individual_analysis -> reanalysis_multiple -> multiple_analysis
  -> results/downstream/multiple_analysis.done (FINAL target)
```

## 5. Detailed Contracts

### 5.1 `pipelines/Morales_et_all/Snakefile` — exact additions

After line 1 (`import os`) add line 2: `import re` (unused for now but kept for parity with editing_wgs).

After the `configfile: "config.yaml"` line, insert (before any `include:`):

```python
SIF_DIR = config.get("singularity_image_dir", "/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity")
CONTAINERS = config.get("containers", {})


def container_for(tool):
    """Return the configured Singularity image path for a workflow tool."""
    return CONTAINERS.get(tool, f"{SIF_DIR}/{tool}.sif")
```

The `rule all:` block and `include:` lines remain unchanged.

### 5.2 `pipelines/Morales_et_all/config.yaml` — exact diff

**Delete** the entire block (lines 36-43):

```yaml
# ==========================================
# Tool Executables & Scripts
# ==========================================
tools:
  picard_jar: "~/bin/picard-tools/MarkDuplicates.jar"
  reditools_script: "~/bin/reditools2.0-master/src/cineca/reditools.py"
  sprint_bin: "~/bin/SPRINT/bin/sprint_from_bam"
  jacusa2_jar: "/binf-isilon/rennie/gsn480/scratch/bin/JACUSA_v2.0.2-RC.jar"
  red_ml_script: "~/bin/RED-ML/bin/red_ML.pl"
  samtools_bin: "~/bin/samtools"
```

**Insert** after the `references:` block (before the `params:` block):

```yaml
# ==========================================
# Container Images (Apptainer/Singularity)
# ==========================================
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

# Path to the Benchmark-of-RNA-Editing-Detection-Tools/Downstream directory.
# IMPORTANT: This is an empty git submodule by default. Run the following before
# executing downstream rules:
#   git submodule update --init Benchmark-of-RNA-Editing-Detection-Tools
downstream_scripts_dir: "Benchmark-of-RNA-Editing-Detection-Tools/Downstream"
```

`threads:`, `conditions:`, `samples:`, `aligners:`, `references:`, and `params:` blocks are unchanged.

### 5.3 `pipelines/Morales_et_all/preprocessing.smk` — full rewritten contract

```python
rule trim_reads:
    input:
        reads="data/fastq/{condition}_{sample}_{read}.fastq"
    output:
        "results/trimmed/{condition}_{sample}_{read}_trimmed.fastq.gz"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("fastx")
    log:
        stdout="results/logs/{condition}_{sample}_{read}.trim_reads.out",
        stderr="results/logs/{condition}_{sample}_{read}.trim_reads.err"
    params:
        q=config["params"]["fastx_trimmer"]["quality"],
        l=config["params"]["fastx_trimmer"]["length"]
    shell:
        r"""
        set -euo pipefail
        fastx_trimmer -Q{params.q} -l {params.l} -z -i {input.reads} -o {output} \
            1> {log.stdout} 2> {log.stderr}
        """


rule star_mapping:
    input:
        r1="results/trimmed/{condition}_{sample}_R1_trimmed.fastq.gz",
        r2="results/trimmed/{condition}_{sample}_R2_trimmed.fastq.gz"
    output:
        bam="results/mapped/{condition}_{sample}.bam",
        bai="results/mapped/{condition}_{sample}.bam.bai"
    threads: config["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("star")
    log:
        stdout="results/logs/{condition}_{sample}.star_mapping.out",
        stderr="results/logs/{condition}_{sample}.star_mapping.err"
    params:
        ref_dir=config["references"]["star_index"],
        prefix="results/mapped/{condition}_{sample}_",
        map_qual=config["params"]["star"]["map_quality"]
    shell:
        r"""
        set -euo pipefail
        STAR --runThreadN {threads} --genomeDir {params.ref_dir} \
             --readFilesIn {input.r1} {input.r2} --readFilesCommand zcat \
             --outSAMtype BAM SortedByCoordinate --outFileNamePrefix {params.prefix} \
             1> {log.stdout} 2> {log.stderr}
        samtools view -@ {threads} -F 0x04 -f 0x2 -q {params.map_qual} -b {params.prefix}Aligned.sortedByCoord.out.bam | \
            samtools sort -@ {threads} -T {params.prefix}tmp -o {output.bam} 2>> {log.stderr}
        samtools index -@ {threads} {output.bam} 2>> {log.stderr}
        rm {params.prefix}Aligned.sortedByCoord.out.bam
        """


rule mark_duplicates:
    input:
        bam="results/mapped/{condition}_{sample}.bam"
    output:
        rmdup_bam="results/mapped/{condition}_{sample}.rmdup.bam",
        metrics="results/mapped/{condition}_{sample}.duplication.info"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("picard")
    log:
        stdout="results/logs/{condition}_{sample}.mark_duplicates.out",
        stderr="results/logs/{condition}_{sample}.mark_duplicates.err"
    shell:
        r"""
        set -euo pipefail
        picard MarkDuplicates INPUT={input.bam} OUTPUT={output.rmdup_bam} \
             METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true \
             1> {log.stdout} 2> {log.stderr}
        """
```

Notes:
- `params.picard` is removed; `picard MarkDuplicates` calls the wrapper at `/usr/local/bin/picard` inside the picard SIF.
- `set -euo pipefail` is added to all three rules (FR-7 for bcftools is the floor; G-2 closure adds it to star_mapping; trim_reads and mark_duplicates inherit the convention for consistency).

### 5.4 `pipelines/Morales_et_all/tools.smk` — full rewritten contract

```python
rule reditools:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        "results/tools/reditools/{condition}_{sample}.output"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("reditools")
    log:
        stdout="results/logs/{condition}_{sample}.reditools.out",
        stderr="results/logs/{condition}_{sample}.reditools.err"
    params:
        ref=config["references"]["fasta"]
    shell:
        r"""
        set -euo pipefail
        reditools.py -S -C -bq 20 -q 20 -f {input.bam} -r {params.ref} -o {output} \
            1> {log.stdout} 2> {log.stderr}
        """


rule sprint:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        "results/tools/sprint/{condition}_{sample}_output"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 12000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 240 * (2 ** (attempt - 1))
    container: container_for("sprint")
    log:
        stdout="results/logs/{condition}_{sample}.sprint.out",
        stderr="results/logs/{condition}_{sample}.sprint.err"
    params:
        ref=config["references"]["fasta"],
        rmsk=config["references"]["rmsk"]
    shell:
        r"""
        set -euo pipefail
        python /opt/sprint/sprint_from_bam.py -rp {params.rmsk} {input.bam} {params.ref} {output} samtools \
            1> {log.stdout} 2> {log.stderr}
        """


rule bcftools:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        "results/tools/bcftools/{condition}_{sample}.bcf"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{condition}_{sample}.bcftools.out",
        stderr="results/logs/{condition}_{sample}.bcftools.err"
    params:
        ref=config["references"]["fasta"],
        max_depth=config["params"]["bcftools"]["max_depth"],
        map_q=config["params"]["bcftools"]["map_quality"],
        base_q=config["params"]["bcftools"]["base_quality"]
    shell:
        r"""
        set -euo pipefail
        bcftools mpileup -Ou --max-depth {params.max_depth} -q {params.map_q} -Q {params.base_q} -f {params.ref} {input.bam} 2> {log.stderr} | \
            bcftools call -mv -O b -o {output} 2>> {log.stderr}
        echo "bcftools done" > {log.stdout}
        """


rule red_ml:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        directory("results/tools/red_ml/{condition}_{sample}_output")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("red_ml")
    log:
        stdout="results/logs/{condition}_{sample}.red_ml.out",
        stderr="results/logs/{condition}_{sample}.red_ml.err"
    params:
        ref=config["references"]["fasta"],
        dbsnp=config["references"]["dbsnp"],
        simple_repeat=config["references"]["simple_repeat"],
        alu=config["references"]["alu_bed"],
        pval=config["params"]["red_ml"]["p_value"]
    shell:
        r"""
        set -euo pipefail
        red_ML.pl --rnabam {input.bam} --reference {params.ref} \
             --dbsnp {params.dbsnp} --simpleRepeat {params.simple_repeat} \
             --alu {params.alu} --outdir {output} -p {params.pval} \
             1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------
# JACUSA2 Aggregate Rules
# ---------------------------------------------------------
rule add_md_tag:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        bam="results/mapped/{condition}_{sample}.rmdup_MD.bam"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{condition}_{sample}.add_md_tag.out",
        stderr="results/logs/{condition}_{sample}.add_md_tag.err"
    params:
        ref=config["references"]["fasta"]
    shell:
        r"""
        set -euo pipefail
        samtools calmd {input.bam} {params.ref} > {output.bam} 2> {log.stderr}
        echo "add_md_tag done" > {log.stdout}
        """


rule jacusa2:
    input:
        wt_bams=expand("results/mapped/WT_{sample}.rmdup_MD.bam", sample=config["samples"]),
        ko_bams=expand("results/mapped/ADAR1KO_{sample}.rmdup_MD.bam", sample=config["samples"])
    output:
        "results/tools/jacusa2/Jacusa.out"
    threads: 5
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("jacusa2")
    log:
        stdout="results/logs/jacusa2.out",
        stderr="results/logs/jacusa2.err"
    params:
        pileup=config["params"]["jacusa2"]["pileup_filter"]
    shell:
        r"""
        set -euo pipefail
        wt_list=$(echo {input.wt_bams} | tr ' ' ',')
        ko_list=$(echo {input.ko_bams} | tr ' ' ',')
        java -jar /opt/jacusa2/jacusa2.jar call-2 -a {params.pileup} -p {threads} -r {output} $wt_list $ko_list \
            1> {log.stdout} 2> {log.stderr}
        """
```

Notes:
- `params.script`, `params.sprint_bin`, `params.jacusa_jar`, `params.samtools_bin` are all removed (FR-9..FR-12). AC-9 verifies their absence.
- `bcftools` shell starts with `set -euo pipefail` (FR-7, AC-7).
- `add_md_tag` uses `container_for("wgs")` (C-005, FR-20, AC-17).
- `jacusa2` log paths are literal (no wildcards) per EC-5.
- `bcftools` and `add_md_tag` use a redirect pattern that writes to `{output}` directly; we route stderr to `{log.stderr}` and write a sentinel string to `{log.stdout}` to satisfy the `log:` directive (Snakemake requires that named log handles be written to). This is preferred over `2>&1 | tee` to avoid corrupting the BCF/BAM stream.

### 5.5 `pipelines/Morales_et_all/downstream.smk` — full rewritten contract

```python
rule run_downstream_parsers:
    input:
        reditools=expand("results/tools/reditools/{condition}_{sample}.output", condition=config["conditions"], sample=config["samples"]),
        sprint=expand("results/tools/sprint/{condition}_{sample}_output", condition=config["conditions"], sample=config["samples"]),
        redml=expand("results/tools/red_ml/{condition}_{sample}_output", condition=config["conditions"], sample=config["samples"]),
        bcftools=expand("results/tools/bcftools/{condition}_{sample}.bcf", condition=config["conditions"], sample=config["samples"]),
        jacusa="results/tools/jacusa2/Jacusa.out"
    output:
        touch("results/downstream/parsers.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/run_downstream_parsers.out",
        stderr="results/logs/run_downstream_parsers.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        python {params.downstream_dir}/REDItools2.py 1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/SPRINT.py    1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/REDML.py     1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/BCFtools.py  1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/JACUSA2.py   1>> {log.stdout} 2>> {log.stderr}
        """


rule update_alu:
    input:
        "results/downstream/parsers.done"
    output:
        touch("results/downstream/alu_updated.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/update_alu.out",
        stderr="results/logs/update_alu.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        python {params.downstream_dir}/Alu.py 1> {log.stdout} 2> {log.stderr}
        """


rule individual_analysis:
    input:
        "results/downstream/alu_updated.done"
    output:
        touch("results/downstream/individual_analysis.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/individual_analysis.out",
        stderr="results/logs/individual_analysis.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        python {params.downstream_dir}/Individual-Analysis.py 1> {log.stdout} 2> {log.stderr}
        """


rule reanalysis_multiple:
    input:
        "results/downstream/individual_analysis.done"
    output:
        touch("results/downstream/reanalysis_multiple.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/reanalysis_multiple.out",
        stderr="results/logs/reanalysis_multiple.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        python {params.downstream_dir}/Re-Analysis-Multiple.py 1> {log.stdout} 2> {log.stderr}
        """


rule multiple_analysis:
    input:
        "results/downstream/reanalysis_multiple.done"
    output:
        touch("results/downstream/multiple_analysis.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/multiple_analysis.out",
        stderr="results/logs/multiple_analysis.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        python {params.downstream_dir}/Multiple-Analysis.py 1> {log.stdout} 2> {log.stderr}
        """
```

Notes:
- All 5 rules use `container_for("morales_downstream")`.
- `params.downstream_dir` is local to each rule (per A-9).
- Log paths use literal rule names (no wildcards) per EC-6.
- All `python Downstream/...` references are replaced with `python {params.downstream_dir}/...` (FR-13, AC-10).

### 5.6 New Dockerfiles — exact contracts

#### `containers/star/Dockerfile`

```dockerfile
FROM ubuntu:22.04

LABEL org.opencontainers.image.title="STAR + SAMtools"
LABEL org.opencontainers.image.description="STAR 2.7.x aligner and SAMtools for RNA-seq alignment in the Morales_et_al pipeline."

ENV DEBIAN_FRONTEND=noninteractive \
    STAR_VERSION=2.7.11a \
    PATH="/opt/star/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        samtools \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/star/bin \
    && wget -qO /tmp/star.tar.gz "https://github.com/alexdobin/STAR/archive/refs/tags/${STAR_VERSION}.tar.gz" \
    && tar -xzf /tmp/star.tar.gz -C /tmp \
    && cp "/tmp/STAR-${STAR_VERSION}/bin/Linux_x86_64_static/STAR" /opt/star/bin/STAR \
    && chmod +x /opt/star/bin/STAR \
    && rm -rf /tmp/star.tar.gz "/tmp/STAR-${STAR_VERSION}"

COPY validate.sh /usr/local/bin/validate-star
RUN chmod +x /usr/local/bin/validate-star

WORKDIR /work
CMD ["validate-star"]
```

#### `containers/star/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

STAR --version
samtools --version | head -n 1
echo "STAR validation passed"
```

#### `containers/red_ml/Dockerfile`

```dockerfile
FROM rocker/r-ver:4.3.2

LABEL org.opencontainers.image.title="RED-ML"
LABEL org.opencontainers.image.description="Perl + R + RED-ML (red_ML.pl) for RNA editing detection by machine learning. Reference: BGI-shenzhen/RED-ML."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/red_ml/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        perl \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages (RED-ML uses caret + randomForest + ROCR + data.table)
RUN Rscript -e 'install.packages(c("caret","data.table","ROCR","randomForest","e1071"), repos="https://cloud.r-project.org/", Ncpus=2)'

# Clone RED-ML and place red_ML.pl on PATH
RUN git clone --depth 1 https://github.com/BGI-shenzhen/RED-ML.git /opt/red_ml \
    && test -f /opt/red_ml/bin/red_ML.pl \
    && chmod +x /opt/red_ml/bin/red_ML.pl

COPY validate.sh /usr/local/bin/validate-red_ml
RUN chmod +x /usr/local/bin/validate-red_ml

WORKDIR /work
CMD ["validate-red_ml"]
```

#### `containers/red_ml/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

perl --version | head -n 2
Rscript --version
test -f /opt/red_ml/bin/red_ML.pl
red_ML.pl 2>&1 | head -n 5 || true
Rscript -e 'library(caret); library(data.table); library(ROCR); library(randomForest); cat("R packages OK\n")'
echo "RED-ML validation passed"
```

#### `containers/fastx/Dockerfile`

```dockerfile
FROM condaforge/miniforge3:latest

LABEL org.opencontainers.image.title="FASTX-Toolkit"
LABEL org.opencontainers.image.description="FASTX-Toolkit (fastx_trimmer) installed via bioconda for FASTQ quality trimming in the Morales_et_al pipeline."

ENV PATH="/opt/conda/bin:${PATH}"

RUN mamba install -y -n base -c conda-forge -c bioconda \
        fastx_toolkit \
    && mamba clean -a -y

COPY validate.sh /usr/local/bin/validate-fastx
RUN chmod +x /usr/local/bin/validate-fastx

WORKDIR /work
CMD ["validate-fastx"]
```

#### `containers/fastx/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# fastx_trimmer prints usage to stderr and exits non-zero with no args, so use -h
fastx_trimmer -h 2>&1 | head -n 5 || true
command -v fastx_trimmer
echo "FASTX-Toolkit validation passed"
```

#### `containers/morales_downstream/Dockerfile`

```dockerfile
FROM python:3.11-slim

LABEL org.opencontainers.image.title="Morales Downstream Analysis"
LABEL org.opencontainers.image.description="Python 3.11 with pandas and numpy for the Benchmark-of-RNA-Editing-Detection-Tools/Downstream/*.py scripts called from the Morales_et_al pipeline."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir \
        "numpy>=1.24,<2.0" \
        "pandas>=2.0,<3.0" \
        "scipy>=1.10,<2.0"

COPY validate.sh /usr/local/bin/validate-morales_downstream
RUN chmod +x /usr/local/bin/validate-morales_downstream

WORKDIR /work
CMD ["validate-morales_downstream"]
```

#### `containers/morales_downstream/validate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

python3 --version
python3 -c 'import pandas, numpy, scipy; print("pandas", pandas.__version__); print("numpy", numpy.__version__); print("scipy", scipy.__version__)'
echo "Morales downstream validation passed"
```

### 5.7 Directive Counts (verification)

- `container:` directives: 3 (preprocessing) + 6 (tools) + 5 (downstream) = 14. AC-4 expects 14.
- `log:` directives: 14 (each rule has one `log:` block). AC-5 expects 14.
- `resources:` directives: 14. AC-6 expects 14.
- `params.script | params.sprint_bin | params.jacusa_jar | params.samtools_bin`: 0 occurrences. AC-9.
- `~/bin\|/binf-isilon`: 0 occurrences in any pipeline file or config. AC-3.
- `python Downstream/`: 0 occurrences. AC-10.
- `java -jar` in preprocessing.smk: 0. AC-8.

## 6. Decision Register

| ID | Decision | Choice | Alternatives | Rationale | Trace |
|----|----------|--------|--------------|-----------|-------|
| D-1 | STAR base image | `ubuntu:22.04` + apt samtools + STAR static binary from upstream release tarball | (a) `condaforge/miniforge3` + bioconda STAR; (b) reuse `lodei.sif` | apt + static binary is leanest; bioconda adds ~200 MB conda env; lodei is an accidental dependency (C-002) | ADR-01 |
| D-2 | RED-ML base image | `rocker/r-ver:4.3.2` + apt perl + CRAN R packages | (a) miniforge3 + bioconda r-base; (b) ubuntu:22.04 + apt r-base | rocker/r-ver pins R version reproducibly; CRAN snapshot via Posit Public Package Manager option; ubuntu apt r-base lags | ADR-02 |
| D-3 | FASTX base image | `condaforge/miniforge3` + bioconda fastx_toolkit | (a) ubuntu:20.04 + compile from source; (b) `quay.io/biocontainers/fastx_toolkit` | bioconda is the path of least resistance and matches the `jacusa2` container's pattern | ADR-03 |
| D-4 | SPRINT shell call | `python /opt/sprint/sprint_from_bam.py ... samtools` | (a) `sprint_from_bam` on PATH; (b) keep `params.sprint_bin` | Path is verified in `containers/sprint/Dockerfile`; `samtools` is on PATH in the sprint container | FR-10, code-references.md |
| D-5 | Log path style | Two-handle pattern: `log: stdout=..., stderr=...` with explicit shell redirects | (a) single combined `log:` field; (b) Snakemake-default per-rule auto-log | Two-handle matches editing_wgs convention exactly; eases triage | ADR-04 |
| D-6 | Resource directive style | `lambda wildcards, attempt: BASE * (1.5 ** (attempt-1))` for mem_mb; `* (2 ** (attempt-1))` for runtime | Static integer values | Matches editing_wgs; gives Snakemake retry-on-OOM headroom; A-7 acceptance | NFR-5 |
| D-7 | `add_md_tag` container | `container_for("wgs")` | `container_for("jacusa2")` | C-005 resolution; avoids pulling jacusa2's mamba overhead for a `samtools calmd` call | FR-20, AC-17 |
| D-8 | `bcftools` and `add_md_tag` log handles | Stderr redirected via `2>`; stdout file written with sentinel `echo "<rule> done"` | (a) `2>&1 | tee {log}`; (b) `> {output} 2> {log.stderr}` only with no stdout log | These rules write the primary output via `>` redirect to `{output}`; we cannot route both `{output}` and `{log.stdout}` to stdout. Sentinel write satisfies Snakemake's named-handle requirement | EC-4 |
| D-9 | Downstream `params.downstream_dir` scoping | Local `params:` block on each downstream rule | Global var in Snakefile | Per A-9; minimizes Snakefile header churn; keeps locality | A-9 |
| D-10 | Empty submodule handling | Comment in `config.yaml` directing user to `git submodule update --init` | Snakemake `checkpoints` to validate; runtime guard rule | EC-1 mitigation; checkpoints add complexity for low value | EC-1 |
| D-11 | New SIF naming | `<key>.sif` matching `containers:` config keys (`star.sif`, `red_ml.sif`, `fastx.sif`, `morales_downstream.sif`) | Free-form names | `container_for()` falls back to `{SIF_DIR}/{tool}.sif`; alignment is mandatory | FR-2, technical-constraints.md |
| D-12 | Task decomposition | 8 tasks, sequential 1-5 (Snakefile/config/smk files) and parallel 6-8 (Dockerfiles) | Single bulk-edit task | Aligns with handoff next_stage_context; lets Dockerfile work happen in parallel; smaller tasks = smaller diff per review | handoff.json |

## 7. Task Decomposition (manifest)

Tasks live in `tasks/task-NN-<slug>.md`. Numbers indicate execution order; `(parallel)` indicates a task may start as soon as its DEPENDENCIES list is satisfied.

| # | Task | File | Depends On | Verifies |
|---|------|------|-----------|----------|
| 01 | Add container_for helper to Snakefile | `task-01-snakefile-helper.md` | (none) | AC-16 |
| 02 | Update config.yaml: containers block, downstream_scripts_dir, remove tools | `task-02-config-yaml.md` | 01 | AC-3, AC-11 |
| 03 | Containerize preprocessing.smk (3 rules) | `task-03-preprocessing-smk.md` | 02 | AC-4 (3/14), AC-5 (3/14), AC-6 (3/14), AC-8 |
| 04 | Containerize tools.smk (6 rules) | `task-04-tools-smk.md` | 02 | AC-4 (9/14), AC-5 (9/14), AC-6 (9/14), AC-7, AC-9, AC-17 |
| 05 | Containerize downstream.smk (5 rules) | `task-05-downstream-smk.md` | 02 | AC-4 (14/14), AC-5 (14/14), AC-6 (14/14), AC-10 |
| 06 | Create containers/star/ Dockerfile + validate.sh | `task-06-container-star.md` | (none, parallel) | AC-12 |
| 07 | Create containers/red_ml/ Dockerfile + validate.sh | `task-07-container-red_ml.md` | (none, parallel) | AC-13 |
| 08 | Create containers/fastx/ + containers/morales_downstream/ Dockerfiles | `task-08-containers-fastx-and-downstream.md` | (none, parallel) | AC-14, AC-15 |

End-of-pipeline verification (covered in `implementer-prompt.md` Verification Plan): AC-1 (lint), AC-2 (dry-run).

## 8. Requirements Coverage Matrix

Every FR/NFR/SEC/AC traces to at least one task:

| Requirement | Task(s) | AC(s) Covered |
|-------------|---------|---------------|
| FR-1 (container_for + globals) | 01 | AC-1, AC-16 |
| FR-2 (containers block) | 02 | AC-2 |
| FR-3 (remove tools section) | 02 | AC-3 |
| FR-4 (container: per rule) | 03, 04, 05 | AC-4 |
| FR-5 (log: per rule) | 03, 04, 05 | AC-5 |
| FR-6 (resources: per rule) | 03, 04, 05 | AC-6 |
| FR-7 (set -euo pipefail in bcftools) | 04 | AC-7 |
| FR-8 (mark_duplicates picard wrapper) | 03 | AC-8 |
| FR-9 (reditools.py on PATH) | 04 | AC-9 |
| FR-10 (sprint /opt path) | 04 | AC-9 |
| FR-11 (jacusa2 /opt path) | 04 | AC-9 |
| FR-12 (red_ML.pl on PATH) | 04 | AC-9 |
| FR-13 (downstream_dir param) | 05 | AC-10 |
| FR-14 (downstream_scripts_dir config) | 02 | AC-11 |
| FR-15 (star Dockerfile) | 06 | AC-12 |
| FR-16 (red_ml Dockerfile) | 07 | AC-13 |
| FR-17 (fastx Dockerfile) | 08 | AC-14 |
| FR-18 (morales_downstream Dockerfile) | 08 | AC-15 |
| FR-19 (star_mapping samtools stderr) | 03 | AC-5, AC-7 (set -euo pipefail in star_mapping per G-2) |
| FR-20 (add_md_tag uses wgs) | 04 | AC-17 |
| NFR-1 (snakemake --lint) | All | AC-1 |
| NFR-2 (dry-run < 60s) | All | AC-2 |
| NFR-3 (minimum Dockerfile content) | 06, 07, 08 | review |
| NFR-4 (validate.sh exit 0) | 06, 07, 08 | review (executed by `scripts/validate_containers.sh` post-build) |
| NFR-5 (mem_mb floors per rule) | 03, 04, 05 | AC-6 (values in resource table) |
| NFR-6 (apptainer SDM compatibility) | 01-05 | AC-2 |
| SEC-1 (no user paths) | 02, 04, 05 | AC-3 |
| SEC-2 (Dockerfile non-root preference) | 06, 07, 08 | review (note: pinned to upstream conventions; existing containers also run as root, so this requirement is informational) |

## 9. Risk Register

| ID | Risk | Severity | Mitigation | Owner Task |
|----|------|----------|-----------|-----------|
| R-1 | `picard` wrapper not on PATH inside SIF | High | Verified in `containers/picard/Dockerfile` line 17; reviewer must confirm wrapper exists before merge | Task 03 (verify), human review |
| R-2 | RED-ML R package install fails (CRAN snapshot drift) | Medium | Pin R version via `rocker/r-ver:4.3.2`; use `repos="https://cloud.r-project.org/"`; install five canonical packages (`caret`, `data.table`, `ROCR`, `randomForest`, `e1071`) | Task 07 |
| R-3 | FASTX bioconda package unavailable on amd64 (rare) | Medium | Bioconda `fastx_toolkit` is currently published for `linux-64`; document fallback to source compile (Ubuntu 20.04) in task notes | Task 08 |
| R-4 | STAR static binary URL changes upstream | Low | Pin `STAR_VERSION=2.7.11a`; URL pattern is stable per upstream conventions | Task 06 |
| R-5 | `bcftools` / `add_md_tag` rule fails Snakemake's "log handle written to" check | Medium | Use sentinel `echo` to write `{log.stdout}`; write `{output}` via shell `>` redirect; D-8 documents this | Task 04 |
| R-6 | Empty downstream submodule causes runtime failure | Low | Documented in config.yaml comment; dry-run still passes | Task 02 (config comment), task 05 (log paths) |
| R-7 | Resource lambdas produce mem_mb above SLURM partition cap on attempt 4 | Low | Default SLURM partition `condo` accommodates up to 256 GB; `32000 * 1.5^3 = 108 GB` is below cap | Task 03/04 |
| R-8 | New SIF files do not exist at `--dry-run` time | Low | Dry-run does not verify SIF existence; operators run `scripts/validate_containers.sh` post-merge | All container tasks |
| R-9 | Existing reditools container has Python 2.7; `reditools.py` may fail with Python 3 input | Low | Inherited; not introduced by this change. Container is unchanged | Task 04 |
| R-10 | Snakemake's `directory(...)` output for `red_ml` rule plus a missing trailing slash trips up some shells | Low | Existing behavior preserved; no change introduced | Task 04 |

Hotspot risk integration: the hotspot register in `.forge/hotspot/hotspots.json` lists no Morales pipeline files. No additional review burden imposed by hotspots.

## 10. Verification Plan

Run from `pipelines/Morales_et_all/`:

1. `snakemake --lint --snakefile Snakefile --configfile config.yaml` -> exit 0, 0 errors. Implements AC-1, NFR-1.
2. `snakemake -n --snakefile Snakefile --configfile config.yaml --cores 1` -> exit 0, < 60s wall clock. Implements AC-2, NFR-2.

Run from repo root:

3. `grep -rn "container:" pipelines/Morales_et_all/*.smk | wc -l` -> `14`. AC-4.
4. `grep -rn "^    log:" pipelines/Morales_et_all/*.smk | wc -l` -> `14`. AC-5.
5. `grep -rn "^    resources:" pipelines/Morales_et_all/*.smk | wc -l` -> `14`. AC-6.
6. `grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/` -> exit 1, no matches. AC-3.
7. `grep "java -jar" pipelines/Morales_et_all/preprocessing.smk` -> no matches. AC-8.
8. `grep -E "params\.(script|sprint_bin|jacusa_jar|samtools_bin)" pipelines/Morales_et_all/*.smk` -> no matches. AC-9.
9. `grep "python Downstream/" pipelines/Morales_et_all/downstream.smk` -> no matches. AC-10.
10. `grep -c "downstream_scripts_dir" pipelines/Morales_et_all/config.yaml` -> `1`. AC-11.
11. `grep "set -euo pipefail" pipelines/Morales_et_all/tools.smk | head` -> bcftools rule present. AC-7.
12. `grep "container_for(\"wgs\")" pipelines/Morales_et_all/tools.smk` -> at least 2 matches (bcftools and add_md_tag). AC-17.
13. `grep "container_for" pipelines/Morales_et_all/Snakefile` -> 1 function definition. AC-16.
14. `test -f containers/star/Dockerfile && test -f containers/star/validate.sh` -> exit 0. AC-12.
15. `test -f containers/red_ml/Dockerfile && test -f containers/red_ml/validate.sh` -> exit 0. AC-13.
16. `test -f containers/fastx/Dockerfile && test -f containers/fastx/validate.sh` -> exit 0. AC-14.
17. `test -f containers/morales_downstream/Dockerfile && test -f containers/morales_downstream/validate.sh` -> exit 0. AC-15.
18. `python -m unittest tests/test_sprint_to_deepred_vcf.py` -> all tests pass.

Post-merge (human runs, not part of build):

- `TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh` builds and validates the four new SIFs. Exit 0 expected.

## 11. Out of Scope (explicit non-goals)

The following are deliberately excluded; the implementer must not perform them:

- Editing any file under `pipelines/editing_wgs/`.
- Editing any file under `containers/{picard,reditools,sprint,wgs,jacusa2}/`.
- Initializing or populating `Benchmark-of-RNA-Editing-Detection-Tools/`.
- Building, pushing, or referencing any actual `.sif` file beyond the path strings in `config.yaml`.
- Running the pipeline on real data, on TSCC or anywhere else.
- Adding new analysis rules.
- Removing the unused `aligners:` config key.
- Modifying `profiles/tscc2/config.yaml`.

## 12. Glossary and References

- **`container_for(tool)`**: Helper function defined in each pipeline's Snakefile that maps a tool name to a SIF path. Falls back to `{SIF_DIR}/{tool}.sif` if no explicit `containers:` mapping is configured.
- **SIF**: Singularity Image Format. Apptainer-readable container image file.
- **SDM**: Software Deployment Method. The Snakemake 9 successor to `--use-singularity`/`--use-conda`/`--use-envmodules`.
- **Apptainer**: Open-source Singularity fork; the actual binary on TSCC.
- **HITL**: Human-In-The-Loop checkpoint.

References:
- Architect input: `.forge/stages/1-requirements/architect-prompt.md`
- Canonical pattern: `pipelines/editing_wgs/Snakefile` lines 14-25, `pipelines/editing_wgs/rna_editing.smk` lines 6-29
- Build script: `scripts/validate_containers.sh`
- TSCC profile: `profiles/tscc2/config.yaml`
- Conflicts ledger: `.forge/stages/0-research/conflicts-resolved.md`
- ADRs: `.forge/stages/2-architect/adrs/ADR-01..ADR-04`
- Threat model: `.forge/stages/2-architect/threat-model.md`
