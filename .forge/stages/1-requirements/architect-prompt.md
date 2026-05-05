# [TASK]: Morales_et_al Pipeline — Snakemake 9+ Compliance and Containerization
<!-- PIPELINE: Stage 1 (Requirements) -> Stage 2 (Architect) -->
<!-- STATUS: READY_FOR_ARCHITECT -->
<!-- UPDATED_UTC: 2026-05-05T22:00:00Z -->
<!-- CLARIFICATION_ROUNDS: 0 -->


## 1. Architect Role Definition

You are the architect for this task. You MUST produce exactly three outputs:

1. `architecture-plan.md`: full architecture with 3+ approaches, contracts, ordered
   task decomposition, and requirements coverage matrix
2. `implementer-prompt.md`: execution constraints and verification plan for the build stage
3. `tasks/task-NN-<slug>.md`: one file per implementation task

You MUST NOT implement code. You MUST produce unambiguous, implementation-ready
specifications. Every acceptance criterion must be measurable. Every task must be
independently verifiable.


## 2. User Request (Untrusted Data)

```
Bring the pipelines/Morales_et_all/ Snakemake pipeline to Snakemake 9+ compliance
and add container fields for every rule, creating missing Dockerfiles where needed.
Ensure Python and Bash scripts are discoverable via config or workflow.source_path()
rather than hardcoded user-home paths.
```

**Interpreted intent**: Bring `pipelines/Morales_et_all/` to the same level of reproducibility and HPC-correctness as `pipelines/editing_wgs/` by adding `container:`, `log:`, and `resources:` directives to every rule, replacing hardcoded tool paths with container-resident binaries, fixing downstream script discoverability, and creating four new Dockerfiles for tools that lack containers.


## 3. Mission Brief

### 3.1 Objective

The `pipelines/Morales_et_all/` Snakemake pipeline currently has zero container directives, user-specific `~/bin/` tool paths in config, no `log:` or `resources:` directives, and downstream script paths that point to an empty git submodule. The task is to retrofit this pipeline to the same containerization and Snakemake 9+ patterns used in `pipelines/editing_wgs/`: add a `container_for()` helper and `containers:` config block, add `container:`, `log:`, and `resources:` directives to all 9 rules (plus 5 downstream rules), replace all `~/bin/` tool paths with container-resident commands, fix downstream script paths via config, and create 4 missing Dockerfiles (star, red_ml, fastx, morales_downstream).

### 3.2 In Scope

- `pipelines/Morales_et_all/Snakefile`: add `container_for()` helper, `SIF_DIR`/`CONTAINERS` globals, `singularity_image_dir` read
- `pipelines/Morales_et_all/preprocessing.smk`: add `container:`, `log:`, `resources:` to 3 rules; update shell commands to use containerized tools
- `pipelines/Morales_et_all/tools.smk`: add `container:`, `log:`, `resources:` to 6 rules (reditools, sprint, bcftools, red_ml, add_md_tag, jacusa2); update shell commands to use containerized tools; add `set -euo pipefail` to bcftools pipe; update `mark_duplicates` to use `picard MarkDuplicates` wrapper
- `pipelines/Morales_et_all/downstream.smk`: add `container:`, `log:`, `resources:` to 5 downstream rules; fix `python Downstream/*.py` bare paths
- `pipelines/Morales_et_all/config.yaml`: add `singularity_image_dir:` key and `containers:` block; remove `tools:` section of user-specific paths; add `downstream_scripts_dir:` key
- `containers/star/Dockerfile` + `validate.sh`: STAR 2.7.x + samtools
- `containers/red_ml/Dockerfile` + `validate.sh`: Perl + R + RED-ML (red_ML.pl)
- `containers/fastx/Dockerfile` + `validate.sh`: FASTX-Toolkit (fastx_trimmer)
- `containers/morales_downstream/Dockerfile` + `validate.sh`: Python 3 + pandas/numpy for Downstream scripts

### 3.3 Out of Scope

- Modifying `pipelines/editing_wgs/` in any way
- Building or pushing SIF files (post-commit step run by humans)
- Running the pipeline on real data
- Adding alignment options beyond STAR (BWA/HISAT2 in `aligners:` config are unused by current rules)
- Modifying the `Benchmark-of-RNA-Editing-Detection-Tools/` submodule contents
- Adding new analysis rules beyond what currently exists

### 3.4 Success Definition

- `snakemake --lint` passes with 0 errors on all four `.smk` files
- `snakemake -n` (dry-run) completes without errors from `pipelines/Morales_et_all/`
- Every rule (9 tool rules + 5 downstream rules = 14 total) has `container:`, `log:`, and `resources:` directives
- Zero `~/bin/` or absolute user-home paths remain in any `.smk` file or `config.yaml`
- Four new Dockerfiles exist with validate scripts that exit 0


## 4. Current-State Technical Context

### 4.1 Repo Facts

- **Stack**: Python 3 / Snakemake 9 / Singularity+Apptainer containers / SLURM (TSCC)
- **Entry points**: `pipelines/Morales_et_all/Snakefile` (4-file pipeline); `pipelines/editing_wgs/Snakefile` (canonical pattern reference)
- **Existing patterns**: `container_for()` helper in editing_wgs Snakefile; `containers:` block + `singularity_image_dir:` in editing_wgs config; `log: stdout=/logs/{sample}.tool.out` per rule; `resources: mem_mb=lambda wildcards, attempt:...` with exponential backoff
- **Package manager**: N/A (Snakemake + Apptainer/Singularity manage tool environments)

### 4.2 Key Files (10-25)

| # | File | Purpose | Relevance to This Task |
|---|------|---------|------------------------|
| 1 | `pipelines/Morales_et_all/Snakefile` | Top-level orchestration: configfile, includes, rule all | Must gain `container_for()`, `SIF_DIR`, `CONTAINERS` globals |
| 2 | `pipelines/Morales_et_all/preprocessing.smk` | Rules: trim_reads, star_mapping, mark_duplicates | 3 rules to containerize; tool path fixes |
| 3 | `pipelines/Morales_et_all/tools.smk` | Rules: reditools, sprint, bcftools, red_ml, add_md_tag, jacusa2 | 6 rules to containerize; path fixes; pipe safety |
| 4 | `pipelines/Morales_et_all/downstream.smk` | Rules: run_downstream_parsers, update_alu, individual_analysis, reanalysis_multiple, multiple_analysis | 5 rules; bare relative script paths → parameterized |
| 5 | `pipelines/Morales_et_all/config.yaml` | Experimental config: references, tool paths, params | Replace `tools:` section; add `containers:` block and `downstream_scripts_dir:` |
| 6 | `pipelines/editing_wgs/Snakefile` | Canonical pattern: `container_for()`, `SIF_DIR`, `CONTAINERS` | Direct copy-adapt source for helper and globals |
| 7 | `pipelines/editing_wgs/config.yaml` | Canonical config: `singularity_image_dir:` + `containers:` block | Pattern for config additions |
| 8 | `pipelines/editing_wgs/rna_editing.smk` | Example rules with `container:`, `log:`, `resources:` | Pattern for rule directives |
| 9 | `containers/picard/Dockerfile` | eclipse-temurin base; picard wrapper script | Reuse pattern for new Dockerfiles |
| 10 | `containers/picard/picard` | Bash wrapper: `exec java -jar /opt/picard/picard.jar "$@"` | Pattern for tool wrapper scripts |
| 11 | `containers/picard/validate.sh` | Validate picard installation | Pattern for validate scripts |
| 12 | `containers/wgs/Dockerfile` | ubuntu:22.04; bcftools, samtools, bwa | Reusable for add_md_tag and bcftools rules |
| 13 | `containers/jacusa2/Dockerfile` | miniforge3; openjdk17 + jacusa2.jar at `/opt/jacusa2/jacusa2.jar` | Reusable for jacusa2 rule; JAR path is `/opt/jacusa2/jacusa2.jar` |
| 14 | `containers/sprint/Dockerfile` | ubuntu:18.04; Python 2.7; SPRINT at `/opt/sprint/` | Reusable for sprint rule; sprint_from_bam.py at `/opt/sprint/sprint_from_bam.py` |
| 15 | `containers/reditools/Dockerfile` | REDItools2 container | Reusable for reditools rule |
| 16 | `profiles/tscc2/config.yaml` | TSCC Snakemake profile: SLURM executor, apptainer SDM, resource defaults | `software-deployment-method: apptainer` (NOT `--use-singularity`); default mem_mb=20000, runtime=30 |
| 17 | `containers/red/Dockerfile` | RED Java GUI app — NOT red_ML | Do NOT reuse; create `containers/red_ml/` separately |

### 4.3 Constraints from Repo Policies

- **CLAUDE.md (project)**: Use `bd` for issue tracking. Work is not complete until `git push` succeeds. Session close protocol: tests/lint, close issues, push.
- **profiles/tscc2/config.yaml**: `software-deployment-method: apptainer` (Snakemake 9 deprecates `--use-singularity`). Default resources: `mem_mb=20000`, `runtime=30`. Partition: `condo`, account: `csd792`.
- **Existing pattern (editing_wgs)**: `container_for()` falls back to `{SIF_DIR}/{tool}.sif` if no explicit entry in CONTAINERS dict. New containers must be named to match their `containers:` key in config.
- **Dockerfile conventions**: Use pinned base images where possible; include `validate.sh` that exits 0 on success; install tools to `/opt/<toolname>/`; add wrapper scripts to `/usr/local/bin/`.
- **Shell safety**: All multi-command shell blocks with pipes must begin with `set -euo pipefail`.

### 4.4 Known Risks

- **Risk**: RED-ML requires specific R packages and a Perl version; Dockerfile may be complex. | **Impact**: Medium | **Mitigation**: Use `rocker/r-ver` or `condaforge/miniforge3` base; install Perl via apt; install R packages `caret`, `data.table`, `ROCR` via `Rscript -e`.
- **Risk**: FASTX-Toolkit is not actively maintained and may not be available in modern Ubuntu apt. | **Impact**: Medium | **Mitigation**: Use conda-forge/bioconda channel (`mamba install -c bioconda fastx_toolkit`) or compile from source in Ubuntu 20.04 base.
- **Risk**: `Benchmark-of-RNA-Editing-Detection-Tools/` submodule is empty; `downstream_scripts_dir` config key requires user to run `git submodule update --init` before execution. | **Impact**: Low (pipeline dry-run still passes; only actual execution fails) | **Mitigation**: Add comment in config.yaml warning about submodule initialization.
- **Risk**: The `mark_duplicates` rule currently uses `java -jar {params.picard}`. After containerization, this should call `picard MarkDuplicates` (wrapper). If the picard container's wrapper script isn't on PATH, the rule will fail. | **Impact**: High | **Mitigation**: Verify `containers/picard/picard` wrapper is copied to `/usr/local/bin/picard` in Dockerfile (it is — confirmed in Dockerfile line 17).
- **Risk**: `star_mapping` produces intermediate files with a `{prefix}Aligned.sortedByCoord.out.bam` naming convention and deletes them. Container must not shadow the output path. | **Impact**: Low | **Mitigation**: Ensure WORKDIR in STAR container is `/work` (writable) and output paths are absolute.


## 5. Requirements

### 5.1 Functional Requirements

- FR-1: The `Snakefile` must define `SIF_DIR`, `CONTAINERS`, and `container_for()` using the same pattern as `pipelines/editing_wgs/Snakefile` lines 14-25.
- FR-2: `config.yaml` must have a `singularity_image_dir:` key and a `containers:` block with entries for all 9 tool-rule containers (fastx, star, picard, reditools, sprint, wgs, red_ml, jacusa2, morales_downstream).
- FR-3: The `tools:` section of `config.yaml` (all 6 hardcoded `~/bin/` and `/binf-isilon/` paths) must be removed; tool executables are resolved from containers.
- FR-4: Every rule in preprocessing.smk, tools.smk, and downstream.smk must have a `container: container_for("<name>")` directive.
- FR-5: Every rule must have a `log:` directive with at least one named output (stdout and/or stderr), following the pattern `logs/{condition}_{sample}.<rulename>.[out|err]`.
- FR-6: Every rule must have a `resources:` directive with at minimum `mem_mb` and `runtime` (using lambda with `attempt` for exponential backoff matching editing_wgs pattern).
- FR-7: The `bcftools` rule's `shell:` block must start with `set -euo pipefail` before the pipe command.
- FR-8: The `mark_duplicates` rule must call `picard MarkDuplicates` (wrapper) instead of `java -jar {params.picard}`, and `params.picard` must be removed.
- FR-9: The `reditools` rule must call the `reditools.py` binary from PATH (container-resident) instead of `python {params.script}`.
- FR-10: The `sprint` rule must call `sprint_from_bam` from the container-resident path `/opt/sprint/sprint_from_bam.py` instead of `{params.sprint_bin}`.
- FR-11: The `jacusa2` rule must call `java -jar /opt/jacusa2/jacusa2.jar` instead of `java -jar {params.jacusa_jar}`, and `params.jacusa_jar` must be removed from the rule and config.
- FR-12: The `red_ml` rule must call `red_ML.pl` from PATH (container-resident) instead of `perl {params.script}`.
- FR-13: `downstream.smk` shell blocks must use `{params.downstream_dir}/REDItools2.py` (and analogous paths) where `params.downstream_dir` reads from `config["downstream_scripts_dir"]`.
- FR-14: `config.yaml` must have a `downstream_scripts_dir:` key pointing to the Benchmark submodule path (`Benchmark-of-RNA-Editing-Detection-Tools/Downstream`) with a comment that `git submodule update --init` is required.
- FR-15: `containers/star/Dockerfile` must install STAR 2.7.x and samtools with a validate.sh that exits 0.
- FR-16: `containers/red_ml/Dockerfile` must install Perl, R, and the RED-ML script (`red_ML.pl` accessible from PATH or known path) with a validate.sh that exits 0.
- FR-17: `containers/fastx/Dockerfile` must install FASTX-Toolkit (`fastx_trimmer` on PATH) with a validate.sh that exits 0.
- FR-18: `containers/morales_downstream/Dockerfile` must install Python 3 + pandas + numpy with a validate.sh that exits 0.
- FR-19: All star_mapping samtools commands must redirect stderr to `{log.stderr}` (currently no log).
- FR-20: The `add_md_tag` rule must use the `wgs` container (not jacusa2), consistent with C-005 resolution.

### 5.2 Non-Functional Requirements

- NFR-1: `snakemake --lint` must produce 0 errors on each of the four `.smk` files individually and collectively.
- NFR-2: `snakemake -n` (dry-run) must complete in under 60 seconds with 0 errors from the pipeline directory (assuming config references are syntactically valid dummy paths).
- NFR-3: Each new Dockerfile must install the minimum set of packages needed (no extra tools beyond what each rule uses).
- NFR-4: All validate.sh scripts must exit 0 when run inside their respective containers.
- NFR-5: Resources directives must specify mem_mb >= 8000 for memory-intensive rules (star_mapping, red_ml) and runtime >= 60 minutes.
- NFR-6: The changes must be backward-compatible: users running with `--use-singularity` (Snakemake 8) should still get a sensible error, not a silent failure. The profile already sets `software-deployment-method: apptainer`.

### 5.3 Security Requirements

- SEC-1: No rule may reference paths outside the workflow directory or mounted bind paths. Hardcoded `/binf-isilon/` and `~` paths must be eliminated. (N/A for cryptographic or auth concerns — this is a local HPC pipeline.)
- SEC-2: Dockerfiles must not run processes as root in the final image layer unless required by the tool. Prefer non-root USER where practical.

### 5.4 Compatibility Constraints

- The TSCC profile (`profiles/tscc2/config.yaml`) already uses `software-deployment-method: apptainer`. No changes needed to the profile.
- Snakemake version is 9+; the `container:` directive (not deprecated `singularity:`) must be used.
- Existing containers (picard, reditools, sprint, wgs, jacusa2) must not be modified; only new containers are created.
- The `aligners:` config key (star, bwa, hisat2) is present but unused by current rules; do not remove it (it may be used by future rules).


## 6. Acceptance Criteria

- AC-1: Running `snakemake --lint` on `pipelines/Morales_et_all/Snakefile` exits 0 with no errors. [traces to FR-1, NFR-1]
- AC-2: Running `snakemake -n --configfile pipelines/Morales_et_all/config.yaml` from the pipeline directory exits 0 (dry-run succeeds). [traces to FR-2, FR-4, NFR-2]
- AC-3: `grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/` returns no matches. [traces to FR-3, SEC-1]
- AC-4: `grep -rn "container:" pipelines/Morales_et_all/*.smk | wc -l` equals 14 (one per rule). [traces to FR-4]
- AC-5: `grep -rn "^    log:" pipelines/Morales_et_all/*.smk | wc -l` equals 14 (one per rule). [traces to FR-5]
- AC-6: `grep -rn "^    resources:" pipelines/Morales_et_all/*.smk | wc -l` equals 14 (one per rule). [traces to FR-6]
- AC-7: `grep "set -euo pipefail" pipelines/Morales_et_all/tools.smk` finds at least the bcftools rule block. [traces to FR-7]
- AC-8: `grep "java -jar" pipelines/Morales_et_all/preprocessing.smk` returns no matches (picard uses wrapper). [traces to FR-8]
- AC-9: `grep "params.script\|params.sprint_bin\|params.jacusa_jar\|params.samtools_bin" pipelines/Morales_et_all/*.smk` returns no matches. [traces to FR-9, FR-10, FR-11, FR-12]
- AC-10: `grep "python Downstream/" pipelines/Morales_et_all/downstream.smk` returns no matches; all calls use `{params.downstream_dir}/`. [traces to FR-13]
- AC-11: `grep "downstream_scripts_dir" pipelines/Morales_et_all/config.yaml` returns exactly 1 match. [traces to FR-14]
- AC-12: `test -f containers/star/Dockerfile && test -f containers/star/validate.sh` exits 0. [traces to FR-15]
- AC-13: `test -f containers/red_ml/Dockerfile && test -f containers/red_ml/validate.sh` exits 0. [traces to FR-16]
- AC-14: `test -f containers/fastx/Dockerfile && test -f containers/fastx/validate.sh` exits 0. [traces to FR-17]
- AC-15: `test -f containers/morales_downstream/Dockerfile && test -f containers/morales_downstream/validate.sh` exits 0. [traces to FR-18]
- AC-16: `grep "container_for" pipelines/Morales_et_all/Snakefile` finds the `container_for()` function definition. [traces to FR-1]
- AC-17: `grep "wgs" pipelines/Morales_et_all/tools.smk` shows the `add_md_tag` rule uses `container_for("wgs")`. [traces to FR-20]


## 7. Explicit Assumptions & Defaults

| # | Assumption | Default Value | Rationale | Risk (H/M/L) | Rollback If Wrong |
|---|-----------|---------------|-----------|---------------|-------------------|
| A-1 | `singularity_image_dir` in Morales config points to the same repo-level `singularity/` directory as editing_wgs | `/tscc/projects/ps-yeolab3/bay001/codebase/rna-editing/singularity` | Matches editing_wgs config; SIF files built from containers/ live here | L | Change the path in config.yaml to user's actual SIF directory |
| A-2 | STAR version 2.7.11a is acceptable for the new star container | 2.7.11a | Current stable; matches common RNA-seq workflows | L | Change `STAR_VERSION` ARG in Dockerfile to another 2.7.x version |
| A-3 | RED-ML Perl script (`red_ML.pl`) will be installed to `/opt/red_ml/bin/red_ML.pl` and added to PATH | `/opt/red_ml/bin/` on PATH | Consistent with other containers; Perl scripts aren't typically wrapped | M | If RED-ML repo structure changes, adjust COPY path and ENV |
| A-4 | FASTX-Toolkit will be installed via bioconda (`mamba install -c bioconda fastx_toolkit`) | bioconda channel | FASTX-Toolkit is in bioconda and is the path of least resistance | M | If bioconda package fails, compile from source using Ubuntu 20.04 + libgtextutils |
| A-5 | The `morales_downstream` container uses Python 3.11 + pandas 2.x + numpy 1.x | python:3.11-slim base | Python 3.11 is current LTS; pandas 2.x is stable; numpy 1.x is broadly compatible | L | Pin to specific versions via requirements.txt if script incompatibilities arise |
| A-6 | `log:` paths use `results/logs/{condition}_{sample}.{rulename}.out` and `.err` | `results/logs/` subdirectory | Keeps logs adjacent to results; consistent; Snakemake creates parent dirs | L | Change log prefix if a different convention is preferred |
| A-7 | Resources for rules follow editing_wgs exponential backoff pattern: `mem_mb=lambda wildcards, attempt: <base> * (1.5 ** (attempt - 1))` | Varies by rule (see context/09) | Matches existing convention; avoids re-typing fixed values for retry | L | Remove lambda and use fixed values if exponential backoff causes SLURM waste |
| A-8 | The `containers:` config block will map `morales_downstream` → `morales_downstream.sif` for downstream rules | Key: `morales_downstream` | All 5 downstream rules use the same Python container | L | Split downstream rules across multiple containers if script deps diverge |
| A-9 | `downstream.smk` rules will add `params.downstream_dir = config["downstream_scripts_dir"]` rather than using a global variable | Rule-level `params:` | Minimizes Snakefile header changes; keeps locality | L | Move to Snakefile global if repetitive |
| A-10 | `samtools calmd` in `add_md_tag` will NOT pipe to `-b` (binary output) and will redirect stdout to output BAM using shell redirect `>` | Current behavior preserved | The current shell command uses `>` redirect; changing output format risks downstream issues | L | Add `-b` flag and remove redirect if downstream tools require binary BAM explicitly |


## 8. Open Gaps Ledger

| # | Priority | Gap Description | Why It Matters | Resolution / Owner |
|---|----------|----------------|----------------|-------------------|
| G-1 | Low | Exact resource values (mem_mb, runtime) for each rule are not specified in the research output | Resource miscalibration may cause SLURM failures or waste | CLOSED: Assign reasonable defaults based on tool class: trim=4GB/30min, star=32GB/120min, markdup=8GB/30min, reditools=8GB/120min, sprint=12GB/240min, bcftools=4GB/60min, red_ml=16GB/120min, add_md_tag=4GB/30min, jacusa2=32GB/60min, downstream=4GB/60min each |
| G-2 | Low | `star_mapping` has a `set -euo pipefail` gap: no pipefail even though it uses `\|` (pipe in intermediate) | A failed samtools sort could be silently ignored | CLOSED: Add `set -euo pipefail` to star_mapping shell block as well |
| G-3 | Low | The SPRINT container uses Python 2.7; `editing_wgs` calls `/opt/sprint/sprint_from_bam.py` — need to verify this path is the same in the Morales usage | Calling wrong path = rule failure | CLOSED: Confirmed `containers/sprint/Dockerfile` clones SPRINT to `/opt/sprint/`; use `python /opt/sprint/sprint_from_bam.py` or verify wrapper exists |
| G-4 | Low | `red_ml` rule passes `--rnabam`, `--reference`, `--dbsnp`, `--simpleRepeat`, `--alu`, `--outdir`, `-p` flags — need to verify these match the actual `red_ML.pl` CLI | Wrong flags = silent failure | CLOSED: Flags are passed verbatim from existing shell block; they match the RED-ML documentation. No change needed. |

**Critical gap count**: 0


## 9. Architect Decision Checklist

| # | Decision Area | Option A | Option B | Option C | Invariants | Validation Method |
|---|--------------|----------|----------|----------|-----------|-------------------|
| D-1 | Base image for `containers/star/` | `ubuntu:22.04` + apt-get STAR (if available) or wget from GitHub | `condaforge/miniforge3` + bioconda STAR | Use existing `lodei.sif` (has STAR as dep) — create symlink or alias | Must have STAR 2.7.x + samtools; must be standalone image not relying on accidental deps | `STAR --version` and `samtools --version` exit 0 in validate.sh |
| D-2 | Base image for `containers/red_ml/` | `rocker/r-ver:4.3` + apt Perl + R packages | `condaforge/miniforge3` + bioconda r-base + perl | `ubuntu:22.04` + apt r-base + apt perl + CRAN packages | Must have `perl`, `Rscript`, RED-ML R packages (`caret`, `data.table`, `ROCR`); `red_ML.pl` on PATH | `perl red_ML.pl --help` or similar exits 0 in validate.sh |
| D-3 | Base image for `containers/fastx/` | `condaforge/miniforge3` + bioconda `fastx_toolkit` | `ubuntu:20.04` + compile from source | `quay.io/biocontainers/fastx_toolkit` prebuilt | Must have `fastx_trimmer` on PATH | `fastx_trimmer --help` exits with usage (non-zero ok) in validate.sh |
| D-4 | SPRINT binary call in `sprint` rule | `python /opt/sprint/sprint_from_bam.py` (existing container path) | `sprint_from_bam` on PATH (if Makefile installs it) | Keep `{params.sprint_bin}` but default to `/opt/sprint/bin/sprint_from_bam` | Must call same tool as existing editing_wgs SPRINT rules use | Rule dry-run passes |
| D-5 | `log:` path convention for rules with both condition and sample wildcards | `results/logs/{condition}_{sample}.{rulename}.out/err` | `logs/{condition}_{sample}.{rulename}.out/err` | Single `results/logs/{wildcards.condition}_{wildcards.sample}.{rulename}.log` | Must be deterministic; Snakemake must create parent; consistent across all rules | `snakemake --lint` passes |
| D-6 | Handling the `samtools_bin` reference removed from `sprint` rule params | Remove `params.samtools_bin` entirely (samtools is on PATH in sprint container) | Replace with hardcoded `samtools` (PATH) | Keep param but default to `samtools` | SPRINT's `sprint_from_bam` expects `samtools` as final positional argument | `snakemake --lint` passes; sprint rule dry-run succeeds |


## 10. Verification Environment

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Lint | `cd pipelines/Morales_et_all && snakemake --lint` | 0 errors, 0 warnings |
| Dry-run | `cd pipelines/Morales_et_all && snakemake -n` | Completes without error; shows job list |
| Container count | `grep -rn "container:" pipelines/Morales_et_all/*.smk \| wc -l` | 14 |
| Log count | `grep -rn "^    log:" pipelines/Morales_et_all/*.smk \| wc -l` | 14 |
| Resources count | `grep -rn "^    resources:" pipelines/Morales_et_all/*.smk \| wc -l` | 14 |
| No user paths | `grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/` | No matches (exit 1 means pass) |
| No bare downstream | `grep "python Downstream/" pipelines/Morales_et_all/downstream.smk` | No matches |
| Dockerfile presence | `ls containers/star/Dockerfile containers/red_ml/Dockerfile containers/fastx/Dockerfile containers/morales_downstream/Dockerfile` | All 4 files exist |
| validate.sh presence | `ls containers/star/validate.sh containers/red_ml/validate.sh containers/fastx/validate.sh containers/morales_downstream/validate.sh` | All 4 files exist |
| Unit tests | `pytest tests/` | All tests pass |


## 11. Context Files Reference

| # | File | Summary |
|---|------|---------|
| 1 | `context/01-vision-and-goals.md` | Project goals: reproducible HPC pipeline matching editing_wgs quality bar |
| 2 | `context/02-user-experience.md` | Developer UX: pipeline runs with single snakemake command on TSCC |
| 3 | `context/03-user-flows.md` | End-to-end flow: FASTQ → trimmed → mapped → tool outputs → downstream |
| 4 | `context/04-data-models.md` | File types, naming conventions, wildcard patterns for conditions/samples |
| 5 | `context/05-business-logic.md` | Rule-by-rule containerization logic, container assignments, shell command changes |
| 6 | `context/06-api-integrations.md` | N/A — no external APIs; container image sources (Docker Hub, bioconda, GitHub releases) |
| 7 | `context/07-security-requirements.md` | No user-home paths, no absolute cluster-specific paths in committed files |
| 8 | `context/08-edge-cases.md` | Empty submodule, STAR intermediate file cleanup, bcftools pipe failure, picard wrapper |
| 9 | `context/09-acceptance-criteria.md` | Full AC list with resource defaults per rule |
| 10 | `context/10-technical-constraints.md` | Snakemake 9+, apptainer SDM, TSCC SLURM profile details |
| 11 | `context/11-code-references.md` | Key file paths, line references, shell command before/after for each rule |
