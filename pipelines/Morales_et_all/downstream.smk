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
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
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
        export DB_PATH={params.db_path}
        python {params.downstream_dir}/REDItools2.py 1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/SPRINT.py    1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/REDML.py     1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/BCFtools.py  1>> {log.stdout} 2>> {log.stderr}
        python {params.downstream_dir}/JACUSA2.py   1>> {log.stdout} 2>> {log.stderr}
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
        export DB_PATH={params.db_path}
        export DOWNSTREAM_WORKDIR=results/downstream
        python {params.downstream_dir}/Alu.py 1> {log.stdout} 2> {log.stderr}
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
        python {params.downstream_dir}/Individual-Analysis.py 1> {log.stdout} 2> {log.stderr}
        """


rule reanalysis_multiple:
    input:
        "results/downstream/individual_analysis.done"
    output:
        touch("results/downstream/reanalysis_multiple.done")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
    container: container_for("morales_downstream")
    log:
        stdout="results/logs/reanalysis_multiple.out",
        stderr="results/logs/reanalysis_multiple.err"
    params:
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
        python {params.downstream_dir}/Re-Analysis-Multiple.py 1> {log.stdout} 2> {log.stderr}
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
        python {params.downstream_dir}/Multiple-Analysis.py 1> {log.stdout} 2> {log.stderr}
        """
