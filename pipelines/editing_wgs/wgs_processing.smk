# --- WGS Processing ---

# BWA-MEM aligns WGS reads before BAM conversion and sorting [5, 6, 15].
# Sources: GitHub https://github.com/lh3/bwa; publication https://doi.org/10.48550/arXiv.1303.3997
rule bwa_mem_wgs:
    input:
        fastq=lambda wildcards: sample_reads(wildcards, "wgs"),
        ref=REF,
        ref_index=expand(REF + "{ext}", ext=BWA_INDEX_EXTENSIONS)
    output:
        bam=WORKDIR + f"/mapped/{{sample,{WGS_SAMPLE_PATTERN}}}.wgs.bam"
    wildcard_constraints:
        sample=WGS_SAMPLE_PATTERN
    threads: 24
    container: container_for("wgs")
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 1800 * (2 ** (attempt - 1)) # WGS alignment is a major bottleneck (~30h) [15, 16]
    log:
        stderr=WORKDIR + "/logs/{sample}.bwa_mem.err"
    shell:
        "bwa mem -t {threads} {input.ref} {input.fastq} 2> {log.stderr} | "
        "samtools sort -@ {threads} -o {output.bam} -"


# SAMtools depth creates WGS coverage profiles from MD-tagged DNA BAMs.
# Sources: GitHub https://github.com/samtools/samtools; publication https://doi.org/10.1093/bioinformatics/btp352
rule generate_dna_coverage:
    input:
        bam=WORKDIR + "/mapped/{sample}.wgs.md.bam",
        bai=WORKDIR + "/mapped/{sample}.wgs.md.bam.bai"
    output:
        cov=WORKDIR + f"/wgs_coverage/{{sample,{WGS_SAMPLE_PATTERN}}}.cov"
    wildcard_constraints:
        sample=WGS_SAMPLE_PATTERN
    container: container_for("wgs")
    log:
        stderr=WORKDIR + "/logs/{sample}.wgs_coverage.err"
    shell:
        "samtools depth {input.bam} > {output.cov} 2> {log.stderr}"


# BCFtools calls germline WGS variants that can be used as genomic filters.
# Sources: GitHub https://github.com/samtools/bcftools; publication https://doi.org/10.1093/gigascience/giab008
rule call_germline_variants:
    input:
        bam=WORKDIR + "/mapped/{sample}.wgs.md.bam",
        bai=WORKDIR + "/mapped/{sample}.wgs.md.bam.bai",
        ref=REF,
        fai=REF + ".fai"
    output:
        vcf=WORKDIR + f"/germline/{{sample,{WGS_SAMPLE_PATTERN}}}_germline.vcf.gz",
        tbi=WORKDIR + f"/germline/{{sample,{WGS_SAMPLE_PATTERN}}}_germline.vcf.gz.tbi"
    wildcard_constraints:
        sample=WGS_SAMPLE_PATTERN
    container: container_for("wgs")
    log:
        stderr=WORKDIR + "/logs/{sample}.germline.err"
    shell:
        r"""
        set -euo pipefail
        bcftools mpileup -f {input.ref} {input.bam} 2> {log.stderr} | \
            bcftools call -mv -Oz -o {output.vcf} 2>> {log.stderr}
        bcftools index -t {output.vcf} 2>> {log.stderr}
        """
