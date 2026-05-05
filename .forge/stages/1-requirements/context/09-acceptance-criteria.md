# Acceptance Criteria (Full List with Resource Defaults)

## Structural AC

- AC-1: `snakemake --lint` on `pipelines/Morales_et_all/Snakefile` exits 0 with no errors. [FR-1, NFR-1]
- AC-2: `snakemake -n` from `pipelines/Morales_et_all/` exits 0. [FR-2, FR-4, NFR-2]
- AC-3: `grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/` returns no matches. [FR-3, SEC-1]
- AC-4: `grep -rn "container:" pipelines/Morales_et_all/*.smk | wc -l` == 14. [FR-4]
- AC-5: `grep -rn "^    log:" pipelines/Morales_et_all/*.smk | wc -l` == 14. [FR-5]
- AC-6: `grep -rn "^    resources:" pipelines/Morales_et_all/*.smk | wc -l` == 14. [FR-6]
- AC-7: `grep "set -euo pipefail" pipelines/Morales_et_all/tools.smk` finds the bcftools rule block. [FR-7]
- AC-8: `grep "java -jar" pipelines/Morales_et_all/preprocessing.smk` returns no matches. [FR-8]
- AC-9: `grep "params.script\|params.sprint_bin\|params.jacusa_jar\|params.samtools_bin" pipelines/Morales_et_all/*.smk` returns no matches. [FR-9, FR-10, FR-11, FR-12]
- AC-10: `grep "python Downstream/" pipelines/Morales_et_all/downstream.smk` returns no matches. [FR-13]
- AC-11: `grep "downstream_scripts_dir" pipelines/Morales_et_all/config.yaml` == 1 match. [FR-14]
- AC-12: `test -f containers/star/Dockerfile && test -f containers/star/validate.sh` exits 0. [FR-15]
- AC-13: `test -f containers/red_ml/Dockerfile && test -f containers/red_ml/validate.sh` exits 0. [FR-16]
- AC-14: `test -f containers/fastx/Dockerfile && test -f containers/fastx/validate.sh` exits 0. [FR-17]
- AC-15: `test -f containers/morales_downstream/Dockerfile && test -f containers/morales_downstream/validate.sh` exits 0. [FR-18]
- AC-16: `grep "container_for" pipelines/Morales_et_all/Snakefile` finds the function definition. [FR-1]
- AC-17: `add_md_tag` rule in tools.smk uses `container_for("wgs")`. [FR-20]

## Resource Default Table (per rule)

These values must appear in `resources:` blocks of each rule:

| Rule | mem_mb | runtime (minutes) | Notes |
|------|--------|-------------------|-------|
| trim_reads | 4000 | 30 | Light CPU-bound |
| star_mapping | 32000 | 120 | Memory-intensive genome loading |
| mark_duplicates | 8000 | 30 | I/O-bound |
| reditools | 8000 | 120 | Multi-threaded, moderate memory |
| sprint | 12000 | 240 | Slow per-sample run |
| bcftools | 4000 | 60 | Streaming, low memory |
| red_ml | 16000 | 120 | R + ML in-memory |
| add_md_tag | 4000 | 30 | Simple streaming |
| jacusa2 | 32000 | 60 | Aggregates 6 BAMs; memory peak |
| run_downstream_parsers | 4000 | 60 | Python scripts |
| update_alu | 4000 | 60 | Python script |
| individual_analysis | 4000 | 60 | Python script |
| reanalysis_multiple | 4000 | 60 | Python script |
| multiple_analysis | 4000 | 60 | Python script |

Resources must use exponential backoff pattern:
```python
resources:
    mem_mb=lambda wildcards, attempt: <base> * (1.5 ** (attempt - 1)),
    runtime=lambda wildcards, attempt: <base_minutes> * (2 ** (attempt - 1))
```

## Dockerfile Quality AC

- Each Dockerfile must have at least one LABEL directive (title and description)
- Each validate.sh must be executable (`chmod +x`) and exit 0 when run inside its container
- Each validate.sh must check that the primary tool executable exists and responds (using `--version`, `--help`, or equivalent)
- Container WORKDIR must be `/work`
