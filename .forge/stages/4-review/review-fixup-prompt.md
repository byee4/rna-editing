# Review Fixup Prompt — Round 1

<!-- FORGE_STAGE: 4.5-revision -->
<!-- SOURCE: .forge/stages/4-review/review-report.md -->

The reviewer found 3 MAJOR and 4 MINOR issues. Apply the following fixes, then re-run `/forge review`.

## Required (MAJOR)

### M-1 — Resolve post-implement scope expansion

The 7 commits between `a9acbae` (architect-approved implementation) and HEAD added ~1,200 lines of unplanned code:
`24ce97b 316ab01 3f7f415 395dbe4 290d0d5 7d79e43 5213422`.

Files added/heavily modified outside the architect plan:
- `pipelines/Morales_et_all/rules/wgs.smk` (NEW, 5 rules)
- `pipelines/Morales_et_all/rules/references.smk` (NEW, 3 rules)
- `pipelines/Morales_et_all/samplesheet.csv` (NEW)
- `scripts/build_downstream_dbs.py` (NEW, 241 lines)
- `pipelines/Morales_et_all/Snakefile` (samplesheet integration)
- `pipelines/Morales_et_all/config.yaml` (wgs_samples, db_path, samplesheet keys)

**Choose one resolution path**:

(a) **Re-architect (preferred)**: Run `/forge architect` again with these new files as input. Produce an addendum architecture plan that:
- Adds ACs for resources/log/container coverage on the 8 new rules
- Decides on the samplesheet driver pattern as a formal architectural choice (D-13)
- Specifies a contract for `scripts/build_downstream_dbs.py`
- Documents the submodule patches as either a fork-and-merge or upstream-PR strategy

(b) **Revert and re-scope**: `git revert 5213422 7d79e43 290d0d5 395dbe4 3f7f415 316ab01 24ce97b`, file the additions as a new forge pipeline run.

### M-2 — Record RED-ML URL deviation, amend ADR-02

Create `.forge/stages/3-implement/spec-deviations.json`:
```json
{
  "deviations": [
    {
      "id": "D-RED-ML-URL",
      "task": "task-07-container-red_ml",
      "spec": "git clone https://github.com/BGI-shenzhen/RED-ML.git (per architecture-plan.md §5.6 / ADR-02 / task-07-container-red_ml.md line 24)",
      "actual": "git clone https://github.com/BGIRED/RED-ML.git (per containers/red_ml/Dockerfile:25)",
      "reason": "BGI-shenzhen org returns HTTP 404; BGIRED is the canonical/working repo. Implementation is correct; spec was wrong.",
      "verified_via": "curl -I https://github.com/BGIRED/RED-ML returns 200; curl -I https://github.com/BGI-shenzhen/RED-ML returns 404",
      "approved_by": "reviewer (forge stage 4-review round 1)"
    }
  ]
}
```

Then amend `.forge/stages/2-architect/adrs/ADR-02` (or the relevant section of architecture-plan.md §5.6) to use the corrected `BGIRED/RED-ML.git` URL.

### M-3 — Add `resources:` and `container:` to post-implement rules

In `pipelines/Morales_et_all/rules/references.smk`, add to each rule:

```python
# generate_simple_repeat
threads: 1
resources:
    mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
    runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))

# generate_alu_bed (same as above)
threads: 1
resources:
    mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
    runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))

# build_dbrna_editing — heavier because REDIportal load is memory-intensive
threads: 1
container: container_for("morales_downstream")
resources:
    mem_mb=lambda wildcards, attempt: 16000 * (1.5 ** (attempt - 1)),
    runtime=lambda wildcards, attempt: 60 * (2 ** (attempt - 1))
```

In `pipelines/Morales_et_all/rules/wgs.smk`, the `wgs_vcf_to_ag_tc_bed` rule needs:

```python
threads: 1
resources:
    mem_mb=lambda wildcards, attempt: 4000 * (1.5 ** (attempt - 1)),
    runtime=lambda wildcards, attempt: 30 * (2 ** (attempt - 1))
```

After these fixes, all 23 rules in the live pipeline (including post-implement additions) will satisfy the original architect invariant of `container:`/`log:`/`resources:` on every rule.

**Verification**:
```python
import re
files = [
    "pipelines/Morales_et_all/preprocessing.smk",
    "pipelines/Morales_et_all/tools.smk",
    "pipelines/Morales_et_all/downstream.smk",
    "pipelines/Morales_et_all/rules/wgs.smk",
    "pipelines/Morales_et_all/rules/references.smk",
]
for f in files:
    text = open(f).read()
    matches = list(re.finditer(r'(?m)^rule\s+(\w+):', text))
    for i, m in enumerate(matches):
        end = matches[i+1].start() if i+1 < len(matches) else len(text)
        body = text[m.end():end]
        for d in ("container:", "log:", "resources:"):
            assert re.search(rf'^[ \t]+{d}', body, re.M), f'{f}::{m.group(1)} missing {d}'
print("OK")
```
The `prepare_fastq` localrule is exempt (see m-3 below).

## Recommended (MINOR)

### m-1 — Add `import re` to Snakefile (per plan §5.1)

`pipelines/Morales_et_all/Snakefile` line 3, between `import os` and the configfile call. Plan §5.1 said "kept for parity with editing_wgs". One-line fix.

### m-2 — Add `container:` to `build_dbrna_editing` rule

Already covered in M-3 above (use `container_for("morales_downstream")`).

### m-3 — Document or constrain `prepare_fastq` localrule

Either (a) add a comment near `localrules: prepare_fastq` warning that the gunzip runs on the head node and is fine for small_examples but should be reconsidered for large files, or (b) drop the localrule classification and dispatch to a worker with `container: container_for("wgs")` and a small `resources:` block.

### m-4 — Document `wgs_samples` requirement for downstream

In `pipelines/Morales_et_all/config.yaml`, add a comment near `wgs_samples:` clarifying that without this key, `multiple_analysis.done` will fail at runtime because the JSON databases will not be built. Alternatively, gate `multiple_analysis.done` in `rule all` on `_WGS_DB_FILES` being non-empty.

## Verification Plan (after fixes)

1. Re-run `python -m unittest discover -s tests` → all green.
2. Re-run the per-rule directive checker (script in M-3) → no missing-directive output.
3. (TSCC) Run `snakemake --lint --snakefile Snakefile --configfile config.yaml` from `pipelines/Morales_et_all/` → 0 errors.
4. (TSCC) Run `snakemake -n --snakefile Snakefile --configfile config.yaml --cores 1` → < 60s wall clock, exit 0.
5. Re-run `/forge review` for round-2 verdict.
