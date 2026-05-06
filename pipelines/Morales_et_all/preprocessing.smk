localrules: prepare_fastq


rule prepare_fastq:
    """Decompress samplesheet FASTQ.GZ paths to data/fastq/{condition}_{sample}_{read}.fastq."""
    input:
        samplesheet_fastq_path
    output:
        "data/fastq/{condition}_{sample}_{read}.fastq"
    shell:
        "zcat {input} > {output}"


rule trim_reads:
    # Trims each read file independently. fastx_trimmer truncates to a fixed length
    # without filtering, so R1 and R2 always retain the same read count and order
    # when trimmed separately — paired-end synchronization is guaranteed.
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
        r2=lambda wildcards: (
            expand(
                "results/trimmed/{condition}_{sample}_R2_trimmed.fastq.gz",
                condition=wildcards.condition,
                sample=wildcards.sample,
            )
            if is_paired(wildcards.condition, wildcards.sample)
            else []
        )
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
        map_qual=config["params"]["star"]["map_quality"],
        # Build --readFilesIn argument: R1 only for SE, R1 R2 for PE.
        reads=lambda wildcards, input: (
            f"{input.r1} {input.r2[0]}" if len(input.r2) > 0 else input.r1
        ),
        # -f 0x2 (properly paired) is only valid for PE alignments.
        samflag=lambda wildcards, input: (
            "-F 0x04 -f 0x2" if len(input.r2) > 0 else "-F 0x04"
        ),
        # Picard MarkDuplicates requires read group tags in the BAM.
        rg_line=lambda wildcards: (
            f"ID:{wildcards.condition}_{wildcards.sample} "
            f"SM:{wildcards.condition}_{wildcards.sample} "
            f"PL:ILLUMINA LB:{wildcards.condition}_{wildcards.sample}"
        )
    shell:
        r"""
        set -euo pipefail
        STAR --runThreadN {threads} --genomeDir {params.ref_dir} \
             --readFilesIn {params.reads} --readFilesCommand zcat \
             --outSAMtype BAM SortedByCoordinate --outFileNamePrefix {params.prefix} \
             --outSAMattrRGline {params.rg_line} \
             1> {log.stdout} 2> {log.stderr}
        samtools view -@ {threads} {params.samflag} -q {params.map_qual} -b {params.prefix}Aligned.sortedByCoord.out.bam | \
            samtools sort -@ {threads} -T {params.prefix}tmp -o {output.bam} 2>> {log.stderr}
        samtools index -@ {threads} {output.bam} 2>> {log.stderr}
        rm {params.prefix}Aligned.sortedByCoord.out.bam
        """


rule mark_duplicates:
    input:
        bam="results/mapped/{condition}_{sample}.bam"
    output:
        rmdup_bam="results/mapped/{condition}_{sample}.rmdup.bam",
        rmdup_bai="results/mapped/{condition}_{sample}.rmdup.bam.bai",
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
        _JAVA_OPTIONS="-Xmx6g" picard MarkDuplicates INPUT={input.bam} OUTPUT={output.rmdup_bam} \
             METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true \
             1> {log.stdout} 2> {log.stderr}
        samtools index {output.rmdup_bam} 2>> {log.stderr}
        """
