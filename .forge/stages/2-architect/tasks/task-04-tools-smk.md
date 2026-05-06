# Task 04: Containerize tools.smk (6 rules)

<!-- DEPENDENCIES: 02 -->
<!-- LABELS: phase-3, stage:3-implement, smk-edit -->
<!-- VERIFIES: AC-4 (9/14), AC-5 (9/14), AC-6 (9/14), AC-7, AC-9, AC-17, FR-4, FR-5, FR-6, FR-7, FR-9, FR-10, FR-11, FR-12, FR-20, SEC-1 -->

## Goal

Fully rewrite `pipelines/Morales_et_all/tools.smk` to add `container:`, `log:`, and `resources:` directives to all 6 rules, remove all user-specific and cluster-specific tool paths, and route tool invocations through containerized executables on PATH.

## Files Modified

- `pipelines/Morales_et_all/tools.smk`

## Full Rewritten File

Replace the entire file content with:

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

## Acceptance Criteria

- [ ] `grep -c "^rule " pipelines/Morales_et_all/tools.smk` returns `6`
- [ ] `grep -c "    container: container_for" pipelines/Morales_et_all/tools.smk` returns `6`
- [ ] `grep -c "^    log:" pipelines/Morales_et_all/tools.smk` returns `6`
- [ ] `grep -c "^    resources:" pipelines/Morales_et_all/tools.smk` returns `6`
- [ ] `grep -c "set -euo pipefail" pipelines/Morales_et_all/tools.smk` returns `6`
- [ ] `grep "params.script\|params.sprint_bin\|params.jacusa_jar\|params.samtools_bin\|params.reditools_script\|params.red_ml_script" pipelines/Morales_et_all/tools.smk` returns no matches (PASS)
- [ ] `grep "~/bin\|/binf-isilon" pipelines/Morales_et_all/tools.smk` returns no matches (PASS)
- [ ] `grep "container_for(\"wgs\")" pipelines/Morales_et_all/tools.smk` returns 2 matches (bcftools and add_md_tag)
- [ ] `grep "container_for(\"jacusa2\")" pipelines/Morales_et_all/tools.smk` returns 1 match
- [ ] `python -c "import ast; ast.parse(open('pipelines/Morales_et_all/tools.smk').read())"` exits 0
- [ ] No other file is modified

## Verification

```bash
grep -c "^rule \|container: container_for\|^    log:\|^    resources:\|set -euo pipefail" pipelines/Morales_et_all/tools.smk
grep "params.script\|params.sprint_bin\|params.jacusa_jar\|params.samtools_bin" pipelines/Morales_et_all/tools.smk || echo "PASS: no hardcoded tool params"
grep "~/bin\|/binf-isilon" pipelines/Morales_et_all/tools.smk || echo "PASS: no user paths"
python -c "import ast; ast.parse(open('pipelines/Morales_et_all/tools.smk').read()); print('syntax OK')"
```

## Notes

- `add_md_tag` uses `container_for("wgs")` — NOT `container_for("jacusa2")` per D-7. `wgs.sif` contains SAMtools; pulling the full JACUSA2 mamba env just for `samtools calmd` wastes space.
- `bcftools` and `add_md_tag` write a sentinel `echo "... done"` to `{log.stdout}` because these rules write primary output via pipe or direct `>` redirect; routing stdout to the BAM/BCF stream AND to a log file requires two-handle separation. This satisfies Snakemake's named-log-handle requirement per D-8.
- `sprint` calls `python /opt/sprint/sprint_from_bam.py` — the absolute path is inside the sprint SIF (verified in D-4); `samtools` is also on PATH inside that container.
- `jacusa2` log paths are literal (no wildcards) because this is an aggregate rule across all samples — per EC-5 in the architecture plan.
- The `red_ml` output uses `directory()` because `red_ML.pl --outdir` writes multiple files into that directory.
