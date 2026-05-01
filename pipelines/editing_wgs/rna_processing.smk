# --- RNA Processing ---

# STAR builds the splice-aware genome index shared by RNA alignment jobs.
# Sources: GitHub https://github.com/alexdobin/STAR; publication https://doi.org/10.1093/bioinformatics/bts635
rule star_genome_generate:
    input:
        ref=REF
    output:
        idx=directory(STAR_INDEX)
    threads: 12
    container: container_for("star")
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    log:
        stdout=WORKDIR + "/logs/star_genome_generate.out",
        stderr=WORKDIR + "/logs/star_genome_generate.err"
    shell:
        "mkdir -p {output.idx} && "
        "STAR --runThreadN {threads} --runMode genomeGenerate "
        "--genomeDir {output.idx} --genomeFastaFiles {input.ref} "
        "1> {log.stdout} 2> {log.stderr}"


# STAR is recommended for splice-aware RNA alignment and speed [5, 12].
# Sources: GitHub https://github.com/alexdobin/STAR; publication https://doi.org/10.1093/bioinformatics/bts635
rule star_align_rna:
    input:
        fastq=lambda wildcards: sample_reads(wildcards, "rna"),
        star_index=STAR_INDEX
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
        "STAR --runThreadN {threads} --genomeDir {input.star_index} --readFilesIn {input.fastq} "
        "--readFilesCommand zcat --outSAMtype BAM SortedByCoordinate "
        "--outFileNamePrefix {params.prefix} 1> {log.stdout} 2> {log.stderr} && "
        "mv -f {params.star_bam} {output.bam}"
