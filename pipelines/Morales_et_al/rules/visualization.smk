"""
visualization.smk — BigWig, BigBed, trackhub, and cross-tool comparison rules.

Rules defined here:
  get_chrom_sizes           derive chrom.sizes from reference FASTA index
  bam_to_bigwig             bamCoverage (deeptools) → .bw per BAM
  tool_output_to_bed        convert each tool's output to BED6
  sort_and_bigbed           sort BED + bedToBigBed → .bb
  compare_all_tools         build coverage/fraction/score matrices
  compare_outputs           intersection co-call table + per-output-type correlation
  consensus_characteristics intersection-vs-outersection characteristics + anticorrelation
  aligner_correlation       Spearman correlation among aligners (per tool)
  make_trackhub             assemble UCSC trackhub from BigWig + BigBed

All Python analysis scripts use:  module load python3essential
BigWig generation uses:           module load deeptools
BigBed conversion uses:           module load ucsc-tools (for bedToBigBed)
"""

import os

# ---------------------------------------------------------------------------
# Helper: path to our own analysis scripts
# ---------------------------------------------------------------------------
# workflow.basedir is the directory containing the top-level Snakefile;
# for this pipeline that is pipelines/Morales_et_al/.
_VIZ_SCRIPTS = os.path.join(workflow.basedir, "scripts")

# _BED_TOOLS and _ALIGNERS are defined in the top-level Snakefile and are
# available here via Snakemake's shared include namespace.

# Tool-dir mapping (matches locate_tool_output logic in compare_all_tools.py)
_TOOL_DIR = {
    "reditools":  "reditools",
    "reditools2": "reditools",
    "reditools3": "reditools3",
    "sprint":     "sprint",
    "red_ml":     "red_ml",
    "redml":      "red_ml",
    "bcftools":   "bcftools",
    "redinet":    "redinet",
    "jacusa2_call1": "jacusa2_call1",
    "marine":     "marine",
}

# Tool-output filename/dir relative to results/tools/{aligner}/{tool_dir}/
_TOOL_OUTPUT = {
    "reditools":  "{condition}_{sample}.output",
    "reditools2": "{condition}_{sample}.output",
    "reditools3": "{condition}_{sample}.txt",
    "sprint":     "{condition}_{sample}_output",
    "red_ml":     "{condition}_{sample}_output",
    "redml":      "{condition}_{sample}_output",
    "bcftools":   "{condition}_{sample}.bcf",
    "redinet":    "{condition}_{sample}.predictions.tsv",
    "jacusa2_call1": "{condition}_{sample}.out",
    # MARINE: edit-type-filtered TSV; edit type baked into the filename (see
    # filter_marine_by_edit_type in rules/tools.smk).
    "marine":     "{condition}_{sample}/final_filtered_site_info." + config["params"]["common"]["edit_type"] + ".tsv",
}


def _tool_output_path(tool, aligner, condition, sample):
    tool_dir = _TOOL_DIR.get(tool, tool)
    tmpl = _TOOL_OUTPUT.get(tool, f"{{condition}}_{{sample}}.output")
    fname = tmpl.format(condition=condition, sample=sample)
    return f"results/tools/{aligner}/{tool_dir}/{fname}"


# ---------------------------------------------------------------------------
# Rule: chrom.sizes
# ---------------------------------------------------------------------------
rule get_chrom_sizes:
    """Derive chromosome sizes from the reference FASTA .fai index."""
    input:
        fai=config["references"]["fasta"] + ".fai"
    output:
        "results/reference/chrom.sizes"
    localrule: True
    shell:
        "cut -f1,2 {input.fai} > {output}"


# ---------------------------------------------------------------------------
# Rule: bam → bigwig
# ---------------------------------------------------------------------------
rule bam_to_bigwig:
    """CPM-normalised coverage BigWig for each alignment BAM."""
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
        bai="results/mapped/{aligner}/{condition}_{sample}.rmdup.bam.bai"
    output:
        "results/bigwig/{aligner}/{condition}_{sample}.bw"
    threads: 4
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    envmodules:
        "deeptools"
    log:
        stdout="results/logs/{aligner}_{condition}_{sample}.bigwig.out",
        stderr="results/logs/{aligner}_{condition}_{sample}.bigwig.err"
    params:
        binsize=config.get("visualization", {}).get("bigwig_binsize", 10)
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        bamCoverage \
            --bam {input.bam} \
            --outFileName {output} \
            --outFileFormat bigwig \
            --binSize {params.binsize} \
            --normalizeUsing CPM \
            --numberOfProcessors {threads} \
            1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: tool output → sorted BED6
# ---------------------------------------------------------------------------
rule tool_output_to_bed:
    """Convert a single tool's per-sample output to sorted BED6."""
    input:
        lambda wc: _tool_output_path(wc.tool, wc.aligner, wc.condition, wc.sample)
    output:
        temp("results/bigbed/{tool}/{aligner}/{condition}_{sample}.unsorted.bed")
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    log:
        stderr="results/logs/{tool}_{aligner}_{condition}_{sample}.to_bed.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "tool_output_to_bed.py"),
        min_cov=config.get("visualization", {}).get("bigbed_min_cov", 0),
        min_score=config.get("visualization", {}).get("bigbed_min_score", 0),
        jacusa2_call1_filter=config.get("params", {}).get("jacusa2", {}).get("call1_filter", "edit_type")
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        module load python3essential
        python3 {params.script} \
            --tool {wildcards.tool} \
            --input {input} \
            --output {output} \
            --min-cov {params.min_cov} \
            --min-score {params.min_score} \
            --jacusa2-call1-filter {params.jacusa2_call1_filter} \
            2> {log.stderr}
        """


rule sort_bed:
    """Sort BED by chrom then position."""
    input:
        "results/bigbed/{tool}/{aligner}/{condition}_{sample}.unsorted.bed"
    output:
        temp("results/bigbed/{tool}/{aligner}/{condition}_{sample}.sorted.bed")
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=10
    shell:
        "sort -k1,1 -k2,2n {input} > {output}"


rule sort_and_bigbed:
    """Convert sorted BED6 to BigBed using bedToBigBed."""
    input:
        bed="results/bigbed/{tool}/{aligner}/{condition}_{sample}.sorted.bed",
        sizes="results/reference/chrom.sizes"
    output:
        "results/bigbed/{tool}/{aligner}/{condition}_{sample}.bb"
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    envmodules:
        "ucsctools"
    log:
        stderr="results/logs/{tool}_{aligner}_{condition}_{sample}.bigbed.err"
    shell:
        r"""
        set -euo pipefail
        module load ucsctools
        if [ ! -s {input.bed} ]; then
            # bedToBigBed requires at least one record; write a dummy if empty
            printf "chr1\t0\t1\t.\t0\t.\n" > {input.bed}
        fi
        bedToBigBed -type=bed3+3 {input.bed} {input.sizes} {output} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: compare_all_tools  (matrix generation)
# ---------------------------------------------------------------------------
def _all_tool_outputs(wildcards):
    """Collect all tool outputs that feed into the comparison matrices."""
    inputs = []
    for tool in _BED_TOOLS:
        for aligner in _ALIGNERS:
            for condition in config["conditions"]:
                for sample in config["samples"]:
                    inputs.append(
                        _tool_output_path(tool, aligner, condition, sample)
                    )
    return inputs


rule compare_all_tools:
    """Build position × sample matrices (coverage, fraction, score) for all tools."""
    input:
        _all_tool_outputs
    output:
        coverage="results/compare_all_tools/edit_coverage_matrix.tsv",
        fraction="results/compare_all_tools/edit_fraction_matrix.tsv",
        score="results/compare_all_tools/tool_score_matrix.tsv"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/compare_all_tools.out",
        stderr="results/logs/compare_all_tools.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "compare_all_tools.py"),
        outdir="results/compare_all_tools",
        tools=" ".join(_BED_TOOLS + ["jacusa2"]),
        aligners=" ".join(_ALIGNERS),
        conditions=" ".join(config["conditions"]),
        samples=" ".join(config["samples"]),
        edit_type=config["params"]["common"]["edit_type"],
        jacusa2_call1_filter=config.get("params", {}).get("jacusa2", {}).get("call1_filter", "edit_type")
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --results-dir results/ \
            --outdir {params.outdir} \
            --tools {params.tools} \
            --aligners {params.aligners} \
            --conditions {params.conditions} \
            --samples {params.samples} \
            --edit-type {params.edit_type} \
            --jacusa2-call1-filter {params.jacusa2_call1_filter} \
            1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: compare_outputs
# ---------------------------------------------------------------------------
# Replaces the old mixed tool_correlation heatmap. Produces, per aligner:
#   - intersect/  : co-called edit table + all-tool Jaccard / overlap counts
#   - by_output_type/ : one intersection-Spearman heatmap per OUTPUT TYPE,
#                       comparing only tools that produce that quantity.
rule compare_outputs:
    """Intersection co-call table + per-output-type correlation plots."""
    input:
        fraction="results/compare_all_tools/edit_fraction_matrix.tsv",
        score="results/compare_all_tools/tool_score_matrix.tsv",
        coverage="results/compare_all_tools/edit_coverage_matrix.tsv"
    output:
        expand("results/correlation/intersect/edits_intersect_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/intersect/tool_jaccard_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/per-site-fraction-correlation_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/per-gene-fraction-correlation_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/qual-or-score-correlation_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/read-count-correlation_{aligner}.tsv", aligner=_ALIGNERS)
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 12000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 90 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/compare_outputs.out",
        stderr="results/logs/compare_outputs.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "compare_outputs.py"),
        outdir="results/correlation",
        aligners=" ".join(_ALIGNERS),
        gtf=config["references"]["gtf"],
        edit_type=config.get("params", {}).get("common", {}).get("edit_type", "AG"),
        min_tools=config.get("params", {}).get("common", {}).get("min_tools", 2)
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --matrix-dir results/compare_all_tools \
            --outdir {params.outdir} \
            --aligners {params.aligners} \
            --gtf {params.gtf} \
            --edit-type {params.edit_type} \
            --min-tools {params.min_tools} \
            1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: consensus_characteristics
# ---------------------------------------------------------------------------
# Stratifies edit characteristics (coverage, fraction, score/p-value) by how
# many tools called each site/gene: outersection (=1 tool) vs intersection
# (>=2, >=3, ... all). Also emits a gene-level anticorrelation diagnostic that
# explains pairs like red_ml vs MARINE (disjoint sites within shared genes).
rule consensus_characteristics:
    """Intersection-vs-outersection characteristic comparison + anticorrelation diagnostic."""
    input:
        fraction="results/compare_all_tools/edit_fraction_matrix.tsv",
        score="results/compare_all_tools/tool_score_matrix.tsv",
        coverage="results/compare_all_tools/edit_coverage_matrix.tsv"
    output:
        expand("results/consensus/site_characteristics_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/consensus/gene_characteristics_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/consensus/anticorrelation_gene_fraction_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/consensus/consensus_report_{aligner}.md", aligner=_ALIGNERS)
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 12000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 90 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/consensus_characteristics.out",
        stderr="results/logs/consensus_characteristics.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "consensus_characteristics.py"),
        outdir="results/consensus",
        aligners=" ".join(_ALIGNERS),
        gtf=config["references"]["gtf"],
        edit_type=config.get("params", {}).get("common", {}).get("edit_type", "AG")
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --matrix-dir results/compare_all_tools \
            --outdir {params.outdir} \
            --aligners {params.aligners} \
            --gtf {params.gtf} \
            --edit-type {params.edit_type} \
            1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: aligner_correlation
# ---------------------------------------------------------------------------
rule aligner_correlation:
    """Pairwise Spearman correlation among aligners (one matrix per tool)."""
    input:
        "results/compare_all_tools/edit_fraction_matrix.tsv"
    output:
        expand(
            "results/correlation/aligner_correlation_{tool}.tsv",
            tool=_BED_TOOLS
        )
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/aligner_correlation.out",
        stderr="results/logs/aligner_correlation.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "aligner_correlation.py"),
        outdir="results/correlation",
        aligners=" ".join(_ALIGNERS),
        tools=" ".join(_BED_TOOLS)
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --matrix-dir results/compare_all_tools \
            --outdir {params.outdir} \
            --aligners {params.aligners} \
            --tools {params.tools} \
            1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: make_trackhub
# ---------------------------------------------------------------------------
def _all_bigwig(wildcards):
    return expand(
        "results/bigwig/{aligner}/{condition}_{sample}.bw",
        aligner=_ALIGNERS,
        condition=config["conditions"],
        sample=config["samples"],
    )


def _all_bigbed(wildcards):
    return expand(
        "results/bigbed/{tool}/{aligner}/{condition}_{sample}.bb",
        tool=_BED_TOOLS,
        aligner=_ALIGNERS,
        condition=config["conditions"],
        sample=config["samples"],
    )


rule make_trackhub:
    """Assemble a UCSC trackhub from BigWig coverage and BigBed edit-site tracks."""
    input:
        bigwigs=_all_bigwig,
        bigbeds=_all_bigbed
    output:
        hub="results/trackhub/hub.txt",
        genomes="results/trackhub/genomes.txt"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=30
    log:
        stdout="results/logs/make_trackhub.out",
        stderr="results/logs/make_trackhub.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "make_trackhub.py"),
        outdir="results/trackhub",
        assembly=config.get("visualization", {}).get("ucsc_assembly", "hg38"),
        hub_name=config.get("visualization", {}).get("hub_name", "Morales_et_al RNA Editing"),
        email=config.get("visualization", {}).get("hub_email", "user@example.com"),
        aligners=" ".join(_ALIGNERS),
        tools=" ".join(_BED_TOOLS),
        conditions=" ".join(config["conditions"]),
        samples=" ".join(config["samples"])
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --bigwig-dir results/bigwig \
            --bigbed-dir results/bigbed \
            --outdir {params.outdir} \
            --assembly {params.assembly} \
            --hub-name "{params.hub_name}" \
            --email {params.email} \
            --aligners {params.aligners} \
            --tools {params.tools} \
            --conditions {params.conditions} \
            --samples {params.samples} \
            1> {log.stdout} 2> {log.stderr}
        """
