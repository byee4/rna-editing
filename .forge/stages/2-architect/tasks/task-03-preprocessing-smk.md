# Task 03: Containerize preprocessing.smk (3 rules)

<!-- DEPENDENCIES: 02 -->
<!-- LABELS: phase-3, stage:3-implement, smk-edit -->
<!-- VERIFIES: AC-4 (3/14), AC-5 (3/14), AC-6 (3/14), AC-8, FR-4, FR-5, FR-6, FR-8, FR-19, NFR-5 -->

## Goal

Add `container:`, `log:`, `resources:`, and `set -euo pipefail` to all 3 rules in `pipelines/Morales_et_all/preprocessing.smk`. Rewrite `mark_duplicates` to call the `picard` wrapper instead of `java -jar`.

## Files Modified

- `pipelines/Morales_et_all/preprocessing.smk`

## Replace the entire file with

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

## Acceptance Criteria

- [ ] `grep -c "^rule " pipelines/Morales_et_all/preprocessing.smk` returns `3`
- [ ] `grep -c "    container: container_for" pipelines/Morales_et_all/preprocessing.smk` returns `3`
- [ ] `grep -c "^    log:" pipelines/Morales_et_all/preprocessing.smk` returns `3`
- [ ] `grep -c "^    resources:" pipelines/Morales_et_all/preprocessing.smk` returns `3`
- [ ] `grep -c "set -euo pipefail" pipelines/Morales_et_all/preprocessing.smk` returns `3`
- [ ] `grep "java -jar" pipelines/Morales_et_all/preprocessing.smk` returns no matches (PASS)
- [ ] `grep "params.picard" pipelines/Morales_et_all/preprocessing.smk` returns no matches
- [ ] `grep "container_for(\"fastx\")" pipelines/Morales_et_all/preprocessing.smk` returns 1 match
- [ ] `grep "container_for(\"star\")" pipelines/Morales_et_all/preprocessing.smk` returns 1 match
- [ ] `grep "container_for(\"picard\")" pipelines/Morales_et_all/preprocessing.smk` returns 1 match
- [ ] `python -c "import ast; ast.parse(open('pipelines/Morales_et_all/preprocessing.smk').read())"` exits 0
- [ ] No other file is modified

## Verification

```bash
grep -c "^rule \|container: container_for\|^    log:\|^    resources:\|set -euo pipefail" pipelines/Morales_et_all/preprocessing.smk
grep "java -jar\|params.picard" pipelines/Morales_et_all/preprocessing.smk || echo "PASS"
```

## Notes

- The `picard` shell call uses the wrapper at `/usr/local/bin/picard` inside the picard SIF, which `containers/picard/Dockerfile` line 17 confirms is installed.
- `mark_duplicates` no longer has a `params:` block (everything moved to direct shell call).
- `star_mapping` `set -euo pipefail` addresses gap G-2 (closes the silent-rm bug noted in EC-2).
- Resources values follow context/09 acceptance criteria's resource defaults table.
