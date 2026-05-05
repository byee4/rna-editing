# Edge Cases

## EC-1: Empty Git Submodule

**Scenario**: `Benchmark-of-RNA-Editing-Detection-Tools/` is an empty directory (submodule not initialized). A user runs `snakemake -n` without initializing the submodule.

**Impact**: Dry-run succeeds (Snakemake doesn't check if script files exist at planning time). Actual execution fails at `run_downstream_parsers` with "No such file or directory".

**Mitigation**:
- Add comment in `config.yaml` next to `downstream_scripts_dir`: `# Run: git submodule update --init`
- Downstream rules should have `log:` so the error surfaces in a log file, not just SLURM output
- Do NOT add a Snakemake `ancient()` or `checkpoints` mechanism to validate this — out of scope

## EC-2: STAR Intermediate File Cleanup

**Scenario**: The `star_mapping` rule deletes `{params.prefix}Aligned.sortedByCoord.out.bam` after processing. If STAR fails mid-run, the cleanup `rm` command may fail or leave partial files.

**Impact**: Rerunning may either succeed (if STAR re-creates the file) or fail (if Snakemake's mtime-based rerun detection triggers incorrectly).

**Mitigation**:
- `set -euo pipefail` at the top of the shell block ensures the `rm` never runs if a prior command fails
- This is handled by FR-7 (add pipefail)

## EC-3: Picard Wrapper vs JAR Direct Call

**Scenario**: The `mark_duplicates` rule currently calls `java -jar {params.picard}`. After containerization, it calls `picard MarkDuplicates`. The `picard` wrapper at `/usr/local/bin/picard` in the container does `exec java -jar /opt/picard/picard.jar "$@"`.

**Impact**: The command signature changes from `java -jar picard.jar MarkDuplicates INPUT=...` to `picard MarkDuplicates INPUT=...`. These are functionally equivalent but the shell call must be updated.

**Mitigation**: Explicitly call `picard MarkDuplicates INPUT=...` in the rule shell block. Remove `params.picard`.

## EC-4: `samtools calmd` Output Format

**Scenario**: The `add_md_tag` rule uses `samtools calmd {input.bam} {params.ref} > {output.bam}`. The default `samtools calmd` output is SAM, not BAM. If downstream tools require BAM, this is a bug.

**Impact**: `jacusa2` takes the `rmdup_MD.bam` as input; it calls `java -jar ... call-2` which supports both SAM and BAM input. Low risk.

**Decision**: Preserve current behavior (SAM-format output with `.bam` extension) to avoid breaking changes. If downstream tools fail, add `-b` flag to produce BAM. This is an existing behavior, not introduced by this task.

## EC-5: `jacusa2` Rule Has No Wildcards

**Scenario**: The `jacusa2` rule aggregates all samples and has no `{condition}` or `{sample}` wildcards. Its `log:` path must use literal names.

**Impact**: Log path cannot use `{condition}_{sample}` pattern used by all other rules.

**Resolution**: Use `results/logs/jacusa2.out` and `results/logs/jacusa2.err` (no wildcards in path).

## EC-6: Downstream Rules Have No Wildcards

**Scenario**: The 5 downstream rules (`run_downstream_parsers`, `update_alu`, etc.) have no wildcards. Log paths use rule names only.

**Resolution**: Use `results/logs/{rulename}.out` and `results/logs/{rulename}.err`.

## EC-7: RED-ML R Package Availability

**Scenario**: RED-ML requires specific R packages (`caret`, `data.table`, `ROCR`, `randomForest`). If the CRAN package archive URL changes or packages become unavailable, the Docker build fails.

**Mitigation**: Pin R package versions in the Dockerfile (e.g., `Rscript -e 'install.packages("caret", version="6.0-94", repos="https://cran.r-project.org")'`). Use `rocker/r-ver` base for stable R version.

## EC-8: FASTX-Toolkit Bioconda Availability

**Scenario**: The `fastx_toolkit` bioconda package may be unavailable for newer architectures (arm64/aarch64). TSCC uses x86_64, so this is low risk.

**Mitigation**: Use `--platform linux/amd64` in Docker build if building on non-x86 machine. Default to bioconda install; fall back to source compile if package unavailable.

## EC-9: `sprint` Rule — Python 2.7 in Container

**Scenario**: The SPRINT container uses `ubuntu:18.04` with Python 2.7. The `sprint_from_bam.py` script is Python 2. If someone updates the sprint container to Python 3, the script will break.

**Impact**: Not introduced by this task; existing behavior. The Morales pipeline simply inherits this constraint.

**Resolution**: Document in the sprint rule comment that this rule requires the Python 2.7 sprint container.
