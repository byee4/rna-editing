# ─────────────────────────────────────────────────────────────────────────────
# Differential (two-condition) editing tools — LoDEI and REDITs (spec DD2/DD3).
# Both are gated and live under results/differential_editing/ (REDITs) or
# results/tools/{aligner}/lodei/ (LoDEI), separate from the per-sample matrices.
#   REDITs : enabled whenever jacusa2_comparison is set (condition1/condition2 reused).
#   LoDEI  : enabled by a separate optional `lodei_comparison` block (DD2).
# ─────────────────────────────────────────────────────────────────────────────
_DIFF_SCRIPTS = os.path.join(workflow.basedir, "scripts")


# ---- REDITs (statistical differential test on integer counts; DD3 / DD3a) ----
def _redits_sample_names():
    return [f"{cond}_{samp}"
            for cond in (_JAC_C1, _JAC_C2) for samp in config["samples"]]


def _redits_groups():
    return ",".join(cond
                    for cond in (_JAC_C1, _JAC_C2) for samp in config["samples"])


def _redits_caller_outputs(wildcards):
    # REDItools per-sample outputs for both comparison conditions, in column order.
    return [
        f"results/tools/{wildcards.aligner}/reditools/{cond}_{samp}.output"
        for cond in (_JAC_C1, _JAC_C2) for samp in config["samples"]
    ]


rule build_redits_counts:
    """Build the per-site integer edited/total matrix from the chosen caller's native
    count columns (DD3a — never fraction*coverage)."""
    input:
        _redits_caller_outputs
    output:
        temp("results/differential_editing/redits/{aligner}/counts_" + _REDITS_CALLER + ".tsv")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
    container: container_for("reditools")
    params:
        script=os.path.join(_DIFF_SCRIPTS, "build_redits_counts.py"),
        names=" ".join(_redits_sample_names()),
        caller=_REDITS_CALLER
    log:
        stdout="results/logs/{aligner}.build_redits_counts.out",
        stderr="results/logs/{aligner}.build_redits_counts.err"
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output})"
        python3 {params.script} --inputs {input} --sample-names {params.names} \
            --caller {params.caller} --output {output} \
            1> {log.stdout} 2> {log.stderr}
        """


rule redits_llr:
    """Run REDIT-LLR (beta-binomial differential-editing test) per site."""
    input:
        "results/differential_editing/redits/{aligner}/counts_" + _REDITS_CALLER + ".tsv"
    output:
        "results/differential_editing/redits/{aligner}/redit_llr_" + _REDITS_CALLER + ".tsv.gz"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("redits")
    params:
        tmpdir=config.get("tmpdir", "/tmp"),
        groups=_redits_groups()
    log:
        stdout="results/logs/{aligner}.redits_llr.out",
        stderr="results/logs/{aligner}.redits_llr.err"
    shell:
        r"""
        set -euo pipefail
        export TMPDIR={params.tmpdir}
        tmp="$(mktemp -p {params.tmpdir})"
        Rscript /opt/redits/redits_llr.R \
            --counts {input} --groups {params.groups} --output "$tmp" \
            1> {log.stdout} 2> {log.stderr}
        gzip -c "$tmp" > {output}
        rm -f "$tmp"
        """


# ---- LoDEI (windowed two-group differential editing; DD2) --------------------
if _RUN_LODEI:

    def _lodei_bams(wildcards, condition):
        return [
            f"results/mapped/{wildcards.aligner}/{condition}_{samp}.rmdup.bam"
            for samp in config["samples"]
        ]

    def _lodei_bais(wildcards, condition):
        return [b + ".bai" for b in _lodei_bams(wildcards, condition)]

    rule lodei:
        """LoDEI 'find': differential editing between two BAM groups (condition1 vs
        condition2). Output is a directory of differentially edited regions."""
        input:
            group1=lambda w: _lodei_bams(w, _LODEI_C1),
            group2=lambda w: _lodei_bams(w, _LODEI_C2),
            bai1=lambda w: _lodei_bais(w, _LODEI_C1),
            bai2=lambda w: _lodei_bais(w, _LODEI_C2),
            fasta="results/references/ref_iupac_masked.fasta",
            fai="results/references/ref_iupac_masked.fasta.fai",
            gff=config["references"]["gtf"]
        output:
            directory("results/tools/{aligner}/lodei/" + _LODEI_C1 + "_vs_" + _LODEI_C2)
        threads: 4
        resources:
            mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
            runtime=lambda wildcards, attempt: 240 * (1.5 ** (attempt - 1))
        container: container_for("lodei")
        params:
            tmpdir=config.get("tmpdir", "/tmp"),
            window=config.get("params", {}).get("lodei", {}).get("window_size", 25),
            min_coverage=config["params"]["common"]["min_coverage"],
            library=config.get("params", {}).get("lodei", {}).get("library", "SR")
        log:
            stdout="results/logs/{aligner}.lodei.out",
            stderr="results/logs/{aligner}.lodei.err"
        shell:
            r"""
            set -euo pipefail
            export TMPDIR={params.tmpdir}
            export MPLCONFIGDIR="$(mktemp -d -p {params.tmpdir})"
            mkdir -p {output}
            lodei find \
                -a {input.group1} -b {input.group2} \
                -f {input.fasta} -g {input.gff} -o {output} \
                -c {threads} -w {params.window} -m {params.min_coverage} \
                -l {params.library} \
                1> {log.stdout} 2> {log.stderr}
            """
