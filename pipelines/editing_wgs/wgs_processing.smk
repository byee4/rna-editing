# --- WGS Processing ---

# WGS Alignment: BWA-MEM is standard for genomic reads [5, 6, 15]
rule bwa_mem_wgs:
    input:
        fastq=lambda wildcards: sample_reads(wildcards, "wgs"),
        ref=REF
    output:
        bam=WORKDIR + "/mapped/{sample}.wgs.bam"
    threads: 24
    container: container_for("wgs")
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 1800 * (2 ** (attempt - 1)) # WGS alignment is a major bottleneck (~30h) [15, 16]
    log:
        stderr=WORKDIR + "/logs/{sample}.bwa_mem.err"
    shell:
        "bwa mem -t {threads} {input.ref} {input.fastq} 2> {log.stderr} | "
        "samtools view -Sb - | samtools sort -@ {threads} -o {output.bam}"


# Coverage and germline calls are WGS-only and intentionally consume .wgs.md.bam.
rule generate_dna_coverage:
    input:
        bam=WORKDIR + "/mapped/{sample}.wgs.md.bam"
    output:
        cov=WORKDIR + "/wgs_coverage/{sample}.cov"
    container: container_for("wgs")
    log:
        stderr=WORKDIR + "/logs/{sample}.wgs_coverage.err"
    shell:
        "samtools depth {input.bam} > {output.cov} 2> {log.stderr}"


# Germline variants from WGS MD-tagged BAMs can be used as genomic filters.
rule call_germline_variants:
    input:
        bam=WORKDIR + "/mapped/{sample}.wgs.md.bam",
        ref=REF
    output:
        vcf=WORKDIR + "/germline/{sample}_germline.vcf.gz",
        tbi=WORKDIR + "/germline/{sample}_germline.vcf.gz.tbi"
    container: container_for("wgs")
    log:
        stderr=WORKDIR + "/logs/{sample}.germline.err"
    shell:
        "{{ bcftools mpileup -f {input.ref} {input.bam} | "
        "bcftools call -mv -Oz -o {output.vcf}; }} 2> {log.stderr} && "
        "bcftools index -t {output.vcf} 2>> {log.stderr}"
