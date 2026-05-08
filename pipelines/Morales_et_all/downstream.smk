rule run_downstream_parsers:
    input:
        reditools=expand("results/tools/reditools/{condition}_{sample}.output", condition=config["conditions"], sample=config["samples"]),
        sprint=expand("results/tools/sprint/{condition}_{sample}_output", condition=config["conditions"], sample=config["samples"]),
        redml=expand("results/tools/red_ml/{condition}_{sample}_output", condition=config["conditions"], sample=config["samples"]),
        bcftools=expand("results/tools/bcftools/{condition}_{sample}.bcf", condition=config["conditions"], sample=config["samples"]),
        jacusa="results/tools/jacusa2/Jacusa.out"
    output:
        touch("results/downstream/parsers.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/run_downstream_parsers.out",
        stderr="results/logs/run_downstream_parsers.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        db_path=config["references"]["db_path"]
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}

        # Build staging directories expected by Downstream scripts:
        # each script uses path = "../TOOL" relative to Downstream/
        BENCH_DIR="{params.downstream_dir}/.."
        rm -rf "$BENCH_DIR/REDItools2" "$BENCH_DIR/SPRINT" "$BENCH_DIR/REDML" \
               "$BENCH_DIR/BCFTools" "$BENCH_DIR/JACUSA2"
        mkdir -p "$BENCH_DIR/REDItools2/star" "$BENCH_DIR/SPRINT/star" \
                 "$BENCH_DIR/REDML/star" "$BENCH_DIR/BCFTools/star" "$BENCH_DIR/JACUSA2/star"

        # REDItools2: symlink outputs with the _filt_sortrmdup suffix REDItools2.py expects
        for f in results/tools/reditools/*.output; do
            base=$(basename "$f" .output)
            ln -sf "$WORKDIR/$f" "$BENCH_DIR/REDItools2/star/${{base}}_filt_sortrmdup.output"
        done

        # SPRINT: symlink output dirs with the _filt_sortrmdup_output suffix SPRINT.py expects
        for d in results/tools/sprint/*_output; do
            base=$(basename "$d")
            ln -sf "$WORKDIR/$d" "$BENCH_DIR/SPRINT/star/${{base%_output}}_filt_sortrmdup_output"
        done

        # REDML: symlink output dirs with identical naming (REDML.py expects CONDITION_CLONE_output)
        for d in results/tools/red_ml/*_output; do
            ln -sf "$WORKDIR/$d" "$BENCH_DIR/REDML/star/$(basename $d)"
        done

        # BCFtools: convert BCF to VCF; vcf2bed conversion is done in Python by BCFtools.py
        for f in results/tools/bcftools/*.bcf; do
            base=$(basename "$f" .bcf)
            bcftools view "$f" > "$BENCH_DIR/BCFTools/star/${{base}}.vcf"
        done

        # JACUSA2: link raw output; per-score-threshold preprocessing is done by JACUSA2.py
        ln -sf "$WORKDIR/results/tools/jacusa2/Jacusa.out" "$BENCH_DIR/JACUSA2/star/Jacusa.out"

        # Scripts write JSON output to ../ relative to Downstream/, so use absolute log paths
        LOG_OUT="$WORKDIR/{log.stdout}"
        LOG_ERR="$WORKDIR/{log.stderr}"

        cd {params.downstream_dir}
        python REDItools2.py 1>> "$LOG_OUT" 2>> "$LOG_ERR"
        python SPRINT.py    1>> "$LOG_OUT" 2>> "$LOG_ERR"
        python REDML.py     1>> "$LOG_OUT" 2>> "$LOG_ERR"
        python BCFtools.py  1>> "$LOG_OUT" 2>> "$LOG_ERR"
        python JACUSA2.py   1>> "$LOG_OUT" 2>> "$LOG_ERR"
        """


rule update_alu:
    input:
        "results/downstream/parsers.done"
    output:
        touch("results/downstream/alu_updated.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/update_alu.out",
        stderr="results/logs/update_alu.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        db_path=config["references"]["db_path"]
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        cd {params.downstream_dir}
        python Alu.py 1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """


rule individual_analysis:
    input:
        "results/downstream/alu_updated.done"
    output:
        touch("results/downstream/individual_analysis.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/individual_analysis.out",
        stderr="results/logs/individual_analysis.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        cd {params.downstream_dir}
        python Individual-Analysis.py 1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """


rule reanalysis_multiple:
    input:
        "results/downstream/individual_analysis.done"
    output:
        touch("results/downstream/reanalysis_multiple.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 120 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/reanalysis_multiple.out",
        stderr="results/logs/reanalysis_multiple.err"
    params:
        downstream_dir=config["downstream_scripts_dir"],
        db_path=config["references"]["db_path"]
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        export DB_PATH={params.db_path}
        cd {params.downstream_dir}
        python Re-Analysis-Multiple.py 1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """


rule multiple_analysis:
    input:
        "results/downstream/reanalysis_multiple.done"
    output:
        touch("results/downstream/multiple_analysis.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/multiple_analysis.out",
        stderr="results/logs/multiple_analysis.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        WORKDIR=$(pwd)
        cd {params.downstream_dir}
        python Multiple-Analysis.py 1> "$WORKDIR/{log.stdout}" 2> "$WORKDIR/{log.stderr}"
        """
