import os

# ---------------------------------------------------------------------------
# Reference file generation rules
# ---------------------------------------------------------------------------
# These rules regenerate derived reference files from their raw sources.
# Snakemake only runs them when the output is absent or stale.
# ---------------------------------------------------------------------------

rule generate_simple_repeat:
    """
    Convert raw UCSC simpleRepeat.txt to a sorted, merged BED file.
    Raw format columns: bin, chrom, chromStart, chromEnd, ...
    """
    input:
        config["references"]["simple_repeat_src"]
    output:
        config["references"]["simple_repeat"]
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/generate_simple_repeat.out",
        stderr="results/logs/generate_simple_repeat.err"
    shell:
        r"""
        set -euo pipefail
        awk '{{print $2"\t"$3"\t"$4}}' {input} \
            | bedtools sort \
            | bedtools merge \
            > {output} \
            2> {log.stderr}
        echo "done" > {log.stdout}
        """


rule generate_alu_bed:
    """
    Extract Alu-family elements from RepeatMasker rmsk.txt.gz and merge overlaps.
    rmsk.txt.gz columns: bin, swScore, milliDiv, milliDel, milliIns,
                      genoName, genoStart, genoEnd, genoLeft, strand,
                      repName, repClass, repFamily, ...
    genoName=col6, genoStart=col7, genoEnd=col8 (0-based half-open).
    """
    input:
        config["references"]["rmsk"]
    output:
        config["references"]["alu_bed"]
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("wgs")
    log:
        stdout="results/logs/generate_alu_bed.out",
        stderr="results/logs/generate_alu_bed.err"
    shell:
        r"""
        set -euo pipefail
        zcat {input} | grep Alu \
            | awk '{{print $6"\t"$7"\t"$8}}' \
            | sort -k1,1 -k2,2n \
            | bedtools merge \
            > {output} \
            2> {log.stderr}
        echo "done" > {log.stdout}
        """


if config.get("references", {}).get("hisat2_index"):
    _HISAT2_IDX = config["references"]["hisat2_index"]

    rule hisat2_extract_splice_sites:
        input:
            config["references"]["gtf"]
        output:
            _HISAT2_IDX + ".ss"
        threads: 1
        resources:
            mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
            runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
        container: container_for("hisat2")
        log:
            stdout="results/logs/hisat2_extract_splice_sites.out",
            stderr="results/logs/hisat2_extract_splice_sites.err"
        shell:
            r"""
            set -euo pipefail
            hisat2_extract_splice_sites.py {input} > {output} 2> {log.stderr}
            echo "done" > {log.stdout}
            """

    rule hisat2_extract_exons:
        input:
            config["references"]["gtf"]
        output:
            _HISAT2_IDX + ".exon"
        threads: 1
        resources:
            mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
            runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
        container: container_for("hisat2")
        log:
            stdout="results/logs/hisat2_extract_exons.out",
            stderr="results/logs/hisat2_extract_exons.err"
        shell:
            r"""
            set -euo pipefail
            hisat2_extract_exons.py {input} > {output} 2> {log.stderr}
            echo "done" > {log.stdout}
            """

    rule hisat2_genome_generate:
        input:
            fasta=config["references"]["fasta"],
            ss=_HISAT2_IDX + ".ss",
            exon=_HISAT2_IDX + ".exon"
        output:
            multiext(_HISAT2_IDX,
                     ".1.ht2", ".2.ht2", ".3.ht2", ".4.ht2",
                     ".5.ht2", ".6.ht2", ".7.ht2", ".8.ht2")
        threads: config["threads"]
        resources:
            mem_mb=lambda wildcards, attempt: 48000 * (1.5 ** (attempt - 1)),
            runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
        container: container_for("hisat2")
        log:
            stdout="results/logs/hisat2_genome_generate.out",
            stderr="results/logs/hisat2_genome_generate.err"
        params:
            idx_prefix=_HISAT2_IDX
        shell:
            r"""
            set -euo pipefail
            mkdir -p "$(dirname {params.idx_prefix})"
            hisat2-build --ss {input.ss} --exon {input.exon} \
                -p {threads} {input.fasta} {params.idx_prefix} \
                1> {log.stdout} 2> {log.stderr}
            """


rule generate_marine_annotation:
    """
    Convert GENCODE GTF to a gene-level BED6 file for MARINE annotation.
    Format: chrom  start(0-based)  end  gene_name  gene_type  strand
    """
    input:
        config["references"]["gtf"]
    output:
        config["references"]["marine_annotation_bed"]
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/generate_marine_annotation.out",
        stderr="results/logs/generate_marine_annotation.err"
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        grep -v "^#" {input} | awk '$3 == "gene"' | \
        gawk 'BEGIN{{OFS="\t"}} {{
            match($0, /gene_name "([^"]+)"/, gn)
            match($0, /gene_type "([^"]+)"/, gt)
            print $1, $4-1, $5, gn[1], gt[1], $7
        }}' | sort -k1,1 -k2,2n > {output} 2> {log.stderr}
        echo "done" > {log.stdout}
        """


rule build_dbrna_editing:
    """
    Build the three JSON databases consumed by the Morales et al. downstream
    analysis scripts (REDItools2.py, SPRINT.py, JACUSA2.py, etc.).

    Inputs
    ------
    hek_bed    : AG/TC variant BED from WGS alignment (generated by wgs.smk)
    rediportal : REDIportal tab-separated database (GRCh38)
    alu_bed    : Alu element BED (generated by generate_alu_bed)

    Outputs (in config["references"]["db_path"])
    --------------------------------------------
    HEK293T_hg38_clean.json
    REDIportal.json
    Alu_GRCh38.json
    """
    input:
        hek_bed=os.path.join(config["references"]["db_path"], "HEK293T_hg38.bed"),
        rediportal=config["references"]["rediportal_hg38"],
        alu_bed=config["references"]["alu_bed"]
    output:
        hek_json=os.path.join(config["references"]["db_path"], "HEK293T_hg38_clean.json"),
        rediportal_json=os.path.join(config["references"]["db_path"], "REDIportal.json"),
        alu_json=os.path.join(config["references"]["db_path"], "Alu_GRCh38.json")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/build_dbrna_editing.out",
        stderr="results/logs/build_dbrna_editing.err"
    params:
        script=os.path.normpath(os.path.join(workflow.basedir, "..", "..", "scripts", "build_downstream_dbs.py")),
        outdir=config["references"]["db_path"]
    shell:
        r"""
        set -euo pipefail
        python {params.script} \
            --hek-bed    {input.hek_bed} \
            --rediportal {input.rediportal} \
            --alu        {input.alu_bed} \
            --assembly   hg38 \
            --outdir     {params.outdir} \
            1> {log.stdout} 2> {log.stderr}
        """
