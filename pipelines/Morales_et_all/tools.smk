rule reditools:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{condition}_{sample}.rmdup.bam.bai"
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
        bam="results/mapped/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{condition}_{sample}.rmdup.bam.bai"
    output:
        directory("results/tools/sprint/{condition}_{sample}_output")
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
        # sprint_from_bam.py exits 1 even on success; suppress and verify output
        python /opt/sprint/sprint_from_bam.py -rp {params.rmsk} {input.bam} {params.ref} {output} samtools \
            1> {log.stdout} 2> {log.stderr} || true
        test -f {output}/SPRINT_identified_regular.res
        """


rule bcftools:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{condition}_{sample}.rmdup.bam.bai"
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
        bam="results/mapped/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{condition}_{sample}.rmdup.bam.bai"
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
        bam="results/mapped/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{condition}_{sample}.rmdup.bam.bai"
    output:
        bam="results/mapped/{condition}_{sample}.rmdup_MD.bam",
        bai="results/mapped/{condition}_{sample}.rmdup_MD.bam.bai"
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
        samtools calmd -b {input.bam} {params.ref} > {output.bam} 2> {log.stderr}
        samtools index {output.bam} 2>> {log.stderr}
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
