# Implementer Prompt: Morales_et_al Pipeline Containerization

Stage: 2-architect -> 3-implement handoff
Generated: 2026-05-05T22:15:00Z

## 1. Role and Constraints

You are the implementer for `forge-8a8d6b83`. You execute the 8 tasks in `.forge/stages/2-architect/tasks/` in their declared dependency order. You produce code changes only. You do not redesign, do not add scope, and do not modify files outside the explicit allowlist.

### Allowlist (you MAY modify these and only these)

- `pipelines/Morales_et_all/Snakefile`
- `pipelines/Morales_et_all/preprocessing.smk`
- `pipelines/Morales_et_all/tools.smk`
- `pipelines/Morales_et_all/downstream.smk`
- `pipelines/Morales_et_all/config.yaml`

### Createlist (you MAY create these new files)

- `containers/star/Dockerfile`
- `containers/star/validate.sh`
- `containers/red_ml/Dockerfile`
- `containers/red_ml/validate.sh`
- `containers/fastx/Dockerfile`
- `containers/fastx/validate.sh`
- `containers/morales_downstream/Dockerfile`
- `containers/morales_downstream/validate.sh`

### Denylist (you MUST NOT modify these)

- Anything under `pipelines/editing_wgs/`
- Anything under `containers/picard/`, `containers/reditools/`, `containers/sprint/`, `containers/wgs/`, `containers/jacusa2/`
- `profiles/tscc2/config.yaml`
- `singularity/` (build artifacts)
- Anything under `Benchmark-of-RNA-Editing-Detection-Tools/`

If a task seems to require modifying a denylist file, stop and escalate via a `bd` issue tagged `blocker`.

## 2. Execution Order

```
Task 01 (Snakefile helper)
   |
   v
Task 02 (config.yaml)
   |
   +-> Task 03 (preprocessing.smk)
   +-> Task 04 (tools.smk)
   +-> Task 05 (downstream.smk)

Task 06 (containers/star/) — parallel, no dependencies
Task 07 (containers/red_ml/) — parallel, no dependencies
Task 08 (containers/fastx/ + containers/morales_downstream/) — parallel, no dependencies
```

Tasks 03, 04, 05 may proceed in any order once Task 02 is complete; they edit different files.

## 3. Verification Plan

After completing all 8 tasks, run from `pipelines/Morales_et_all/`:

```bash
snakemake --lint --snakefile Snakefile --configfile config.yaml
snakemake -n --snakefile Snakefile --configfile config.yaml --cores 1
```

Both must exit 0.

Then run from the repo root:

```bash
# Directive counts (each must equal 14)
grep -rn "container:" pipelines/Morales_et_all/*.smk | wc -l
grep -rn "^    log:" pipelines/Morales_et_all/*.smk | wc -l
grep -rn "^    resources:" pipelines/Morales_et_all/*.smk | wc -l

# Forbidden strings (each must return no matches; exit 1 means PASS)
grep -r "~/bin\|/binf-isilon" pipelines/Morales_et_all/
grep "java -jar" pipelines/Morales_et_all/preprocessing.smk
grep -E "params\.(script|sprint_bin|jacusa_jar|samtools_bin)" pipelines/Morales_et_all/*.smk
grep "python Downstream/" pipelines/Morales_et_all/downstream.smk

# Required strings
grep -c "downstream_scripts_dir" pipelines/Morales_et_all/config.yaml   # expect 1 (or more if code references it)
grep "container_for" pipelines/Morales_et_all/Snakefile                  # expect function def
grep "container_for(\"wgs\")" pipelines/Morales_et_all/tools.smk        # expect >= 2 (bcftools, add_md_tag)
grep "set -euo pipefail" pipelines/Morales_et_all/tools.smk             # expect bcftools rule

# File existence
test -f containers/star/Dockerfile && test -f containers/star/validate.sh
test -f containers/red_ml/Dockerfile && test -f containers/red_ml/validate.sh
test -f containers/fastx/Dockerfile && test -f containers/fastx/validate.sh
test -f containers/morales_downstream/Dockerfile && test -f containers/morales_downstream/validate.sh

# Existing tests must still pass
python -m unittest tests/test_sprint_to_deepred_vcf.py
```

The `tests/test_editing_wgs_dryrun.py` test is for the editing_wgs pipeline and is not affected.

Container build/validation is a post-merge human step:
```bash
TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
```
The implementer does NOT run this.

## 4. Style and Conventions

- Match `pipelines/editing_wgs/` rule layout exactly: `input` -> `output` -> `threads` -> `resources` -> `container` -> `log` -> `params` -> `shell`.
- Use raw triple-quoted strings (`r"""..."""`) for shell blocks.
- Indent shell content by 8 spaces.
- Always start multi-command shell blocks with `set -euo pipefail`.
- Use line continuations (`\`) consistently; do not over-fold short commands.
- Append `1> {log.stdout} 2> {log.stderr}` to single-command shells; use `2>> {log.stderr}` for follow-up commands.
- For Dockerfiles: pin versions where possible; use `--no-install-recommends` with apt; clean apt lists in same RUN; use `mamba clean -a -y` after mamba install.
- For validate.sh: start with `#!/usr/bin/env bash` and `set -euo pipefail`; end with `echo "<Tool> validation passed"`.

## 5. What Triggers Escalation

Stop and file a `bd` issue tagged `blocker` if:
- A required upstream URL (STAR release tarball, RED-ML repo, bioconda fastx_toolkit) returns 404 or fails checksum
- `snakemake --lint` fails with an error that is not addressable by adjusting the modified files (i.e., suggests a Snakemake version incompatibility)
- A task's acceptance criteria contradict another task's
- The picard wrapper at `/usr/local/bin/picard` is not present in the picard container Dockerfile (verify before merging Task 03)
- `red_ML.pl` is not at `/opt/red_ml/bin/red_ML.pl` after RED-ML clone (verify in Task 07)

Do NOT escalate for: minor cosmetic style differences from the plan (acceptable if functionally equivalent and reviewed); resource value tweaks (acceptable if within 25% of plan values).

## 6. Handoff Acknowledgement

Before starting Task 01, the implementer should:
1. Read this prompt entirely.
2. Read `architecture-plan.md` sections 5 (Detailed Contracts) and 7 (Task Decomposition).
3. Read each task file in execution order.
4. Read `assumptions.json` and confirm none are invalidated by current state.
5. Confirm the denylist has not been modified by any prior change (`git status` clean for those paths).

## 7. Definition of Done (entire stage)

The build stage is COMPLETE when ALL of the following are true:
- All 8 task files have AC checkmarks ticked AND a passing verification command output captured.
- All 18 verification commands in section 3 pass.
- `git status` shows changes only within the allowlist + createlist.
- A `bd` issue summarizing the build is opened with status `closed` and label `phase-3`.
