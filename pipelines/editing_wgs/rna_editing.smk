# --- RNA Editing Detection (DNA-RNA Comparison) ---

# REDItools2: The DNA-RNA script uses genomic reads to purge SNPs [9, 20, 21]
rule reditools2_dnarna:
    input:
        rna_bam=WORKDIR + "/dedup/{sample}.rna.bam",
        wgs_bam=WORKDIR + "/dedup/{sample}.wgs.bam",
        ref=REF
    output:
        table=WORKDIR + f"/reditools2_dnarna/{{sample,{WGS_SAMPLE_PATTERN}}}.tsv"
    wildcard_constraints:
        sample=WGS_SAMPLE_PATTERN
    threads: config["reditools2"]["threads"]
    container: container_for("reditools")
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 12000 * (2 ** (attempt - 1)) # Multi-day runtime for large WGS data [16]
    params:
        min_cov=config["reditools2"]["min_cov"]
    log:
        stdout=WORKDIR + "/logs/{sample}.reditools2.out",
        stderr=WORKDIR + "/logs/{sample}.reditools2.err"
    shell:
        "python /opt/reditools/main/REDItoolDnaRna.py -i {input.rna_bam} -j {input.wgs_bam} "
        "-f {input.ref} -o {output.table} "
        "-c {params.min_cov},{params.min_cov} -q 30,30 -m 30,255 -v 3 "
        "1> {log.stdout} 2> {log.stderr}"


# JACUSA2: call-2 mode in RDD (RNA-DNA Difference) mode [22, 23]
rule jacusa2_dnarna:
    input:
        rna_bam=WORKDIR + "/mapped/{sample}.rna.md.bam",
        wgs_bam=WORKDIR + "/mapped/{sample}.wgs.md.bam"
    output:
        out=WORKDIR + f"/jacusa2_dnarna/{{sample,{WGS_SAMPLE_PATTERN}}}.out"
    wildcard_constraints:
        sample=WGS_SAMPLE_PATTERN
    threads: config["jacusa2"]["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 33350 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 400 * (2 ** (attempt - 1))
    container: container_for("jacusa2")
    log:
        stdout=WORKDIR + "/logs/{sample}.jacusa2.out",
        stderr=WORKDIR + "/logs/{sample}.jacusa2.err"
    params:
        filters=config["jacusa2"]["filters"]
    shell:
        "java -jar /opt/jacusa2/jacusa2.jar call-2 -r {output.out} -p {threads} "
        "-a {params.filters} {input.rna_bam} {input.wgs_bam} "
        "1> {log.stdout} 2> {log.stderr}"


# --- RNA-only Editing Detection and Classification ---

# SPRINT takes coordinate-sorted BAMs and reports RNA editing candidates.
rule sprint_from_bam:
    input:
        bam=get_rna_bam,
        ref=REF
    output:
        res=WORKDIR + "/sprint/{sample}/regular.res"
    resources:
        mem_mb=lambda wildcards, attempt: 12500 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 1400 * (2 ** (attempt - 1))
    benchmark: "benchmarks/{sample}.sprint.txt"
    container: container_for("sprint")
    log:
        stdout=WORKDIR + "/logs/{sample}.sprint.out",
        stderr=WORKDIR + "/logs/{sample}.sprint.err"
    params:
        outdir=WORKDIR + "/sprint/{sample}"
    shell:
        "sprint_from_bam {input.bam} {input.ref} {params.outdir} samtools "
        "1> {log.stdout} 2> {log.stderr}"


# REDItools2 serial mode runs RNA-only candidate discovery from the RNA BAM.
rule reditools2_serial:
    input:
        bam=get_rna_bam,
        ref=REF
    output:
        table=WORKDIR + "/reditools2/{sample}.tsv"
    threads: config["reditools2"]["threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 1350 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 12910 * (2 ** (attempt - 1))
    benchmark: "benchmarks/{sample}.reditools2_serial.txt"
    container: container_for("reditools")
    log:
        stdout=WORKDIR + "/logs/{sample}.reditools2_serial.out",
        stderr=WORKDIR + "/logs/{sample}.reditools2_serial.err"
    params:
        min_cov=config["reditools2"]["min_cov"]
    shell:
        "python /opt/reditools2/src/cineca/reditools.py "
        "-f {input.bam} -r {input.ref} -o {output.table} "
        "-l {params.min_cov} -V "
        "1> {log.stdout} 2> {log.stderr}"


# DeepRED scores SPRINT editing candidates with the configured DeepRED image.
rule deepred_predict:
    input:
        snvs=WORKDIR + "/sprint/{sample}/regular.res"
    output:
        pred=WORKDIR + "/deepred/{sample}_predictions.txt"
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    benchmark: "benchmarks/{sample}.deepred.txt"
    container: container_for("deepred")
    log:
        stdout=WORKDIR + "/logs/{sample}.deepred.out",
        stderr=WORKDIR + "/logs/{sample}.deepred.err"
    shell:
        "deepred_predict --input {input.snvs} --output {output.pred} "
        "1> {log.stdout} 2> {log.stderr}"


# editPredict filters and scores SPRINT candidates against the reference genome.
rule editpredict_filter:
    input:
        ref=REF,
        pos=WORKDIR + "/sprint/{sample}/regular.res",
        variants=variant_input
    output:
        positions=temp(WORKDIR + "/editpredict/{sample}_positions.tsv"),
        out=WORKDIR + "/editpredict/{sample}_scores.txt"
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    benchmark: "benchmarks/{sample}.editpredict.txt"
    container: container_for("editpredict")
    log:
        stdout=WORKDIR + "/logs/{sample}.editpredict.out",
        stderr=WORKDIR + "/logs/{sample}.editpredict.err"
    params:
        positions_script=EDITPREDICT_POSITIONS_SCRIPT,
        variant_arg=lambda wildcards, input: editpredict_variant_arg(input.variants)
    shell:
        "python {params.positions_script} {input.pos} {output.positions} "
        "1> {log.stdout} 2> {log.stderr} && "
        "editpredict_score --reference {input.ref} --positions {output.positions} "
        "--output {output.out} {params.variant_arg} "
        "1>> {log.stdout} 2>> {log.stderr}"


# REDI-NET classifies REDItools2 serial output into candidate editing classes.
rule redinet_classify:
    input:
        reditable=WORKDIR + "/reditools2/{sample}.tsv",
        ref=REF
    output:
        classified=WORKDIR + "/redinet/{sample}_classified.txt"
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    benchmark: "benchmarks/{sample}.redinet.txt"
    container: container_for("redinet")
    log:
        stdout=WORKDIR + "/logs/{sample}.redinet.out",
        stderr=WORKDIR + "/logs/{sample}.redinet.err"
    params:
        min_coverage=config["redinet"]["min_coverage"],
        ag_frequency=config["redinet"]["ag_frequency"],
        min_ag_subs=config["redinet"]["min_ag_subs"]
    shell:
        "redinet_classify --reditable {input.reditable} --reference {input.ref} "
        "--output {output.classified} --min-coverage {params.min_coverage} "
        "--ag-frequency {params.ag_frequency} --min-ag-subs {params.min_ag_subs} "
        "1> {log.stdout} 2> {log.stderr}"
