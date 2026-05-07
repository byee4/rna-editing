import os

# ---------------------------------------------------------------------------
# WGS alignment and variant calling for HEK293T SNP filtering
# ---------------------------------------------------------------------------
# Adapted from pipelines/WGS/Snakefile.
#
# Config keys consumed (all under config["wgs_samples"]):
#   wgs_samples:
#     HEK293T:
#       - "/path/to/R1.fastq.gz"
#       - "/path/to/R2.fastq.gz"
#
# Final output per sample:
#   data/dbRNA-Editing/{wgs_sample}_hg38.bed
#     — 5-column BED (chr, start, end, ref, alt) of biallelic A>G and T>C SNPs,
#       used by build_dbrna_editing to produce HEK293T_hg38_clean.json.
# ---------------------------------------------------------------------------

_WGS_SAMPLES = list(config.get("wgs_samples", {}).keys())
_WGS_REF     = config["references"]["fasta"]
_DB_PATH     = config["references"]["db_path"]


rule wgs_bwa_mem:
    input:
        reads=lambda wc: config["wgs_samples"][wc.wgs_sample],
        ref=_WGS_REF
    output:
        temp("results/wgs/{wgs_sample}.raw.bam")
    threads: config["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 480 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/wgs_{wgs_sample}.bwa.out",
        stderr="results/logs/wgs_{wgs_sample}.bwa.err"
    shell:
        r"""
        set -euo pipefail
        bwa mem -t {threads} {input.ref} {input.reads} 2> {log.stderr} \
            | samtools view -h -b - > {output} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule wgs_deduplicate:
    input:
        "results/wgs/{wgs_sample}.raw.bam"
    output:
        temp("results/wgs/{wgs_sample}.dedup.bam")
    threads: config["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 240 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/wgs_{wgs_sample}.dedup.out",
        stderr="results/logs/wgs_{wgs_sample}.dedup.err"
    shell:
        r"""
        set -euo pipefail
        samtools sort -n -@ {threads} -O bam {input} 2> {log.stderr} \
            | samtools fixmate -m - - 2>> {log.stderr} \
            | samtools sort -@ {threads} - 2>> {log.stderr} \
            | samtools markdup -r - {output} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule wgs_md_tags:
    input:
        bam="results/wgs/{wgs_sample}.dedup.bam",
        ref=_WGS_REF
    output:
        bam="results/wgs/{wgs_sample}.md.bam",
        bai="results/wgs/{wgs_sample}.md.bam.bai"
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/wgs_{wgs_sample}.md.out",
        stderr="results/logs/wgs_{wgs_sample}.md.err"
    shell:
        r"""
        set -euo pipefail
        samtools calmd -b {input.bam} {input.ref} > {output.bam} 2> {log.stderr}
        samtools index {output.bam} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule wgs_call_variants:
    input:
        bam="results/wgs/{wgs_sample}.md.bam",
        ref=_WGS_REF
    output:
        vcf="results/wgs/{wgs_sample}_germline.vcf.gz",
        tbi="results/wgs/{wgs_sample}_germline.vcf.gz.tbi"
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 720 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/wgs_{wgs_sample}.variants.out",
        stderr="results/logs/wgs_{wgs_sample}.variants.err"
    params:
        max_depth=config["params"]["bcftools"]["max_depth"],
        map_q=config["params"]["bcftools"]["map_quality"],
        base_q=config["params"]["bcftools"]["base_quality"]
    shell:
        r"""
        set -euo pipefail
        bcftools mpileup \
            --max-depth {params.max_depth} \
            -q {params.map_q} -Q {params.base_q} \
            -f {input.ref} {input.bam} \
            2> {log.stderr} \
            | bcftools call -mv -Oz -o {output.vcf} 2>> {log.stderr}
        bcftools index -t {output.vcf} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule wgs_vcf_to_ag_tc_bed:
    """
    Filter germline VCF for biallelic A>G and T>C SNPs and write a 5-column BED.
    Output columns: chrom, start(0-based), end(1-based), ref, alt.
    This BED is consumed by build_dbrna_editing → HEK293T_hg38_clean.json.
    """
    input:
        vcf="results/wgs/{wgs_sample}_germline.vcf.gz"
    output:
        bed=os.path.join(_DB_PATH, "{wgs_sample}_hg38.bed")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/wgs_{wgs_sample}.ag_tc_bed.out",
        stderr="results/logs/wgs_{wgs_sample}.ag_tc_bed.err"
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.bed})"
        bcftools view -f "PASS,." -v snps -m2 -M2 {input.vcf} 2> {log.stderr} \
            | bcftools view -i '(REF="A" && ALT="G") || (REF="T" && ALT="C")' 2>> {log.stderr} \
            | awk 'BEGIN{{OFS="\t"}} !/^#/ {{print $1, $2-1, $2, $4, $5}}' \
            > {output.bed} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """
