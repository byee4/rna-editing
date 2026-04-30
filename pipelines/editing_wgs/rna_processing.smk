# --- RNA Processing ---

# RNA Alignment: STAR is recommended for its splice-awareness and speed [5, 12]
rule star_align_rna:
    input:
        fastq=lambda wildcards: sample_reads(wildcards, "rna"),
        ref=REF
    output:
        bam=WORKDIR + "/mapped/{sample}.rna.bam"
    threads: 12
    container: container_for("star")
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)), # STAR requires ~30GB for human [13, 14]
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    log:
        stdout=WORKDIR + "/logs/{sample}.star.out",
        stderr=WORKDIR + "/logs/{sample}.star.err"
    params:
        prefix=WORKDIR + "/mapped/{sample}.rna.",
        star_bam=WORKDIR + "/mapped/{sample}.rna.Aligned.sortedByCoord.out.bam"
    shell:
        "STAR --runThreadN {threads} --genomeDir {input.ref}_idx --readFilesIn {input.fastq} "
        "--readFilesCommand zcat --outSAMtype BAM SortedByCoordinate "
        "--outFileNamePrefix {params.prefix} 1> {log.stdout} 2> {log.stderr} && "
        "mv -f {params.star_bam} {output.bam}"
