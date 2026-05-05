# --- RNA Editing Detection (DNA-RNA Comparison) ---


# JACUSA2 call-2 compares RNA and DNA BAMs for RNA-DNA differences [22, 23].
# Sources: GitHub https://github.com/dieterich-lab/JACUSA2; publication https://doi.org/10.1186/s13059-022-02676-0
rule jacusa2_dnarna:
    input:
        rna_bam=WORKDIR + "/mapped/{sample}.rna.md.bam",
        rna_bai=WORKDIR + "/mapped/{sample}.rna.md.bam.bai",
        wgs_bam=WORKDIR + "/mapped/{sample}.wgs.md.bam",
        wgs_bai=WORKDIR + "/mapped/{sample}.wgs.md.bam.bai"
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
# Sources: GitHub https://github.com/jumphone/SPRINT; publication https://doi.org/10.1093/bioinformatics/btx473
rule sprint_mapq_bam:
    input:
        bam=get_rna_bam
    output:
        bam=WORKDIR + "/sprint_mapq/{sample}.bam"
    threads: 4
    container: container_for("sprint")
    log:
        stdout=WORKDIR + "/logs/{sample}.sprint_mapq.out",
        stderr=WORKDIR + "/logs/{sample}.sprint_mapq.err"
    params:
        indir=WORKDIR + "/sprint_mapq/{sample}",
        in_sam=WORKDIR + "/sprint_mapq/{sample}/input.sam",
        mapq_sam=WORKDIR + "/sprint_mapq/{sample}/mapq30.sam"
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.indir}
        samtools view -h {input.bam} > {params.in_sam} 2> {log.stderr}
        python /opt/sprint/utilities/changesammapq.py {params.in_sam} {params.mapq_sam} \
            1> {log.stdout} 2>> {log.stderr}
        samtools sort -@ {threads} -T {params.indir}/tmp -o {output.bam} {params.mapq_sam} 2>> {log.stderr}
        rm -f {params.in_sam} {params.mapq_sam}
        """


rule sprint_from_bam:
    input:
        bam=WORKDIR + "/sprint_mapq/{sample}.bam",
        ref=REF
    output:
        res=WORKDIR + "/sprint/{sample}/SPRINT_identified_regular.res"
    resources:
        mem_mb=lambda wildcards, attempt: 12500 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 1400 * (2 ** (attempt - 1))
    benchmark: WORKDIR + "/benchmarks/{sample}.sprint.txt"
    container: container_for("sprint")
    log:
        stdout=WORKDIR + "/logs/{sample}.sprint.out",
        stderr=WORKDIR + "/logs/{sample}.sprint.err"
    params:
        outdir=WORKDIR + "/sprint/{sample}"
    shell:
        "python /opt/sprint/sprint_from_bam.py {input.bam} {input.ref} {params.outdir} samtools "
        "1> {log.stdout} 2> {log.stderr}"


# REDItools v1 extracts low-stringency RNA-only candidates for REDInet.
# Sources: GitHub https://github.com/BioinfoUNIBA/REDItools; REDInet https://github.com/BioinfoUNIBA/REDInet
rule reditools_for_redinet:
    input:
        bam=get_rna_bam,
        bai=WORKDIR + "/dedup/{sample}.rna.bam.bai",
        ref=REF,
        fai=REF + ".fai"
    output:
        reditable=WORKDIR + "/redinet/{sample}/outTable.gz",
        tbi=WORKDIR + "/redinet/{sample}/outTable.gz.tbi"
    threads: config["redinet"]["reditools_threads"]
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 12910 * (2 ** (attempt - 1))
    benchmark: WORKDIR + "/benchmarks/{sample}.reditools_for_redinet.txt"
    container: container_for("reditools")
    log:
        stdout=WORKDIR + "/logs/{sample}.reditools_for_redinet.out",
        stderr=WORKDIR + "/logs/{sample}.reditools_for_redinet.err"
    params:
        outdir=WORKDIR + "/redinet/{sample}"
    shell:
        r"""
        set -euo pipefail
        rm -rf {params.outdir}
        mkdir -p {params.outdir}
        python /opt/reditools/main/REDItoolDnaRna.py \
            -o {params.outdir} -i {input.bam} -f {input.ref} \
            -t {threads} \
            -c 0,1 -m 0,255 -v 1 -q 0,30 \
            -e -n 0.0 -N 0.0 -u -l -p -s 2 -g 2 -S \
            1> {log.stdout} 2> {log.stderr}
        outtable=$(find {params.outdir} -path "*/outTable_*" -type f | head -n 1)
        if [ -z "$outtable" ]; then
            echo "REDItools did not create an outTable_* file in {params.outdir}" >&2
            exit 1
        fi
        bgzip -f "$outtable"
        mv -f "${{outtable}}.gz" {output.reditable}
        tabix -s 1 -b 2 -e 2 -c R {output.reditable}
        """


# DeepRed scores SPRINT editing candidates with the configured DeepRed image.
# Sources: GitHub https://github.com/wenjiegroup/DeepRed; publication https://doi.org/10.1038/s41598-018-24298-y
rule deepred_predict:
    input:
        snvs=WORKDIR + "/sprint/{sample}/SPRINT_identified_regular.res"
    output:
        vcf=temp(WORKDIR + "/deepred/{sample}.gatk.raw.vcf"),
        pred=WORKDIR + "/deepred/{sample}_predictions.txt"
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    benchmark: WORKDIR + "/benchmarks/{sample}.deepred.txt"
    container: container_for("deepred")
    log:
        stdout=WORKDIR + "/logs/{sample}.deepred.out",
        stderr=WORKDIR + "/logs/{sample}.deepred.err"
    params:
        vcf_script=DEEPRED_VCF_SCRIPT,
        project=lambda wildcards: wildcards.sample,
        sample=lambda wildcards: wildcards.sample,
        matlab_arg=deepred_matlab_arg,
        deepred_root_arg=deepred_root_arg,
        reference_arg=deepred_reference_arg,
        slurm_bin_dir_arg=deepred_slurm_bin_dir_arg
    shell:
        "python {params.vcf_script} {input.snvs} {output.vcf} && "
        "deepred_predict --input-vcf {output.vcf} --project {params.project} "
        "--sample {params.sample} --output {output.pred} {params.matlab_arg} {params.deepred_root_arg} "
        "{params.reference_arg} {params.slurm_bin_dir_arg} "
        "1> {log.stdout} 2> {log.stderr}"


# EditPredict filters and scores SPRINT candidates against the reference genome.
# Sources: GitHub https://github.com/wjd198605/EditPredict; publication https://doi.org/10.1016/j.ygeno.2021.09.016
rule editpredict_filter:
    input:
        ref=REF,
        pos=WORKDIR + "/sprint/{sample}/SPRINT_identified_regular.res",
        variants=variant_input
    output:
        positions=temp(WORKDIR + "/editpredict/{sample}_positions.tsv"),
        out=WORKDIR + "/editpredict/{sample}_scores.txt"
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    benchmark: WORKDIR + "/benchmarks/{sample}.editpredict.txt"
    container: container_for("editpredict")
    log:
        stdout=WORKDIR + "/logs/{sample}.editpredict.out",
        stderr=WORKDIR + "/logs/{sample}.editpredict.err"
    params:
        positions_script=EDITPREDICT_POSITIONS_SCRIPT,
        variant_arg=lambda wildcards, input: editpredict_variant_arg(input.variants)
    shell:
        r"""
        set -euo pipefail
        export TMPDIR=/tmp
        python {params.positions_script} {input.pos} {output.positions} \
            1> {log.stdout} 2> {log.stderr}
        editpredict_score --reference {input.ref} --positions {output.positions} \
            --output {output.out} {params.variant_arg} \
            1>> {log.stdout} 2>> {log.stderr}
        """


# REDInet classifies tabix-indexed REDItools candidate tables into editing classes.
# Sources: GitHub https://github.com/BioinfoUNIBA/REDInet; publication https://doi.org/10.1093/bib/bbaf107
rule redinet_classify:
    input:
        reditable=WORKDIR + "/redinet/{sample}/outTable.gz",
        tbi=WORKDIR + "/redinet/{sample}/outTable.gz.tbi",
        ref=REF
    output:
        classified=WORKDIR + "/redinet/{sample}_classified.txt.predictions.tsv"
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    benchmark: WORKDIR + "/benchmarks/{sample}.redinet.txt"
    container: container_for("redinet")
    log:
        stdout=WORKDIR + "/logs/{sample}.redinet.out",
        stderr=WORKDIR + "/logs/{sample}.redinet.err"
    params:
        min_coverage=config["redinet"]["min_coverage"],
        ag_frequency=config["redinet"]["ag_frequency"],
        min_ag_subs=config["redinet"]["min_ag_subs"],
        output_prefix=lambda wildcards: WORKDIR + f"/redinet/{wildcards.sample}_classified.txt"
    shell:
        r"""
        set -euo pipefail
        nrows=$(zcat {input.reditable} | tail -n +2 | wc -l)
        if [ "$nrows" -eq 0 ]; then
            echo "outTable.gz has no data rows; skipping classification" > {log.stdout}
            touch {output.classified}
        else
            redinet_classify --reditable {input.reditable} --reference {input.ref} \
                --output {params.output_prefix} --min-coverage {params.min_coverage} \
                --ag-frequency {params.ag_frequency} --min-ag-subs {params.min_ag_subs} \
                1> {log.stdout} 2> {log.stderr}
        fi
        """
