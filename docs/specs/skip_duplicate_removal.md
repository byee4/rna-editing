# Spec: Optional skip of duplicate removal (use the un-deduplicated BAM)

Status: **DRAFT — awaiting review**
Author: Claude (for Brian Yee)
Date: 2026-06-03
Scope: `pipelines/Morales_et_al/`, `examples/Morales_et_al*/config*.yaml`, `tests/`, `docs/`
Tracking: `rna-editing-oj2`

## 1. Motivation

Two related requests:

1. **Guarantee a single source BAM/FASTQ across all callers.** An audit (see §2) confirms
   every caller already reads one converged BAM (`.rmdup.bam`) and one converged trimmed
   FASTQ per aligner. We want a guard test that locks this invariant so a future edit
   cannot silently point one tool at a different input.
2. **Allow skipping duplicate removal.** For some library types (e.g. amplicon / targeted
   panels, low-input, or UMI-free protocols where optical/PCR duplicate marking is
   inappropriate or removes real signal) the user wants every caller to run on the BAM
   *before* Picard removes duplicates — i.e. all reads retained.

These interact: `mark_duplicates` is the **single point** through which all callers'
BAM provenance flows, so making dedup optional is a one-rule change that automatically
preserves the single-source invariant — and the guard test then covers both modes.

## 2. Current state — the convergence points (audited 2026-06-03)

**FASTQ** — every aligner consumes the identical trimmed file:

```
samplesheet (fastq_1/fastq_2)
  → prepare_fastq  → data/fastq/{cond}_{samp}_{read}.fastq.gz
  → trim_reads     → results/trimmed/{cond}_{samp}_{read}_trimmed.fastq.gz
  → {star,bwa,hisat2}_mapping
```

**BAM** — every caller reads `.rmdup.bam` (output of `mark_duplicates`, Picard
`REMOVE_DUPLICATES=true`) or a tag/partition-only derivative that preserves the alignment:

| Caller | Declared BAM input | Derivation from `.rmdup.bam` |
|---|---|---|
| reditools (by-chrom) | `.split/{chrom}.bam` | `split_bam_by_chrom` |
| reditools3 | `.rmdup.bam` | direct |
| reditools_redinet | `.split/{chrom}.bam` | `split_bam_by_chrom` |
| bcftools | `.rmdup.bam` | direct |
| red_ml | `.rmdup.bam` | direct |
| sprint | `.rmdup.bam` (bwa) / `.rmdup_mapq30.bam` (star,hisat2) | `sprint_mapq_bam` (MAPQ 255→30) |
| jacusa2 / jacusa2_call1 | `.rmdup_MD.bam` | `add_md_tag` (calmd) |
| marine | `.split_md/{chrom}.bam` | `add_md_tag` → `split_marine_md_bam_by_chrom` |

No caller reads a raw pre-dedup `.bam`, an externally supplied BAM, or an untrimmed FASTQ.
The derivatives change only MAPQ values, MD tags, or chromosome partitioning — never the
read set or alignment coordinates. `.rmdup.bam` is the sole BAM convergence point.

## 3. Design

### 3.1 Config flag

Add one key under `params.common` (single source of truth, consistent with
`strandedness`/`edit_type`):

```yaml
params:
  common:
    remove_duplicates: true   # true (default) = Picard MarkDuplicates REMOVE_DUPLICATES=true
                              # false           = bypass Picard, feed callers the raw BAM
```

Default `true` ⇒ **no behavior change** for existing runs and configs that omit the key
(the rule reads `config["params"]["common"].get("remove_duplicates", True)`).

### 3.2 Make `mark_duplicates` conditional (recommended approach)

Keep the output filename `.rmdup.bam` and branch inside the existing single rule. This is
the minimal-blast-radius option: **zero downstream rules change**, all ~15 references to
`.rmdup.bam` (and the `_mapq30` / `_MD` / `.split` derivatives) keep working untouched, and
the single-source invariant is preserved by construction.

```python
rule mark_duplicates:
    input:
        bam="results/mapped/{aligner}/{condition}_{sample}.bam"
    output:
        rmdup_bam=temp("results/mapped/{aligner}/{condition}_{sample}.rmdup.bam"),
        metrics="results/mapped/{aligner}/{condition}_{sample}.duplication.info"
    ...
    container: container_for("picard")
    params:
        remove_dups=config["params"]["common"].get("remove_duplicates", True),
        mem_mb_heap=lambda wildcards, resources: int(resources.mem_mb * 0.75)
    shell:
        r"""
        set -euo pipefail
        if [ "{params.remove_dups}" = "True" ]; then
            _JAVA_OPTIONS="-Xmx{params.mem_mb_heap}m" picard MarkDuplicates \
                 INPUT={input.bam} OUTPUT={output.rmdup_bam} \
                 METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true \
                 1> {log.stdout} 2> {log.stderr}
        else
            # Duplicate removal skipped (params.common.remove_duplicates=false):
            # pass the aligner BAM through unchanged so every caller still reads
            # the single converged .rmdup.bam target — now containing all reads.
            cp -f {input.bam} {output.rmdup_bam} 2> {log.stderr}
            echo "duplicate removal skipped (params.common.remove_duplicates=false); raw aligner BAM passed through" \
                > {output.metrics}
            echo "skipped" > {log.stdout}
        fi
        """
```

Notes:
- `cp` and `echo` are present in the picard container, so the skip branch needs no extra
  tooling and keeps `container:` unchanged.
- The `metrics` output is still produced (a one-line placeholder) so the DAG and any
  consumer of `*.duplication.info` stay stable.
- Snakemake renders a Python `bool` as `True`/`False`; the shell test matches `"True"`.

### 3.3 Alternatives considered (and rejected)

- **Mark-but-keep (`REMOVE_DUPLICATES=false`).** Still runs Picard, flags duplicates but
  retains all reads. Tools that honor the dup flag would still skip them; tools that ignore
  it see all reads. This is *not* a clean "skip" and is less predictable across the 8
  callers. Rejected as the default meaning; can be offered later as a third mode if needed.
- **Rename the output to a neutral name** (e.g. `.processed.bam`) and add a helper
  `source_bam(wildcards)` consumed by every caller. Correct in principle but touches every
  caller input and every derivative filename — large diff, defeats the just-confirmed
  single-source design, and complicates the guard test. Rejected; noted as future cleanup
  (§7).
- **Separate `skip_dedup` rule + `ruleorder`.** Two rules producing the same output is
  ambiguous and needs `ruleorder` plumbing. More moving parts than the in-shell branch.
  Rejected.

## 4. Naming tradeoff (explicit)

When `remove_duplicates: false`, the file is still named `.rmdup.bam` but contains
duplicates. This is a deliberate, documented misnomer chosen to keep the change surgical
(zero downstream edits). The placeholder `*.duplication.info` and the rule comment make the
true provenance discoverable. Renaming for accuracy is deferred to §7.

## 5. Config changes

Add `remove_duplicates: true` (with the comment from §3.1) to `params.common` in:
- `examples/Morales_et_al_small/config_small.yaml`
- `examples/Morales_et_al/config.yaml`

## 6. Files touched

| File | Change |
|---|---|
| `pipelines/Morales_et_al/rules/preprocessing.smk` | `mark_duplicates`: add `remove_dups` param + conditional shell branch |
| `examples/Morales_et_al_small/config_small.yaml` | add `params.common.remove_duplicates: true` |
| `examples/Morales_et_al/config.yaml` | add `params.common.remove_duplicates: true` |
| `tests/test_morales_pipeline_spec.py` | add guard test class (§7.1) + dedup-toggle test (§7.2) |
| `docs/specs/skip_duplicate_removal.md` | this spec |
| `docs/tools_reference.md` (or equivalent) | one line documenting the new flag |

## 7. Guard test + verification

`tests/test_morales_pipeline_spec.py` already parses rule bodies statically via
`_all_rules()` / `_parse_rules()`. Add:

### 7.1 Single-source invariant (locks the audit)

`class TestSingleSourceBam` — for every caller rule, assert its declared BAM input resolves
(transitively, following the known derivation chain) to `.rmdup.bam`, and that no caller
rule references a raw `results/mapped/{aligner}/{condition}_{sample}.bam` (pre-dedup) or an
untrimmed FASTQ.

```python
CALLER_RULES = {
    "reditools_by_chrom", "reditools3", "reditools_redinet_by_chrom",
    "bcftools", "red_ml", "sprint", "jacusa2", "jacusa2_call1",
    "add_md_tag", "marine_by_chrom", "split_bam_by_chrom",
    "split_marine_md_bam_by_chrom", "sprint_mapq_bam",
}
# Every BAM-consuming rule above must reference one of:
#   .rmdup.bam | .rmdup_mapq30.bam | .rmdup_MD.bam | .split/{chrom}.bam | .split_md/{chrom}.bam
# and NONE may reference the bare pre-dedup '{condition}_{sample}.bam'.
```

(Maintain `CALLER_RULES` as the canonical list; a new caller rule that reads a BAM should be
added here, which is itself the reminder to route it through `.rmdup.bam`.)

### 7.2 Dedup toggle

`class TestRemoveDuplicatesFlag`:
- `mark_duplicates` body contains both a `MarkDuplicates ... REMOVE_DUPLICATES=true` branch
  and a `cp -f {input.bam} {output.rmdup_bam}` branch gated on `remove_dups`.
- Both example configs contain `params.common.remove_duplicates`.
- (Optional, env-gated) a real `snakemake --dry-run` in each mode: with the flag `true` the
  printed DAG shows `MarkDuplicates`; with `false` it shows the `cp` passthrough, and in
  **both** modes every caller is still scheduled from `.rmdup.bam`.

### 7.3 Acceptance criteria

| # | Given | When | Then |
|---|---|---|---|
| AC-1 | config omits `remove_duplicates` | dry-run | identical DAG to today (Picard runs); back-compatible |
| AC-2 | `remove_duplicates: true` | run | `.rmdup.bam` produced by Picard `REMOVE_DUPLICATES=true` (unchanged) |
| AC-3 | `remove_duplicates: false` | run | `.rmdup.bam` is a byte copy of the aligner BAM; Picard not invoked; `*.duplication.info` is the placeholder |
| AC-4 | either mode | dry-run | every caller's BAM input resolves to `.rmdup.bam`; no caller reads the pre-dedup `.bam` or untrimmed FASTQ |
| AC-5 | — | `python -m unittest tests/test_morales_pipeline_spec.py` | new guard + toggle tests pass |

## 8. Out of scope / future

- Renaming `.rmdup.bam` → a provenance-neutral name (§4) for accuracy.
- A third "mark-but-keep" dedup mode (`REMOVE_DUPLICATES=false`).
- Applying the same flag to the `editing_wgs` pipeline (this spec is Morales-only).
- Per-aligner or per-sample dedup overrides (single global flag only, by design).
