# Architecture Addendum — Post-Implement Scope Expansion

<!-- FORGE_STAGE: 2-architect (addendum) -->
<!-- CREATED: 2026-05-07 during forge stage 4.5-revision round 1 -->
<!-- COVERS: commits 24ce97b 316ab01 3f7f415 395dbe4 290d0d5 7d79e43 5213422 -->

This addendum formally ratifies the ~1,200 lines added after the original architect-approved
implementation (`a9acbae`). It follows the same conventions as `architecture-plan.md`.

---

## A1. New Files Ratified

| File | Lines | Status |
|------|-------|--------|
| `pipelines/Morales_et_all/rules/wgs.smk` | ~151 | NEW — 5 rules |
| `pipelines/Morales_et_all/rules/references.smk` | ~120 | NEW — 3 rules |
| `pipelines/Morales_et_all/samplesheet.csv` | ~5 | NEW — CSV driver |
| `scripts/build_downstream_dbs.py` | 241 | NEW — downstream DB builder |
| `pipelines/Morales_et_all/Snakefile` | delta | MODIFIED — samplesheet integration |
| `pipelines/Morales_et_all/config.yaml` | delta | MODIFIED — wgs_samples, db_path, samplesheet |

---

## A2. New Rules — Acceptance Criteria

### rules/wgs.smk (5 rules)

Each rule must satisfy the original architect invariant: `container:`, `log:`, `resources:`.

| Rule | container | log | resources | threads |
|------|-----------|-----|-----------|---------|
| `wgs_bwa_mem` | `wgs` | stdout+stderr | mem_mb+runtime | config["threads"] |
| `wgs_deduplicate` | `wgs` | stdout+stderr | mem_mb+runtime | config["threads"] |
| `wgs_md_tags` | `wgs` | stdout+stderr | mem_mb+runtime | (inherits) |
| `wgs_call_variants` | `wgs` | stdout+stderr | mem_mb+runtime | (inherits) |
| `wgs_vcf_to_ag_tc_bed` | `wgs` | stdout+stderr | mem_mb+runtime | 1 |

All resource values follow the existing pattern:
- `mem_mb = lambda wildcards, attempt: BASE * (1.5 ** (attempt - 1))`
- `runtime = lambda wildcards, attempt: BASE * (2 ** (attempt - 1))`

### rules/references.smk (3 rules)

| Rule | container | log | resources | threads |
|------|-----------|-----|-----------|---------|
| `generate_simple_repeat` | `wgs` | stdout+stderr | mem_mb(4000)+runtime(30) | 1 |
| `generate_alu_bed` | `wgs` | stdout+stderr | mem_mb(4000)+runtime(30) | 1 |
| `build_dbrna_editing` | `morales_downstream` | stdout+stderr | mem_mb(16000)+runtime(60) | 1 |

---

## A3. Decision D-13 — Samplesheet Driver Pattern

| Field | Value |
|-------|-------|
| **ID** | D-13 |
| **Decision** | Replace inline `config["conditions"]`/`config["samples"]` lists with a CSV samplesheet loaded by `_load_samplesheet()` in `Snakefile` |
| **Choice** | CSV samplesheet at `config["samplesheet"]` (default `samplesheet.csv`) |
| **Alternatives** | (a) Keep inline YAML lists; (b) TSV samplesheet; (c) JSON |
| **Rationale** | CSV is the lingua franca for experiment metadata; `csv.DictReader` is stdlib with no additional deps; pattern is widely used in Snakemake workflows (e.g., nf-core samplesheet convention). The samplesheet populates `config["conditions"]` and `config["samples"]` at load time so all downstream rules remain unchanged. |
| **Constraint** | Samplesheet columns required: `conditions`, `samples`, `fastq_1`, `fastq_2` (optional). Missing `fastq_2` means single-end. |

---

## A4. Contract for `scripts/build_downstream_dbs.py`

### Purpose
Build the three JSON lookup databases consumed by `pipelines/Morales_et_all/downstream.smk`:
- `HEK293T_hg38_clean.json` — filtered A>G / T>C SNPs from WGS alignment
- `REDIportal.json` — known A-to-I editing sites from REDIportal GRCh38
- `Alu_GRCh38.json` — Alu element coordinates

### Interface

```
python scripts/build_downstream_dbs.py \
    --hek-bed    <path>     # 5-col BED from wgs_vcf_to_ag_tc_bed
    --rediportal <path>     # REDIportal tab-sep file (gzip OK)
    --alu        <path>     # Alu BED from generate_alu_bed
    --assembly   hg38       # assembly label written into JSON
    --outdir     <dir>      # output directory (created if absent)
```

### Outputs (in `--outdir`)
- `HEK293T_hg38_clean.json`
- `REDIportal.json`
- `Alu_GRCh38.json`

### Acceptance Criteria
- AC-ADD-1: All three JSON files created in `--outdir` when given valid inputs.
- AC-ADD-2: Script is idempotent — re-running overwrites existing JSON files without error.
- AC-ADD-3: Script exits non-zero on missing/malformed input files.
- AC-ADD-4: gzip-compressed `--rediportal` input supported.

---

## A5. Submodule Strategy — Benchmark-of-RNA-Editing-Detection-Tools

**Decision:** Fork-and-pin (current approach). The repo is included as a git submodule pointing to
the upstream `BGIRED/Benchmark-of-RNA-Editing-Detection-Tools` at a fixed commit. No upstream PRs
are planned for the downstream Python scripts.

**Rationale:** The downstream scripts are consumed as-is. Patching is done via the `params.downstream_dir`
indirection in `downstream.smk`, which lets the submodule path be overridden in `config.yaml`.
A full fork-and-merge would require maintaining a fork repo; the submodule pin achieves the same
reproducibility at lower maintenance cost.

**Constraint:** Users must run `git submodule update --init Benchmark-of-RNA-Editing-Detection-Tools`
before executing downstream rules. This is documented in `config.yaml`.

---

## A6. Updated Decision Register (new entries)

Append to `architecture-plan.md` §6 Decision Register:

| ID | Decision | Choice | Rationale |
|----|----------|--------|-----------|
| D-13 | Samplesheet driver | CSV via `_load_samplesheet()` in Snakefile | See §A3 above |
| D-14 | WGS pipeline integration | New `rules/wgs.smk` with 5 rules mirroring `editing_wgs/wgs_processing.smk` | Keeps WGS-specific logic isolated; HEK293T SNP database builds automatically when `wgs_samples` is present in config |
| D-15 | Reference DB generation | New `rules/references.smk` with 3 rules; `build_dbrna_editing` uses `morales_downstream` container | Reference generation is idempotent and gated on output existence; heavier memory budget (16 GB) for REDIportal load |

---

## A7. Verification

The per-rule directive checker from review finding M-3 covers all 8 new rules.
After fixes in stage 4.5-revision, the checker must output `OK` with no missing directives.
