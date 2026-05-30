def _sprint_bam(wildcards):
    if wildcards.aligner == "bwa":
        return f"results/mapped/{wildcards.aligner}/{wildcards.condition}_{wildcards.sample}.rmdup.bam"
    return f"results/mapped/{wildcards.aligner}/{wildcards.condition}_{wildcards.sample}.rmdup_mapq30.bam"


def _sprint_bai(wildcards):
    if wildcards.aligner == "bwa":
        return f"results/mapped/{wildcards.aligner}/{wildcards.condition}_{wildcards.sample}.rmdup.bam.bai"
    return f"results/mapped/{wildcards.aligner}/{wildcards.condition}_{wildcards.sample}.rmdup_mapq30.bam.bai"


# ─────────────────────────────────────────────────────────────────────────────
# REDItools — per-chromosome parallel execution
# ─────────────────────────────────────────────────────────────────────────────

checkpoint get_chrom_list:
    """Write the list of chromosomes with mapped reads to a text file."""
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        "results/mapped/{aligner}/{condition}_{sample}.chroms.txt"
    resources:
        mem_mb=2000,
        runtime=10
    container: container_for("wgs")
    shell:
        "samtools idxstats {input.bam} | awk '$3>0 {{print $1}}' > {output}"


rule split_bam_by_chrom:
    """Extract one chromosome from the BAM for parallel REDItools processing."""
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        bam=temp("results/mapped/{aligner}/{condition}_{sample}.split/{chrom}.bam"),
        bai=temp("results/mapped/{aligner}/{condition}_{sample}.split/{chrom}.bam.bai")
    wildcard_constraints:
        chrom="[^/]+"
    resources:
        mem_mb=lambda wildcards, attempt: 2000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 20 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}_{chrom}.split_bam.out",
        stderr="results/logs/{aligner}_{condition}_{sample}_{chrom}.split_bam.err"
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.bam})"
        samtools view -b {input.bam} {wildcards.chrom} > {output.bam} 2> {log.stderr}
        samtools index {output.bam} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule reditools_by_chrom:
    """Run REDItools on a single-chromosome BAM using the -g region flag."""
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.split/{chrom}.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.split/{chrom}.bam.bai"
    output:
        temp("results/tools/{aligner}/reditools_split/{condition}_{sample}/{chrom}.output")
    wildcard_constraints:
        chrom="[^/]+"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (1.5 ** (attempt - 1))
    container: container_for("reditools")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}_{chrom}.reditools.out",
        stderr="results/logs/{aligner}_{condition}_{sample}_{chrom}.reditools.err"
    params:
        ref=config["references"]["fasta"]
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        reditools.py -S -C -bq 20 -q 20 \
            -f {input.bam} -r {params.ref} \
            -g {wildcards.chrom} -o {output} \
            1> {log.stdout} 2> {log.stderr}
        """


def _reditools_chrom_outputs(wildcards):
    chrom_file = checkpoints.get_chrom_list.get(
        aligner=wildcards.aligner,
        condition=wildcards.condition,
        sample=wildcards.sample,
    ).output[0]
    chroms = [c for c in open(chrom_file).read().strip().split("\n") if c]
    return [
        f"results/tools/{wildcards.aligner}/reditools_split/"
        f"{wildcards.condition}_{wildcards.sample}/{chrom}.output"
        for chrom in chroms
    ]


rule join_reditools_output:
    """Merge per-chromosome REDItools outputs; keep header from first file only."""
    input:
        _reditools_chrom_outputs
    output:
        "results/tools/{aligner}/reditools/{condition}_{sample}.output"
    localrule: True
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        first=1
        for f in {input}; do
            if [ "$first" -eq 1 ]; then
                cat "$f" > {output}
                first=0
            else
                tail -n +2 "$f" >> {output}
            fi
        done
        """


rule unzip_rmsk:
    params:
        rmsk=config["references"]["rmsk"]
    output:
        rmsk="data/rmsk.txt"
    resources:
        mem_mb=lambda wildcards, attempt: 24000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 10 * (2 ** (attempt - 1))
    container: container_for("sprint")
    log:
        stdout="results/logs/unzip_rmsk.out",
        stderr="results/logs/unzip_rmsk.err"
    shell:
        r"""
        set -euo pipefail
        zcat {params.rmsk} > {output.rmsk} 2> {log.stderr}
        echo "done" > {log.stdout}
        """


rule sprint_mapq_bam:
    # STAR and HISAT2 emit MAPQ=255 for uniquely mapped reads; SPRINT rejects
    # this value. Rewrite to MAPQ=30 using rewrite_mapq.py (pysam-based) so
    # the shared rmdup BAM is not modified. changesammapq.py (SPRINT's own
    # utility) produces malformed BGZF blocks that SAMtools 1.2 inside
    # sprint_from_bam.py cannot read, causing empty output for non-BWA aligners.
    # BWA assigns real MAPQ values and skips this rule via wildcard_constraints.
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup_mapq30.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup_mapq30.bam.bai"
    wildcard_constraints:
        aligner="star|hisat2"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (2 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("sprint")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.sprint_mapq_bam.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.sprint_mapq_bam.err"
    shell:
        r"""
        set -euo pipefail
        python3 /usr/local/bin/rewrite_mapq.py {input.bam} {output.bam} 30 2> {log.stderr}
        samtools index {output.bam} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule sprint:
    input:
        bam=_sprint_bam,
        bai=_sprint_bai,
        unzip_rmsk="data/rmsk.txt"
    output:
        directory("results/tools/{aligner}/sprint/{condition}_{sample}_output")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 36000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 240 * (2 ** (attempt - 1))
    container: container_for("sprint")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.sprint.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.sprint.err"
    params:
        ref=config["references"]["fasta"],
    shell:
        r"""
        set -euo pipefail
        # sprint_from_bam.py exits 1 even on success; suppress and verify output
        python /opt/sprint/sprint_from_bam.py -rp {input.unzip_rmsk} {input.bam} {params.ref} {output} samtools \
            1> {log.stdout} 2> {log.stderr} || true
        test -f {output}/SPRINT_identified_regular.res
        """


rule bcftools:
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        "results/tools/{aligner}/bcftools/{condition}_{sample}.bcf"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 180 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.bcftools.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.bcftools.err"
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
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        directory("results/tools/{aligner}/red_ml/{condition}_{sample}_output")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 48000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 240 * (2 ** (attempt - 1))
    container: container_for("red_ml")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.red_ml.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.red_ml.err"
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
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup_MD.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup_MD.bam.bai"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.add_md_tag.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.add_md_tag.err"
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
        wt_bams=lambda wildcards: expand(
            "results/mapped/{aligner}/WT_{sample}.rmdup_MD.bam",
            aligner=wildcards.aligner,
            sample=config["samples"]
        ),
        ko_bams=lambda wildcards: expand(
            "results/mapped/{aligner}/ADAR1KO_{sample}.rmdup_MD.bam",
            aligner=wildcards.aligner,
            sample=config["samples"]
        )
    output:
        "results/tools/{aligner}/jacusa2/Jacusa.out"
    threads: 5
    resources:
        mem_mb=lambda wildcards, attempt: 48000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 240 * (2 ** (attempt - 1))
    container: container_for("jacusa2")
    log:
        stdout="results/logs/{aligner}.jacusa2.out",
        stderr="results/logs/{aligner}.jacusa2.err"
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


# ---------------------------------------------------------
# REDItools3 / REDInet Rules
# ---------------------------------------------------------
rule reditools3:
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai",
        ref="results/references/ref_iupac_masked.fasta",
        ref_fai="results/references/ref_iupac_masked.fasta.fai"
    output:
        "results/tools/{aligner}/reditools3/{condition}_{sample}.txt"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 36000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 1200 * (1.5 ** (attempt - 1))
    container: container_for("redinet")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.reditools3.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.reditools3.err"
    params:
        strand=config["params"]["reditools3"]["strand"],
        map_quality=config["params"]["reditools3"]["map_quality"],
        base_quality=config["params"]["reditools3"]["base_quality"]
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        /opt/conda/envs/REDInet/bin/python3.10 -m reditools analyze \
            {input.bam} \
            -r {input.ref} \
            -o {output} \
            -s {params.strand} \
            -q {params.map_quality} \
            -bq {params.base_quality} \
            1> {log.stdout} 2> {log.stderr}
        """


rule reditools_redinet_by_chrom:
    # Step 1a of the REDInet workflow: run REDItoolDnaRna.py on a single-chromosome
    # BAM. The split BAM naturally restricts output to that chromosome. Output is a
    # per-chromosome temp directory because the tool names its outTable file using the PID.
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.split/{chrom}.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.split/{chrom}.bam.bai"
    output:
        temp(directory("results/tools/{aligner}/reditools_redinet/{condition}_{sample}_split/{chrom}/"))
    wildcard_constraints:
        chrom="[^/]+"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 36000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (1.5 ** (attempt - 1))
    container: container_for("reditools")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}_{chrom}.reditools_redinet.out",
        stderr="results/logs/{aligner}_{condition}_{sample}_{chrom}.reditools_redinet.err"
    params:
        ref=config["references"]["fasta"],
        strand=config["params"]["redinet"]["reditools_strand"],
        map_quality=config["params"]["redinet"]["map_quality"],
        base_quality=config["params"]["redinet"]["base_quality"],
        min_cov=config["params"]["redinet"]["min_cov"]
    shell:
        r"""
        set -euo pipefail
        mkdir -p {output}
        python /opt/reditools/main/REDItoolDnaRna.py \
            -i {input.bam} \
            -f {params.ref} \
            -o {output} \
            -s {params.strand} \
            -e -u \
            -q 0,{params.base_quality} \
            -m 0,{params.map_quality} \
            -c 0,{params.min_cov} \
            -t {threads} \
            1> {log.stdout} 2> {log.stderr}
        """


def _reditools_redinet_chrom_dirs(wildcards):
    chrom_file = checkpoints.get_chrom_list.get(
        aligner=wildcards.aligner,
        condition=wildcards.condition,
        sample=wildcards.sample,
    ).output[0]
    chroms = [c for c in open(chrom_file).read().strip().split("\n") if c]
    return [
        f"results/tools/{wildcards.aligner}/reditools_redinet/"
        f"{wildcards.condition}_{wildcards.sample}_split/{chrom}/"
        for chrom in chroms
    ]


rule join_reditools_redinet_output:
    # Step 1b: merge all per-chromosome outTable files into a single directory.
    # Header is taken from the first chromosome; subsequent files skip their header.
    # The merged outTable_merged file is what reditools_redinet_bgzip consumes.
    input:
        _reditools_redinet_chrom_dirs
    output:
        directory("results/tools/{aligner}/reditools_redinet/{condition}_{sample}_raw/")
    localrule: True
    shell:
        r"""
        set -euo pipefail
        mkdir -p {output}
        first=1
        for chrom_dir in {input}; do
            OUTTABLE=$(find "$chrom_dir" -name "outTable_*" | head -1)
            test -n "$OUTTABLE" || {{ echo "No outTable_* in $chrom_dir" >&2; exit 1; }}
            if [ "$first" -eq 1 ]; then
                cat "$OUTTABLE" > {output}/outTable_merged
                first=0
            else
                tail -n +2 "$OUTTABLE" >> {output}/outTable_merged
            fi
        done
        """


rule reditools_redinet_bgzip:
    # Step 2: bgzip + tabix the outTable file (bgzip and tabix live in reditools2.sif).
    # Locates the single outTable_* file in the raw directory and produces a
    # predictably named .gz for REDInet to consume.
    input:
        rawdir="results/tools/{aligner}/reditools_redinet/{condition}_{sample}_raw/"
    output:
        gz="results/tools/{aligner}/reditools_redinet/{condition}_{sample}/{condition}_{sample}.output.gz",
        tbi="results/tools/{aligner}/reditools_redinet/{condition}_{sample}/{condition}_{sample}.output.gz.tbi"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("reditools")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.reditools_redinet_bgzip.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.reditools_redinet_bgzip.err"
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.gz})"
        OUTTABLE=$(find {input.rawdir} -name "outTable_*" | head -1)
        test -n "$OUTTABLE" || {{ echo "No outTable_* file found in {input.rawdir}" >&2; exit 1; }}
        bgzip -c "$OUTTABLE" > {output.gz} 2> {log.stderr}
        tabix -s 1 -b 2 -e 2 -S 1 {output.gz} 2>> {log.stderr}
        echo "done" > {log.stdout}
        """


rule redinet:
    # Step 3: classify A-to-I editing sites with REDInet_Inference_light_ver.py.
    # -r takes the tabix-indexed .gz file directly; -o is the output prefix.
    input:
        gz="results/tools/{aligner}/reditools_redinet/{condition}_{sample}/{condition}_{sample}.output.gz",
        tbi="results/tools/{aligner}/reditools_redinet/{condition}_{sample}/{condition}_{sample}.output.gz.tbi"
    output:
        predictions="results/tools/{aligner}/redinet/{condition}_{sample}.predictions.tsv",
        features="results/tools/{aligner}/redinet/{condition}_{sample}.feature_vectors.tsv",
        params_tsv="results/tools/{aligner}/redinet/{condition}_{sample}.REDInet_ligth_ver_parameters.tsv"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("redinet")
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.redinet.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.redinet.err"
    params:
        prefix=lambda wildcards: f"results/tools/{wildcards.aligner}/redinet/{wildcards.condition}_{wildcards.sample}",
        cov=config["params"]["redinet"]["cov_threshold"],
        agfreq=config["params"]["redinet"]["agfreq_threshold"],
        min_ag=config["params"]["redinet"]["min_ag_subs"]
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.predictions})"
        /opt/conda/envs/REDInet/bin/python \
            /app/REDInet/Package/Utilities/REDInet_Inference_light_ver.py \
            -r {input.gz} \
            -o {params.prefix} \
            -c {params.cov} \
            -f {params.agfreq} \
            -s {params.min_ag} \
            1> {log.stdout} 2> {log.stderr} || \
        {{
            echo "REDInet produced no candidates (EmptyDataError); creating empty outputs" >> {log.stdout}
            touch {output.predictions} {output.features} {output.params_tsv}
        }}
        """


# ---------------------------------------------------------
# MARINE Rule (disabled — outputs too large for compare_all_tools matrix)
# ---------------------------------------------------------
# rule marine:
#     # Uses env-modules (no container yet; Dockerfile is in containers/marine/).
#     # Requires MD-tagged BAM produced by add_md_tag, and a gene annotation BED6
#     # generated by generate_marine_annotation in references.smk.
#     input:
#         bam="results/mapped/{aligner}/{condition}_{sample}.rmdup_MD.bam",
#         bai="results/mapped/{aligner}/{condition}_{sample}.rmdup_MD.bam.bai",
#         annotation=config["references"]["marine_annotation_bed"]
#     output:
#         "results/tools/{aligner}/marine/{condition}_{sample}/final_filtered_site_info.tsv"
#     threads: 4
#     resources:
#         mem_mb=lambda wildcards, attempt: 64000 * (1.5 ** (attempt - 1)),
#         runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
#     envmodules:
#         "marine"
#     log:
#         stdout="results/logs/{aligner}_{condition}_{sample}.marine.out",
#         stderr="results/logs/{aligner}_{condition}_{sample}.marine.err"
#     params:
#         outdir=lambda wildcards: f"results/tools/{wildcards.aligner}/marine/{wildcards.condition}_{wildcards.sample}",
#         strandedness=config["params"]["marine"]["strandedness"],
#         paired_end_flag="--paired_end" if config["params"]["marine"].get("paired_end", True) else ""
#     shell:
#         r"""
#         set -euo pipefail
#         rm -rf {params.outdir}
#         marine.py \
#             --bam_filepath {input.bam} \
#             --output_folder {params.outdir} \
#             --strandedness {params.strandedness} \
#             --annotation_bedfile_path {input.annotation} \
#             {params.paired_end_flag} \
#             --cores {threads} \
#             1> {log.stdout} 2> {log.stderr}
#         """
