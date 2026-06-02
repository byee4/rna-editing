# Spec: MARINE integration into the Morales_et_al benchmark suite

Status: **DRAFT — awaiting review**
Author: Claude (for Brian Yee)
Date: 2026-06-02
Scope: `pipelines/Morales_et_al/`, `containers/marine/`, `docs/`
Tracking: `rna-editing-qil`

## 1. Motivation

The `pipelines/Morales_et_al/Snakefile` benchmarks A-to-I editing callers (REDItools2/3,
SPRINT, RED-ML, BCFtools, REDInet, JACUSA2). **MARINE** (https://github.com/yeolab/marine)
is the Yeo Lab's own bulk/single-cell A-to-I detector and is currently the one tool wired
into config and downstream scripts but **not actually run**: its Snakemake rule and its
annotation-generation rule are commented out, and it is explicitly excluded from the tool
set that feeds BigBed tracks, the cross-tool comparison matrices, and the consensus
analysis (`Snakefile:87` → `if t not in ("jacusa2", "marine")`).

The goal is to fully activate MARINE as a first-class caller: run it in a container, wire
its output through the comparison/consensus analysis, and keep human- and agent-readable
docs in sync — with **no regression** to the existing outputs.

## 2. Current state (what already exists)

This is a *re-activation*, not a green-field add. The following scaffolding is present:

| Artifact | Location | State |
|---|---|---|
| Container image | `singularity/marine.sif` (1.1 GB, built 2026-06-02) | built, **not yet validated end-to-end** |
| Dockerfile | `containers/marine/Dockerfile` | present; clones MARINE `main`, builds conda env `marine` from `marine_environment2.yaml` |
| `validate-marine` | `containers/marine/validate.sh` | **BROKEN** — checks `/opt/marine/bin/MARINE/marine.py`; real path is `/opt/marine/marine.py` |
| `rule marine` | `rules/tools.smk:568` | commented out; uses `envmodules: marine` (no container), `--bam_filepath .rmdup_MD.bam` |
| `rule generate_marine_annotation` | `rules/references.smk:225` | commented out; GTF → BED6 gene annotation |
| Config keys | `examples/Morales_et_al_small/config_small.yaml` | `references.marine_annotation_bed`, `params.marine{strandedness, paired_end}`, `visualization.tools` includes `marine` |
| Downstream parsers | `scripts/compare_all_tools.py:355` (`parse_marine`), `scripts/tool_output_to_bed.py:214` (`to_bed_marine`), `scripts/make_trackhub.py`, `scripts/aligner_correlation.py` | present and marine-aware |
| Exclusion | `Snakefile:87`, `visualization.smk` (`_BED_TOOLS`) | marine excluded from comparison/BigBed/consensus |

**Implication:** most of the *consumer* side is done. The work is (a) a verified container
+ active rule that produces `final_filtered_site_info.tsv`, and (b) flipping marine into
`_BED_TOOLS` while solving the "outputs too large" problem (§6) that caused the original
exclusion.

## 3. Verified facts about the MARINE container & CLI

Probed from `singularity/marine.sif` on 2026-06-02 (TSCC):

- **Interpreter:** `/opt/conda/envs/marine/bin/python` (conda env `marine`, Python 3.8).
  `conda run -n marine` does **not** work under `singularity exec` because the host
  `~/.bashrc`/conda shim leaks in; call the env's python directly.
- **Entrypoint:** `/opt/marine/marine.py` — **not** `/opt/marine/bin/MARINE/marine.py`.
- **Container cache quirk (blocker):** importing MARINE triggers `numba` and `matplotlib`,
  which fail with `cannot cache function ... no locator available` and an unwritable
  `~/.cache/matplotlib` unless writable cache dirs are provided. The rule **must** export
  `NUMBA_CACHE_DIR` and `MPLCONFIGDIR` to a writable scratch path (e.g. under
  `config.tmpdir`). `SINGULARITYENV_HOME`/`--env HOME` override is rejected, so do not rely
  on setting `HOME`.
- **CLI (relevant flags):**

  | Flag | Meaning | Default |
  |---|---|---|
  | `--bam_filepath` | MD-tagged, indexed BAM | — |
  | `--annotation_bedfile_path` | BED6 `contig start end label1 label2 strand` | — |
  | `--output_folder` | created if absent | — |
  | `--cores` | CPUs for analysis | all available |
  | `--strandedness {0,1,2}` | 0=unstranded, 1=stranded, 2=reverse | — |
  | `--min_base_quality` | min base quality | **0** |
  | `--min_read_quality` | min MAPQ (aligner-dependent scale) | **0** |
  | `--contigs` | comma list, e.g. `chr1,chr2` (must match BAM nomenclature) | all |
  | `--paired_end` | dedupe overlapping mate coverage (slower, accurate) | off |
  | `--keep_intermediate_files` | retain intermediates | **off** |
  | `--barcode_tag` / `--barcode_whitelist_file` | single-cell only — **omit for bulk** | — |

- **Canonical output:** `{output_folder}/final_filtered_site_info.tsv` (singular "site").
  MARINE skips edit-finding if this file already exists. Columns consumed by
  `parse_marine`: `contig, position, strand, editing_type, coverage, edited_reads,
  edit_frequency`.

## 4. Requirements

Functional requirements, traceable to the original task list (phases preserved in §9).

- **R1 — Branch.** Work on `feature/marine_integration`.
- **R2 — Container validation.** `scripts/validate_containers.sh` (TOOLS=marine) must pass
  against `singularity/marine.sif`. Requires fixing `containers/marine/validate.sh`
  (§3: wrong path) and adding the cache-dir env vars. If the existing prebuilt SIF clears
  validation it is reused as-is; the corrected Dockerfile/validate.sh are committed.
- **R3 — Annotation generation.** Re-activate `generate_marine_annotation`: parse all
  `gene` features from `config.references.gtf` into BED6
  (`chrom  start(0-based)  end  gene_name  gene_type  strand`), sorted, written to
  `config.references.marine_annotation_bed`. (Uses `gawk` match groups — confirm `gawk`
  availability in the container used for this rule.)
- **R4 — MARINE rule.** Re-activate `rule marine` running inside `marine.sif`:
  - Input: MD-tagged indexed BAM (`results/mapped/{aligner}/{condition}_{sample}.rmdup_MD.bam`
    from `add_md_tag`) + the R3 annotation BED.
  - Output: `results/tools/{aligner}/marine/{condition}_{sample}/final_filtered_site_info.tsv`.
  - `--cores` **must equal** the rule's `threads`.
  - `--min_read_quality` **must** come from config (see DD2).
  - `--strandedness` from `config.params.marine.strandedness` (default 2 per task list —
    **note current config default is 0**, see DD3).
  - `--paired_end` emitted **only** when the sample is paired-end. The task list ties this
    to "if paired-end fastqs are supplied"; `is_paired(condition, sample)` (Snakefile:90)
    is the authoritative per-sample signal. `config.params.marine.paired_end` should gate
    this too (see DD4).
  - No `--barcode_tag` / `--barcode_whitelist_file` (bulk).
  - Intermediate files not kept (default; do **not** pass `--keep_intermediate_files`).
  - Resources modeled on REDItools2 (per task list).
- **R5 — No regression.** A dry-run + a real small-example run
  (`examples/Morales_et_al_small`) produces all pre-existing `rule all` targets unchanged,
  plus the new MARINE outputs.
- **R6 — Comparison wiring.** MARINE participates in the cross-tool comparison matrices,
  intersection/Jaccard, per-output-type correlation, **and** the consensus analysis —
  i.e. marine is added to `_BED_TOOLS`, contingent on solving §6.
- **R7 — Docs.** `README`, `CHANGELOG`, and `docs/tools_reference.md` updated. Each phase
  is committed to git and reflected in beads so the work is human- and agent-traceable.

## 5. Design decisions (require sign-off)

These are choices the task list left implicit or under-specified. Per project convention,
they are surfaced rather than chosen silently.

### DD1 — Parallelization: split-BAM-per-chrom vs. native `--contigs`
The task list says: "use the same split-bam strategy that splits a full-sized BAM into
chromosomes, **and** use `--contigs` to run MARINE in parallel across all chromosomes."
These are two different parallelism models and are partly redundant:

- **Option A (mirror REDItools, literal reading):** `checkpoint get_chrom_list` →
  `split_bam_by_chrom` → one `marine` job per chrom (single-chrom BAM, `--contigs <chrom>`)
  → join, keeping a single header. Gives SLURM-level parallelism and per-chrom retry
  granularity; matches the existing `reditools_by_chrom` pattern exactly. **Downside:** a
  single-contig job benefits little from `--cores`, and MARINE re-loads the annotation +
  spins up its own interval machinery per job.
- **Option B (native):** one `marine` job on the full BAM with `--contigs chr1,...,chrN`
  and `--cores {threads}`; MARINE parallelizes internally over contigs/intervals. Simpler
  DAG, one annotation load, fewer scheduler jobs. **Downside:** one large job, coarser
  retry, peak memory across all contigs at once.

**Recommendation: Option A** for consistency with the rest of the suite and the task list's
explicit instruction, joining per-chrom `final_filtered_site_info.tsv` with the header kept
from the first file only (mirror `join_reditools_output`). Confirm before implementing.

### DD2 — `--min_read_quality` source
Task list: "`--min_read_quality` matches config.yaml." MARINE's `--min_read_quality` is a
**MAPQ** filter. The natural match is the per-aligner `map_quality: 20` used by other tools
(`reditools3.map_quality`, `redinet.map_quality`, etc.), not `common.base_quality`.
**Proposal:** map `--min_read_quality` ← a new `params.marine.min_read_quality` (default
20), and **also** set `--min_base_quality` ← `params.common.base_quality` (30) for harmony
with the other callers, even though the task list mentions only read quality. Confirm
whether base-quality harmonization is in scope.

### DD3 — `--strandedness` default
Task list: "default `--strandedness` should be 2, but let this be configurable." The config
key already exists but is currently `0`. **Proposal:** keep it configurable via
`params.marine.strandedness`; set the documented/default value to **2** in the production
config and explain in `tools_reference.md` why (most stranded RNA-seq libraries). Confirm
the intended default for the small-example config (it may legitimately differ).

### DD4 — `--paired_end` gating
Two signals exist: the per-sample `is_paired()` (truthful, from the samplesheet) and the
global `params.marine.paired_end` flag. **Proposal:** pass `--paired_end` only when the
sample is paired-end *and* the config flag is true (config acts as a global override to
force single-end coverage counting). Confirm precedence.

### DD5 — `validate.sh`/Dockerfile correction
`containers/marine/validate.sh` references a non-existent path and uses `conda run`, which
fails under the SIF. **Proposal:** correct it to call `/opt/marine/marine.py --help` via the
env's python with the cache-dir env vars set. This changes the committed Dockerfile context;
the existing SIF is kept if it still validates.

## 6. The "outputs too large" problem (gating R6)

The original `rule marine` was disabled with the note *"outputs too large for
compare_all_tools matrix"*, and `Snakefile:87` excludes marine from `_BED_TOOLS`. The
comparison matrices are keyed on the **union** of all tools' called sites; MARINE emits
genome-wide, all-conversion-type rows, which inflates the matrix and the downstream
correlation/consensus.

**Constraint:** before adding marine to `_BED_TOOLS`, its contribution must be reduced to
the comparable site set. `parse_marine` already filters to A→I/T→C edit types via
`EDIT_TYPES`; it does **not** yet apply a coverage floor. **Proposal:** filter MARINE sites
to `editing_type ∈ {AG, TC}` **and** `coverage ≥ params.common.min_coverage` at parse time
(consistent with how other callers are floored), so marine's footprint matches the others.
Verify on the small example that the matrices and `compare_outputs.py` consensus still build
in reasonable time/memory. If the footprint is still prohibitive, fall back to leaving marine
in BigBed/trackhub only and document the exclusion from the matrix.

## 7. Affected files

- `containers/marine/{Dockerfile,validate.sh}` — fix entrypoint path + cache env (DD5).
- `pipelines/Morales_et_al/rules/references.smk` — re-activate `generate_marine_annotation`.
- `pipelines/Morales_et_al/rules/tools.smk` — re-activate `rule marine` (+ split/join rules
  if DD1=Option A), container-based, cache env vars, `--cores {threads}`.
- `pipelines/Morales_et_al/rules/visualization.smk` — add `marine` to `_TOOL_OUTPUT`
  template map (`{condition}_{sample}/final_filtered_site_info.tsv`).
- `pipelines/Morales_et_al/Snakefile` — remove `marine` from the `_BED_TOOLS` exclusion
  (line 87) and add the marine target to `rule all` (gated by §6).
- `pipelines/Morales_et_al/scripts/compare_all_tools.py` — add coverage floor in
  `parse_marine` (§6).
- Config: `examples/Morales_et_al_small/config_small.yaml` (+ production config) — add
  `containers.marine`, `params.marine.min_read_quality`, set strandedness default (DD3).
- Docs: `README`, `CHANGELOG`, `docs/tools_reference.md`.

## 8. Acceptance criteria

1. **AC1 (R2):** `TOOLS=marine scripts/validate_containers.sh` exits 0; `validate-marine`
   inside the SIF runs `marine.py --help` successfully with cache env vars set.
2. **AC2 (R3):** `generate_marine_annotation` produces a sorted BED6 at
   `references.marine_annotation_bed` with one row per GTF `gene`, columns
   `chrom start end gene_name gene_type strand`.
3. **AC3 (R4):** For each `{aligner}/{condition}_{sample}`, `rule marine` produces a
   non-empty `final_filtered_site_info.tsv`; the invocation passes `--cores == threads`,
   the config-driven `--min_read_quality`/`--strandedness`, `--paired_end` per DD4, and
   **no** barcode flags; no intermediate files remain.
4. **AC4 (R5):** `snakemake --dry-run` on `config_small.yaml` lists the new marine targets
   and **all** pre-existing `rule all` targets; a real small-example run reproduces the
   pre-existing outputs unchanged (spot-check a sample of matrices/figures).
5. **AC5 (R6):** marine columns appear in
   `results/compare_all_tools/edit_*_matrix.tsv`, in the intersect/Jaccard and
   per-output-type correlation outputs, and in the consensus analysis, with matrix build
   time/memory within the same order as before (§6 verified).
6. **AC6 (R7):** README, CHANGELOG, and `docs/tools_reference.md` describe MARINE (inputs,
   params, output, parallelization model, comparison treatment); each implementation phase
   has a corresponding git commit and beads update.

## 9. Implementation phases (commit + beads update after each)

0. Create branch `feature/marine_integration`. → verify: `git branch` shows it.
1. Read MARINE bulk docs; fix + validate the container (DD5, AC1). Commit Dockerfile/
   validate.sh. → verify: `validate_containers.sh` green.
2. Re-activate `generate_marine_annotation` (AC2). → verify: BED6 row count ≈ GTF gene count.
3. Re-activate `rule marine` (+ split/join per DD1) with config wiring (AC3). → verify:
   single-sample run yields `final_filtered_site_info.tsv`; one header after join.
4. Small-example regression run (AC4). → verify: dry-run + real run, diff pre-existing
   targets.
5. Solve §6 and wire marine into comparison + consensus (AC5). → verify: matrices/consensus
   include marine and still build.
6. Update README, CHANGELOG, `tools_reference.md` (AC6). → verify: docs mention MARINE; final
   commit + push.

## 10. Open questions

- DD1/DD2/DD3/DD4 sign-off (parallelism model, quality-flag sources, strandedness default,
  paired-end precedence).
- §6: is matrix inclusion required, or is BigBed/trackhub-only acceptable if MARINE's
  filtered footprint is still too large?
- Production `config.yaml` (full inputs) is referenced by the suite but only the small
  example config was inspected here; confirm the production config gets the same new keys.
