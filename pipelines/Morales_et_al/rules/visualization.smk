"""
visualization.smk — BigWig, BigBed, trackhub, and cross-tool comparison rules.

Rules defined here:
  get_chrom_sizes           derive chrom.sizes from reference FASTA index
  bam_to_bigwig             bamCoverage (deeptools) → .bw per BAM
  tool_output_to_bed        convert each tool's output to BED6
  sort_and_bigbed           sort BED + bedToBigBed → .bb
  compare_all_tools         build coverage/fraction/score matrices
  tool_correlation          Spearman correlation among tools (per aligner)
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
    "marine":     "{condition}_{sample}/final_filtered_site_info.tsv",
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
        script=os.path.join(_VIZ_SCRIPTS, "tool_output_to_bed.py")
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        module load python3essential
        python3 {params.script} \
            --tool {wildcards.tool} \
            --input {input} \
            --output {output} \
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
        "ucsc-tools"
    log:
        stderr="results/logs/{tool}_{aligner}_{condition}_{sample}.bigbed.err"
    shell:
        r"""
        set -euo pipefail
        if [ ! -s {input.bed} ]; then
            # bedToBigBed requires at least one record; write a dummy if empty
            echo "chr1\t0\t1\t.\t0\t." > {input.bed}
        fi
        bedToBigBed -type=bed6 {input.bed} {input.sizes} {output} 2> {log.stderr}
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
        samples=" ".join(config["samples"])
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
            1> {log.stdout} 2> {log.stderr}
        """


# ---------------------------------------------------------------------------
# Rule: tool_correlation
# ---------------------------------------------------------------------------
rule tool_correlation:
    """Pairwise Spearman correlation among tools (one matrix per aligner)."""
    input:
        "results/compare_all_tools/edit_fraction_matrix.tsv"
    output:
        expand(
            "results/correlation/tool_correlation_{aligner}.tsv",
            aligner=_ALIGNERS
        )
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 8000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/tool_correlation.out",
        stderr="results/logs/tool_correlation.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "tool_correlation.py"),
        outdir="results/correlation",
        aligners=" ".join(_ALIGNERS)
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --matrix-dir results/compare_all_tools \
            --outdir {params.outdir} \
            --aligners {params.aligners} \
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
