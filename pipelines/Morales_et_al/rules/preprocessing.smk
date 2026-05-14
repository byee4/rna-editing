# NOTE: prepare_fastq runs on the SLURM head node (localrule). This is fine for
# small_examples where each FASTQ is a few MB. For large production FASTQs (>1 GB),
# consider removing the localrule classification and dispatching to a worker node
# with container: container_for("wgs") and a small resources: block.
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
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 180 * (2 ** (attempt - 1))
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
        bam="results/mapped/star/{condition}_{sample}.bam",
        bai="results/mapped/star/{condition}_{sample}.bam.bai"
    threads: config["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 36000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("star")
    log:
        stdout="results/logs/{condition}_{sample}.star_mapping.out",
        stderr="results/logs/{condition}_{sample}.star_mapping.err"
    params:
        ref_dir=config["references"]["star_index"],
        prefix="results/mapped/star/{condition}_{sample}_",
        map_qual=config["params"]["star"]["map_quality"],
        reads=lambda wildcards, input: (
            f"{input.r1} {input.r2[0]}" if len(input.r2) > 0 else input.r1
        ),
        samflag=lambda wildcards, input: (
            "-F 0x04 -f 0x2" if len(input.r2) > 0 else "-F 0x04"
        ),
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


rule bwa_mapping:
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
        ),
        idx=multiext(config["references"]["fasta"], ".amb", ".ann", ".bwt", ".pac", ".sa"),
    output:
        bam="results/mapped/bwa/{condition}_{sample}.bam",
        bai="results/mapped/bwa/{condition}_{sample}.bam.bai"
    threads: config["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 36000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 240 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{condition}_{sample}.bwa_mapping.out",
        stderr="results/logs/{condition}_{sample}.bwa_mapping.err"
    params:
        ref=config["references"]["fasta"],
        prefix="results/mapped/bwa/{condition}_{sample}_",
        map_qual=config["params"]["star"]["map_quality"],
        reads=lambda wildcards, input: (
            f"{input.r1} {input.r2[0]}" if len(input.r2) > 0 else input.r1
        ),
        samflag=lambda wildcards, input: (
            "-F 0x04 -f 0x2" if len(input.r2) > 0 else "-F 0x04"
        ),
        # BWA -R field separator: newer BWA requires the literal two-character
        # escape \t (not a real tab). Python \\t → string \t → BWA parses as tab.
        rg=lambda wildcards: (
            f"@RG\\tID:{wildcards.condition}_{wildcards.sample}"
            f"\\tSM:{wildcards.condition}_{wildcards.sample}"
            f"\\tPL:ILLUMINA"
            f"\\tLB:{wildcards.condition}_{wildcards.sample}"
        ),
    shell:
        r"""
        set -euo pipefail
        bwa mem -t {threads} -R "{params.rg}" {params.ref} {params.reads} \
            2> {log.stderr} \
            | samtools view -@ {threads} {params.samflag} -q {params.map_qual} -b - \
            2>> {log.stderr} \
            | samtools sort -@ {threads} -T {params.prefix}tmp -o {output.bam} \
            2>> {log.stderr}
        samtools index -@ {threads} {output.bam} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule hisat2_mapping:
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
        ),
        idx=multiext(config["references"]["hisat2_index"],
                     ".1.ht2", ".2.ht2", ".3.ht2", ".4.ht2",
                     ".5.ht2", ".6.ht2", ".7.ht2", ".8.ht2"),
    output:
        bam="results/mapped/hisat2/{condition}_{sample}.bam",
        bai="results/mapped/hisat2/{condition}_{sample}.bam.bai"
    threads: config["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 36000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("hisat2")
    log:
        stdout="results/logs/{condition}_{sample}.hisat2_mapping.out",
        stderr="results/logs/{condition}_{sample}.hisat2_mapping.err"
    params:
        idx_prefix=config["references"]["hisat2_index"],
        prefix="results/mapped/hisat2/{condition}_{sample}_",
        map_qual=config["params"]["star"]["map_quality"],
        reads=lambda wildcards, input: (
            f"-1 {input.r1} -2 {input.r2[0]}" if len(input.r2) > 0 else f"-U {input.r1}"
        ),
        samflag=lambda wildcards, input: (
            "-F 0x04 -f 0x2" if len(input.r2) > 0 else "-F 0x04"
        ),
        rg_id=lambda wildcards: f"{wildcards.condition}_{wildcards.sample}",
    shell:
        r"""
        set -eu
        hisat2 -p {threads} -x {params.idx_prefix} {params.reads} \
            --rg-id "{params.rg_id}" \
            --rg "SM:{params.rg_id}" --rg "PL:ILLUMINA" --rg "LB:{params.rg_id}" \
            2> {log.stderr} \
            | samtools view -@ {threads} {params.samflag} -q {params.map_qual} -b - \
            2>> {log.stderr} \
            | samtools sort -@ {threads} -T {params.prefix}tmp -o {output.bam} \
            2>> {log.stderr}
        sts=("${{PIPESTATUS[@]}}")
        # HISAT2 exits 141 (SIGPIPE) when the pipe closes after samtools finishes;
        # this is expected behaviour, not a real alignment error.
        [[ ${{sts[0]}} -eq 0 || ${{sts[0]}} -eq 141 ]] || exit ${{sts[0]}}
        [[ ${{sts[1]}} -eq 0 ]] || exit ${{sts[1]}}
        [[ ${{sts[2]}} -eq 0 ]] || exit ${{sts[2]}}
        samtools index -@ {threads} {output.bam} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule mark_duplicates:
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.bam"
    output:
        rmdup_bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        metrics="results/mapped/{aligner}/{condition}_{sample}.duplication.info"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (2 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("picard")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.mark_duplicates.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.mark_duplicates.err"
    params:
        # Reserve 75 % of the SLURM-allocated memory for the JVM heap; the
        # remaining 25 % covers JVM overhead and native Picard allocations.
        mem_mb_heap=lambda wildcards, resources: int(resources.mem_mb * 0.75)
    shell:
        r"""
        set -euo pipefail
        _JAVA_OPTIONS="-Xmx{params.mem_mb_heap}m" picard MarkDuplicates INPUT={input.bam} OUTPUT={output.rmdup_bam} \
             METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true \
             1> {log.stdout} 2> {log.stderr}
        """


rule index_rmdup_bam:
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam"
    output:
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (2 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.index_rmdup_bam.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.index_rmdup_bam.err"
    shell:
        r"""
        set -euo pipefail
        samtools index {input.bam} {output.bai} 2> {log.stderr}
        echo "done" > {log.stdout}
        """
