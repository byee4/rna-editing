# Task 05: Containerize downstream.smk (5 rules)

<!-- DEPENDENCIES: 02 -->
<!-- LABELS: phase-3, stage:3-implement, smk-edit -->
<!-- VERIFIES: AC-4 (14/14), AC-5 (14/14), AC-6 (14/14), AC-10, FR-4, FR-5, FR-6, FR-13, SEC-1 -->

## Goal

Fully rewrite `pipelines/Morales_et_all/downstream.smk` to add `container:`, `log:`, and `resources:` directives to all 5 rules, replace all bare `python Downstream/...` calls with `python {params.downstream_dir}/...` using the config-sourced `downstream_scripts_dir` key, and route execution through the `morales_downstream` container.

## Files Modified

- `pipelines/Morales_et_all/downstream.smk`

## Full Rewritten File

Replace the entire file content with:

```python
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
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
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
        downstream_dir=config["downstream_scripts_dir"]
    shell:
        r"""
        set -euo pipefail
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
```

## Acceptance Criteria

- [ ] `grep -c "^rule " pipelines/Morales_et_all/downstream.smk` returns `5`
- [ ] `grep -c "    container: container_for" pipelines/Morales_et_all/downstream.smk` returns `5`
- [ ] `grep -c "^    log:" pipelines/Morales_et_all/downstream.smk` returns `5`
- [ ] `grep -c "^    resources:" pipelines/Morales_et_all/downstream.smk` returns `5`
- [ ] `grep -c "set -euo pipefail" pipelines/Morales_et_all/downstream.smk` returns `5`
- [ ] `grep "python Downstream/" pipelines/Morales_et_all/downstream.smk` returns no matches (PASS)
- [ ] `grep -c "downstream_dir" pipelines/Morales_et_all/downstream.smk` returns `10` (5 params: definitions + 5 shell uses per rule, `run_downstream_parsers` has 5 python calls)
- [ ] `grep 'container_for("morales_downstream")' pipelines/Morales_et_all/downstream.smk` returns `5` matches
- [ ] `python -c "import ast; ast.parse(open('pipelines/Morales_et_all/downstream.smk').read())"` exits 0
- [ ] No other file is modified

## Verification

```bash
grep -c "^rule \|container: container_for\|^    log:\|^    resources:\|set -euo pipefail" pipelines/Morales_et_all/downstream.smk
grep "python Downstream/" pipelines/Morales_et_all/downstream.smk || echo "PASS: no bare Downstream/ paths"
python -c "import ast; ast.parse(open('pipelines/Morales_et_all/downstream.smk').read()); print('syntax OK')"
```

## Notes

- All 5 rules use `container_for("morales_downstream")` — the new `morales_downstream.sif` built in Task 08.
- `params.downstream_dir` is local to each rule per D-9. This avoids adding a global var to the Snakefile header.
- `run_downstream_parsers` uses `1>>` / `2>>` (append mode) because it calls 5 separate python subprocesses in sequence; append collects all output in one log pair.
- The remaining 4 downstream rules use `1>` / `2>` (overwrite) since each invokes a single script.
- Log paths use literal rule names (no wildcards) because these are aggregate rules with no sample-level wildcards — per EC-6.
- After this task, the running count of containerized rules is 3 (preprocessing) + 6 (tools) + 5 (downstream) = **14/14** (AC-4 fully satisfied).
