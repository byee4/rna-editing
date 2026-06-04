# Spec: integrate GIREMI, LoDEI, REDITs, and EditPredict into the Morales_et_al benchmark

Status: **DRAFT — decisions signed off; ready to implement**
Author: Claude (for Brian Yee)
Date: 2026-06-03
Scope: `pipelines/Morales_et_al/`, `containers/{giremi,lodei,redits,editpredict}/`, `scripts/`, `docs/`
Tracking: `rna-editing-jpg`

### Revision 2026-06-03 (post-review sign-off)
- **DD1/DD5 merged → one shared candidate set.** A single mpileup-derived candidate-site
  list (independent of any caller) feeds **both** GIREMI and EditPredict. EditPredict is no
  longer pinned to SPRINT.
- **DD6 upgraded.** Because EditPredict now scores the *independent* shared candidate set
  (not SPRINT's orthogonal output), it becomes a first-class **comparable classifier** —
  analogous to REDInet/RED-ML classifying a candidate table — and joins
  `_COMPARE_TOOLS`/consensus, not BigBed-only.
- **DD2/DD3/DD4 accepted as recommended** (separate `lodei_comparison`; REDITs as a
  downstream stats stage on one default caller; dedicated `containers/{giremi,redits}/`).
- **Upstream facts verified** (GIREMI ships a *precompiled* binary + `giremi.r` + `mark_snp.py`,
  needs `libhts.so.1`; REDITs is base-R only). Dockerfiles for the two green-field tools are
  written (see §7).

## 1. Motivation

`pipelines/Morales_et_al/Snakefile` benchmarks A-to-I editing callers (REDItools2/3, SPRINT,
RED-ML, BCFtools, REDInet, JACUSA2 call-1/2, MARINE) and wires them through a common
comparison/consensus layer (`compare_all_tools.py`, `consensus_characteristics.py`,
`tool_output_to_bed.py`, trackhub). The goal is to add four more methods — **GIREMI**,
**LoDEI**, **REDITs**, and **EditPredict** — so they appear alongside the existing tools.

## 2. The central finding: these four tools are NOT the same kind of thing

This is the most important point in the spec and it drives everything else. The existing
suite is built around one dominant shape: a **per-sample, RNA-only, candidate-or-pileup
caller** that emits a table of sites, which `_BED_TOOLS` / `_COMPARE_TOOLS` then fold into
the per-sample comparison matrices and consensus. The four requested tools span **three
different shapes**, only one of which fits that mold:

| Tool | Shape | Closest existing analog | Fits per-sample matrix? |
|---|---|---|---|
| **GIREMI** | Per-sample, RNA-only, **candidate-based** de-novo caller (needs an SNV candidate list + dbSNP + strand) | reditools / red_ml | **Yes** — drop-in per-sample tool |
| **EditPredict** | Per-site **CNN scorer/filter** — classifies *candidate positions supplied to it*, does not discover sites | REDInet / RED-ML (classify a candidate table) | **Yes — classifier over the shared candidate set (DD5/DD6)** |
| **LoDEI** | **Two-condition differential** caller over BAM groups (windowed) | JACUSA2 **call-2** | **No** — per-comparison, not per-sample (like jacusa2 call-2, which is excluded) |
| **REDITs** | **Statistical test (R)** on per-site edited/total **count matrices** across samples (REDIT-LLR / REDIT-regression) | (none; downstream stats layer) | **No** — consumes a matrix, emits per-site p-values |

**Implication:** "integrate all four the same way" is not achievable, and pretending it is
would produce a misleading benchmark. GIREMI is a true drop-in. EditPredict, LoDEI, and
REDITs each need a deliberate placement decision (§5). The existing suite already contains
the precedent for two of these shapes: JACUSA2 call-2 is a differential caller that is
**excluded** from the per-sample matrices but kept as its own output (`Snakefile:80-87`),
and the comparison matrices themselves are the count-matrix substrate REDITs would consume.

## 3. Current state (what already exists)

| Tool | Container dir | SIF | Wired into Morales? | Notes |
|---|---|---|---|---|
| **GIREMI** | — (none) | — | No | **Green-field**: no Dockerfile, no SIF. Needs build. |
| **LoDEI** | `containers/lodei/` | `singularity/lodei.sif` (built) | No | SIF exists (Bioconda `lodei 1.0.0`); `lodei.sif` is currently reused only as a STAR image. Not run as a caller. |
| **REDITs** | — (none) | — | No | **Green-field**: R package from `gxiaolab/REDITs`, no container. |
| **EditPredict** | `containers/editpredict/` | `singularity/editpredict.sif` (built) | No (in Morales) | Container built with `editpredict_score` wrapper + `get_seq.py` patches. **Already integrated (but deactivated) in the *other* pipeline** `pipelines/editing_wgs/rna_editing.smk:162` (`rule editpredict_filter`), where it scores SPRINT `regular.res` positions. |

So two of four containers exist; two must be built. EditPredict additionally has a working
invocation precedent to copy from.

## 4. Verified facts about each tool's CLI / interface

### 4.1 GIREMI (https://github.com/zhqingit/giremi) — green-field
- **Mode:** per-sample, RNA-only, candidate-based. Identifies A-to-I edits by mutual
  information between a candidate SNV's allelic ratio and nearby known SNPs.
- **Inputs:** (a) a coordinate-sorted, indexed BAM; (b) reference FASTA `-f` (with `.fai`);
  (c) a **candidate SNV list** `-l` that GIREMI does **not** generate itself — verified 6-col
  format: `chrom  start(0-based)  end(1-based)  gene|Inte  dbSNP(1/0)  strand(+/-/#)`. The
  dbSNP flag and strand are columns of this list, so the adapter (DD1) must supply both.
- **Invocation (verified README):** `giremi [-m min] [-p paired] [-s strand] -f {ref}.fa
  -l {snv_list} -o {out} {sorted.bam}`. Flags: `-m`←`min_coverage`, `-p`←paired-end,
  `-s`←strandedness (0/1/2 from `_STRAND_FLAGS`).
- **Packaging (verified repo listing):** GIREMI ships a **precompiled binary** `giremi`
  (~164 KB, links `libhts.so.1`) plus `giremi.r` (the GLM/MI R step the binary calls) and
  `mark_snp.py` — *not* a source tree. The container (containers/giremi, §7) provides
  `libhts.so.1` (htslib 1.9 from source) + R + Python and keeps the three files together on
  `PATH`.
- **Strand (DD1a):** the list's strand column is gene-annotation/read-orientation derived, not
  a constant `#` — see DD1a. This is the single biggest accuracy lever for GIREMI.
- **Output:** a table with a per-site `ifRNAE` column (1=MI-predicted, 2=GLM-predicted,
  0=not editing) plus strand/MI/p-value; A-to-I sites are the `ifRNAE∈{1,2}` rows. Needs a
  small parser (`parse_giremi`).

### 4.2 LoDEI (Bioconda `lodei 1.0.0`) — differential, SIF built
- **Mode:** two-condition **differential** editing over groups of BAMs, windowed k-mer
  scan; reports sites/windows with a differential editing score + multiple-testing-corrected
  q-value. Conceptually parallel to JACUSA2 `call-2`.
- **Entrypoint:** `lodei` (container `ENTRYPOINT ["lodei"]`). Subcommand-based; the windowed
  analysis is `lodei windows ...` (exact flags to be confirmed against `lodei windows --help`
  inside the SIF — see AC1). Takes group-A BAM list, group-B BAM list, reference FASTA, and
  an output directory.
- **Container:** `singularity/lodei.sif` already built from `quay.io/biocontainers/lodei`
  plus STAR/samtools/cutadapt/fastqc/multiqc. `validate-lodei` already runs `lodei --help`.
- **Gating:** like JACUSA2, only runs when a two-group comparison is configured. Reuse the
  existing `jacusa2_comparison`-style block (or a new `lodei_comparison`) — see DD2.

### 4.3 REDITs (https://github.com/gxiaolab/REDITs) — statistical test, green-field
- **Mode:** **not a caller.** An R library of beta-binomial tests:
  - **REDIT-LLR** — likelihood-ratio test comparing edited/total counts between two groups.
  - **REDIT-regression** — generalized regression for continuous/multi-level designs.
- **Input:** a matrix of per-site `[edited, total]` (or `[edited, unedited]`) counts, one
  column per sample, plus a group/design vector. It is invoked from R, not a CLI.
- **Natural substrate in this repo:** the comparison layer already builds
  `edit_coverage_matrix.tsv.gz` and `edit_fraction_matrix.tsv.gz` (per-site coverage and
  edited-fraction across samples/tools). REDITs would consume the **per-site edited-count /
  coverage** for a single caller (e.g. REDItools) across the two conditions and emit a
  per-site p/q-value table. So REDITs is a **downstream differential-statistics stage**, not
  a `_BED_TOOLS` entry (see DD3).
- **Container:** needs R + the `REDITs` source sourced into an R script wrapper. The existing
  `morales_downstream.sif` (R-based) or `red_ml.sif` (R 4.3.2) are candidate base images
  (DD4).

### 4.4 EditPredict (https://github.com/wjd198605/EditPredict) — scorer/filter, SIF built
- **Mode:** per-site CNN classifier. `get_seq.py` extracts flanking sequence around each
  candidate position; `editPredict.py` scores it with a pre-trained Alu model
  (`editPredict_construction_alu.h5` + `editPredict_weight_alu.json`).
- **Container wrapper (already built):** `editpredict_score --reference {fa} --positions
  {tsv} --output {txt} [--vcf {vcf.gz}]`. Positions file is `chrom<TAB>pos` (1-based).
  Empty positions → empty output, exits 0 (verified in `editpredict_score`).
- **Precedent:** `pipelines/editing_wgs/rna_editing.smk:162` runs it on SPRINT
  `SPRINT_identified_regular.res` via `scripts/sprint_to_editpredict_positions.py`.
- **Candidate source (RESOLVED — DD5):** EditPredict only *scores* positions it is handed.
  It is fed the **shared mpileup candidate set** (DD1) — the same independent candidate list
  GIREMI uses — converted to its `chrom<TAB>pos` positions TSV by the DD1 adapter.

## 5. Design decisions (require sign-off)

These are surfaced rather than chosen silently, per project convention.

### DD1 — Shared candidate-SNV source (feeds GIREMI **and** EditPredict) — RESOLVED: A
GIREMI and EditPredict both need a candidate-site list they do not produce. **Decision:** one
**shared, caller-independent candidate set** built once per sample by samtools mpileup +
adapter, consumed by both. Rationale: keeps both methods independent of the other callers
(genuine benchmark points), gives them the *same* candidate substrate (so they are directly
comparable), and avoids two candidate-generation paths.

- **A (CHOSEN): samtools mpileup + `mpileup_to_candidates.py` adapter** on the deduplicated
  BAM, floored at `params.common.min_coverage`/`base_quality`, restricted to candidate
  mismatch sites, and annotated with dbSNP membership from `references.dbsnp`. The adapter
  emits **two views** of the same sites:
  - GIREMI's 6-column SNV list: `chrom  start(0-based)  end(1-based)  gene|Inte  dbSNP(1/0)
    strand(+/-/#)` (verified against GIREMI README, §4.1).
  - EditPredict's positions TSV: `chrom<TAB>pos(1-based)` (verified against `editpredict_score`).
- **B (rejected): reuse REDItools2's per-site table** — confounds GIREMI/EditPredict with
  REDItools.

**Performance — per-chromosome split (user requirement).** Genome-wide `samtools mpileup`
is slow, so the candidate-generation step is parallelized **per chromosome**, mirroring the
existing REDItools pattern exactly:
`checkpoint get_chrom_list` → `split_bam_by_chrom` (both already exist in `tools.smk`) →
`candidate_sites_by_chrom` (mpileup + adapter on the single-chrom BAM, `-r {chrom}`) →
`join_candidate_sites` (merge per-chrom candidate lists, single header kept). The per-chrom
BAMs are already produced (and `temp()`-marked) by `split_bam_by_chrom`, so GIREMI/EditPredict
candidate generation reuses them at no extra split cost. GIREMI and EditPredict then run on the
merged candidate set (GIREMI can also run per-chrom directly off the same split BAMs if its own
runtime warrants it — start merged).

**DD1a — strand assignment (do NOT default to `#`).** *(Raised in review — correct and
adopted.)* GIREMI's MI/GLM accuracy depends on the per-site transcript strand (col 6), and
EditPredict needs it to know whether the edit signal is `A>G` (+) or `T>C` (−). Blanket-`#`
would degrade both, especially on stranded libraries. The adapter therefore derives strand,
and reserves `#` **only** for genuinely intergenic sites:

1. **Primary — gene-annotation intersect.** Intersect each candidate position with a
   gene-strand BED6 to assign the transcript strand (`+`/`−`). The repo already builds such a
   BED (`generate_marine_annotation` → `references.marine_annotation_bed`, gene features with
   strand); reuse it (or a dedicated gene BED). Sites with no gene overlap → `gene="Inte"`,
   `strand="#"` — the legitimate, narrow use of `#`.
2. **Refinement / fallback — pileup read orientation (stranded libs).** When
   `params.common.strandedness != unstranded`, the read orientation already encoded in
   `samtools mpileup` (UPPERCASE = forward-mapping read, lowercase = reverse) plus the library
   protocol (`reverse_stranded`/dUTP ⇒ R2 = transcript strand) determines transcript strand
   directly from the data, independent of annotation. Use it to set strand where annotation is
   ambiguous (overlapping genes on both strands) and to **choose the edit candidate**: on a
   `+` transcript keep `A>G` (ref `A`), on a `−` transcript keep `T>C` (ref `T`). For
   `unstranded` libraries, annotation strand is authoritative and both `A>G`/`T>C` mismatches
   are emitted with the annotated strand.
3. GIREMI's own `-s {0,1,2}` flag is set from `config["strand_flags"]["reditools"]`
   (the existing single-source-of-truth `_STRAND_FLAGS`), so GIREMI's read-counting matches
   the strand column the adapter writes.

Net: the strand column is data/annotation-derived, not a constant. `#` appears only for
intergenic sites, which is also what GIREMI's README intends.

**DD1b — newline-safe join (no bare `cat`).** *(Raised in review — correct and adopted.)*
Bare `cat a.tsv b.tsv` fuses A's last line into B's first line if any per-chrom file lacks a
trailing newline. `join_candidate_sites` must use a record-aware merge that (a) guarantees a
newline after every record and (b) keeps exactly one header. Use `awk`, which re-emits each
record with `ORS="\n"` and so cannot fuse lines:
`awk 'FNR==1 && NR!=1 {next} {print}' chr1.tsv chr2.tsv ... > merged.tsv`
(the existing `join_reditools_output` is the precedent to mirror). The adapter itself must
also terminate every line it writes with `\n`. Apply the same awk-merge to the GIREMI-view and
EditPredict-view files. Add an AC that a per-chrom file deliberately stripped of its trailing
newline still merges without a fused row.

### DD2 — LoDEI comparison-group config
LoDEI is differential. Reuse the existing `jacusa2_comparison: {condition1, condition2}`
block, or add a parallel `lodei_comparison`?
- **Recommendation:** add a separate optional `lodei_comparison` block mirroring
  `jacusa2_comparison` (so LoDEI can be enabled/disabled independently and, if desired,
  contrast different groups). When absent, LoDEI is skipped everywhere (mirror `_RUN_JACUSA2`
  → `_RUN_LODEI`).

### DD3 — REDITs placement (the big one)
REDITs is a statistic, not a caller. Two coherent placements:
- **A (recommended): downstream differential stage.** New rule `redits_llr` that takes the
  per-site edited/coverage counts for **one chosen caller** (default REDItools2) across the
  two `*_comparison` conditions, runs REDIT-LLR in R, and writes
  `results/tool_comparison/redits/{aligner}/redit_llr_{caller}.tsv.gz`
  (`chrom pos ... p_value`). It is **not** added to `_BED_TOOLS`/`_COMPARE_TOOLS`; it is a
  new downstream output. Optionally feed multiple callers' matrices.
- **B: skip as a caller, document as out-of-scope.** If a differential-stats layer is not
  wanted in this benchmark, REDITs is the weakest "integration" fit and could be deferred.

**Recommendation: A**, scoped to a single default caller to keep it minimal. Confirm whether
a differential-statistics output belongs in this (largely per-sample-call-overlap) benchmark
at all, or whether REDITs should be deferred (B).

### DD4 — REDITs / GIREMI base images
- REDITs: reuse `morales_downstream.sif` (already R, already in the pipeline) by sourcing
  the `REDITs` `.R` from GitHub at build time, vs. a dedicated `containers/redits/`.
  **Recommendation:** dedicated `containers/redits/` (clean provenance, matches one-tool-one-
  container convention), R 4.x base.
- GIREMI: dedicated `containers/giremi/` (htslib + R + the giremi scripts). Green-field.

### DD5 — EditPredict candidate source — RESOLVED: shared candidate set (DD1)
**Decision:** EditPredict scores the **shared mpileup candidate set** from DD1, *not* SPRINT.
Reasoning: SPRINT is the one tool deliberately excluded from `_COMPARE_TOOLS` (`Snakefile:93`)
as an orthogonal de-novo outlier; building EditPredict on SPRINT would inherit that
distortion. Scoring the independent candidate set instead makes EditPredict a clean classifier
over the same sites GIREMI sees. (The `editing_wgs` SPRINT precedent is left untouched; it is
specific to that SPRINT-centric pipeline.) EditPredict's "called set" = candidate sites whose
EditPredict ed-score ≥ threshold (`params.editpredict.score_threshold`, default per the model).

### DD6 — How EditPredict/GIREMI enter the comparison — RESOLVED (upgraded)
- **GIREMI**: full `_BED_TOOLS` + `_COMPARE_TOOLS` + consensus member (a real per-sample
  caller). Add `parse_giremi` + `to_bed_giremi` + `_TOOL_OUTPUT["giremi"]`.
- **EditPredict**: **also** a full `_BED_TOOLS` + `_COMPARE_TOOLS` + consensus member. Because
  it now classifies the *independent* shared candidate set (DD5), it is directly analogous to
  REDInet/RED-ML (classifiers over a candidate table) — both of which **are** in
  `_COMPARE_TOOLS`. Add `parse_editpredict` (keep sites with ed-score ≥ threshold, filtered to
  `EDIT_TYPES`) + `to_bed_editpredict` + `_TOOL_OUTPUT["editpredict"]`. This supersedes the
  earlier BigBed-only proposal, which only applied while EditPredict was pinned to SPRINT.

## 6. Requirements

- **R0 — Branch.** Work on `feature/giremi_lodei_redits_editpredict` (or per-tool branches
  if implemented incrementally; see §9).
- **R1 — Containers validate.** `TOOLS="giremi lodei redits editpredict"
  scripts/validate_containers.sh` exits 0. `lodei`/`editpredict` SIFs reused if they still
  validate; `giremi`/`redits` containers newly built with `validate-<tool>` scripts.
- **R1b — Shared candidate set (per-chrom).** `candidate_sites_by_chrom` (mpileup +
  `mpileup_to_candidates.py` on each `split_bam_by_chrom` output, container `wgs`) →
  `join_candidate_sites`, producing per-sample GIREMI 6-col SNV list and EditPredict positions
  TSV, floored at `params.common.{min_coverage,base_quality}`, dbSNP-annotated, and
  **strand-assigned per DD1a** (gene-annotation intersect + read orientation for stranded
  libs; `#` only for intergenic). Parallelized per chromosome (genome-wide mpileup is slow),
  reusing the existing `get_chrom_list`/`split_bam_by_chrom` rules. The per-chrom merge uses
  the newline-safe awk join of DD1b, **not** bare `cat`.
- **R2 — GIREMI caller.** Per-sample rule (container `giremi`) producing
  `results/tools/{aligner}/giremi/{condition}_{sample}.txt`, fed by the R1b candidate list,
  configured from `params.common` where GIREMI exposes a knob (`-m` ← min_coverage, `-s` ←
  strand, `-p` ← paired). Starts as one job on the merged candidate set; mirror reditools
  split/join if its own runtime warrants.
- **R3 — LoDEI differential.** Optional rule gated on `lodei_comparison` (DD2), container
  `lodei`, producing `results/tools/{aligner}/lodei/lodei.out` (per aligner, per comparison),
  parsed/plotted like the JACUSA2 call-2 output. Flags driven from `params.common` where
  exposed.
- **R4 — REDITs stats.** Optional downstream rule (DD3) producing a per-site
  p/q-value table from the chosen caller's counts across the comparison conditions.
- **R5 — EditPredict classifier.** Per-sample rule (container `editpredict`) scoring the R1b
  shared candidate positions (DD5) → `results/tools/{aligner}/editpredict/{condition}_{sample}_scores.txt`,
  via the `editpredict_score` wrapper already in the container.
- **R6 — Comparison wiring.** Per DD6: GIREMI **and** EditPredict in matrices + consensus
  (EditPredict filtered to ed-score ≥ threshold); LoDEI as its own differential output (not
  per-sample matrix); REDITs as its own downstream stats output.
- **R7 — Parsers/converters.** `compare_all_tools.py` gains `parse_giremi` (and registry
  entry); `tool_output_to_bed.py` gains `to_bed_giremi` + `to_bed_editpredict`;
  `visualization.smk` `_TOOL_OUTPUT`/`_TOOL_DIR` updated.
- **R8 — No regression.** Dry-run + small-example run (`examples/Morales_et_al_small`)
  reproduces all pre-existing `rule all` targets unchanged, plus the new outputs.
- **R9 — Config.** `examples/Morales_et_al_small/config_small.yaml` (+ production
  `config.yaml`) gain `containers.{giremi,lodei,redits,editpredict}`, any `params.{giremi,
  lodei,redits,editpredict}` knobs, the optional `lodei_comparison` block, and
  `visualization.tools` additions (`giremi`, `editpredict`).
- **R10 — Docs.** `docs/tools_reference.md`, `docs/specs/edit_calling_parameters.md` (flag
  matrix), README, CHANGELOG updated; each phase committed to git + reflected in beads.

## 7. Affected files

- **New containers:** `containers/giremi/{Dockerfile,validate.sh}`,
  `containers/redits/{Dockerfile,validate.sh,redits_llr.R}`.
- **Existing containers (reuse/verify):** `containers/lodei/`, `containers/editpredict/`.
- **New adapters:** `pipelines/Morales_et_al/scripts/mpileup_to_candidates.py` (DD1 — emits
  both the GIREMI 6-col SNV list and the EditPredict positions TSV from one mpileup;
  strand-assigns per DD1a; writes newline-terminated rows per DD1b);
  `containers/redits/redits_llr.R` (bundled in the container).
- **Reference dependency (DD1a):** a gene-strand BED6 for strand assignment — reuse
  `references.marine_annotation_bed` (`generate_marine_annotation`) or add a dedicated gene
  BED; wire it as an input to `candidate_sites_by_chrom`.
- **Rules:** `pipelines/Morales_et_al/rules/tools.smk` — `candidate_sites_by_chrom` +
  `join_candidate_sites` (R1b, per-chrom mpileup), `rule giremi`, `rule editpredict`,
  `rule lodei` (gated), `rule redits_llr` (gated). Possibly a new `rules/differential.smk`
  for LoDEI+REDITs to keep `tools.smk` focused.
- **Comparison:** `scripts/compare_all_tools.py` (`parse_giremi`, `parse_editpredict`,
  registry), `scripts/tool_output_to_bed.py` (`to_bed_giremi`, `to_bed_editpredict`).
- **Snakefile:** add giremi **and** editpredict to `_BED_TOOLS` and `_COMPARE_TOOLS`,
  add `_RUN_LODEI`/comparison plumbing, add new targets to `rule all`.
- **Visualization:** `rules/visualization.smk` `_TOOL_OUTPUT` / `_TOOL_DIR`.
- **Config:** small-example + production configs (R9).
- **Docs:** `docs/tools_reference.md`, `docs/specs/edit_calling_parameters.md`, README,
  CHANGELOG.

## 8. Acceptance criteria

1. **AC1 (R1):** all four `validate-<tool>` scripts pass via `validate_containers.sh`;
   `lodei windows --help` and `giremi`/REDITs entrypoints confirmed inside their SIFs and the
   exact flags recorded in `tools_reference.md`'s orthogonal-verification table.
2. **AC2 (R2):** for each `{aligner}/{condition}_{sample}`, GIREMI produces a non-empty site
   table from the DD1 candidate list; `parse_giremi` filters to `EDIT_TYPES` and GIREMI
   columns appear in `edit_*_matrix.tsv.gz`, intersect/Jaccard, correlation, and consensus.
3. **AC3 (R3):** when `lodei_comparison` is set, LoDEI produces a per-aligner differential
   output with q-values; when the block is absent, no LoDEI rule is scheduled (dry-run
   confirms).
4. **AC4 (R4):** REDITs produces a per-site p/q-value table for the chosen caller across the
   two comparison conditions (or is documented as deferred per DD3-B).
5. **AC5 (R5):** EditPredict produces `*_scores.txt` for each sample from the shared
   candidate positions; empty candidate input yields an empty (exit-0) result; EditPredict
   columns (ed-score-thresholded) appear in `edit_*_matrix.tsv.gz` and consensus, plus a
   trackhub track.
6b. **AC1b (R1b):** `candidate_sites_by_chrom`/`join_candidate_sites` produce, per sample, a
   GIREMI 6-col SNV list and an EditPredict positions TSV covering the same sites; the
   per-chrom dry-run shows one candidate job per chromosome (not a single genome-wide mpileup).
6c. **AC1c (DD1a — strand):** in the GIREMI SNV list, genic candidates carry `+`/`−` from the
   gene annotation (and, for stranded libs, agree with pileup read orientation); `#` appears
   **only** on intergenic (`Inte`) rows — assert no all-`#` output on a stranded sample.
6d. **AC1d (DD1b — join):** a per-chrom candidate file with its trailing newline deliberately
   stripped still merges via `join_candidate_sites` with the correct row count and **no** fused
   line (last row of chrom N kept distinct from first row of chrom N+1).
6. **AC6 (R8):** `snakemake --dry-run` on `config_small.yaml` lists the new targets **and**
   all pre-existing `rule all` targets; a real small-example run reproduces pre-existing
   outputs unchanged (spot-check matrices/figures).
7. **AC7 (R10):** docs describe each tool's mode, command, output, **and its placement
   category** (per-sample caller / post-filter / differential / stats); each phase has a git
   commit + beads update.

## 9. Implementation phases (commit + beads update after each)

Phased so the cleanest, highest-value tool lands first and the heterogeneous ones are
explicit decisions, not surprises. **Each tool is independently shippable.**

0. Branch; DD1–DD6 signed off (done). → verify: `git branch`.
1. **Shared candidate set (R1b)** — the prerequisite for both GIREMI and EditPredict: write
   `mpileup_to_candidates.py`; `candidate_sites_by_chrom` + `join_candidate_sites` (per-chrom,
   reusing `split_bam_by_chrom`). → verify: AC1b — one mpileup job per chrom; both candidate
   views emitted.
2. **GIREMI + EditPredict** (both consume the R1b set): build the GIREMI container (htslib 1.9
   + precompiled binary); `rule giremi` and `rule editpredict`; `parse_giremi`/`parse_editpredict`
   + BED converters; into matrices + consensus. → verify: AC1/AC2/AC5.
3. **LoDEI** (differential): confirm `lodei windows` CLI; `lodei_comparison` config; gated
   rule; parser/figure. → verify: AC3.
4. **REDITs** (stats, most optional): build R container; `redits_llr.R`; downstream rule. →
   verify: AC4 (or document deferral).
5. Small-example regression (AC6) + docs/CHANGELOG (AC7). → verify: dry-run + real run; push.

## 10. Open questions

**Resolved at review (2026-06-03):** DD1 = shared mpileup candidate set (A), per-chrom split;
DD2 = separate `lodei_comparison`; DD3 = REDITs as downstream stats on one default caller (A);
DD4 = dedicated containers; DD5 = EditPredict scores the shared candidate set; DD6 = GIREMI
**and** EditPredict are full comparison/consensus members.

**Still to confirm during implementation (AC1):**
- **REDITs counts source (DD3 detail):** default caller whose per-site edited/coverage feeds
  REDIT-LLR (proposed: REDItools2), and the two comparison conditions (proposed: reuse
  `jacusa2_comparison`/`lodei_comparison` condition1/condition2).
- **Strandedness/quality knobs:** which of `params.common` (base_quality, min_coverage,
  strandedness) GIREMI (`-m/-s/-p` confirmed §4.1) and LoDEI actually expose — LoDEI flags to
  be read from `lodei windows --help` inside the SIF and recorded in the flag matrix.
- **Strand-annotation source (DD1a):** confirm reuse of `references.marine_annotation_bed` as
  the gene-strand BED for candidate strand assignment vs. a dedicated gene BED; and whether
  read-orientation refinement is worth implementing now or deferred to a follow-up (the
  annotation intersect alone already removes the all-`#` degradation).
- **GIREMI runtime libhts:** the precompiled `giremi` binary links `libhts.so.1`; the
  container builds htslib 1.9 from source to provide it (§7 Dockerfile). Confirm the binary
  runs under that lib at validate time; if the soname differs, adjust the htslib version.
- **EditPredict score threshold:** default `params.editpredict.score_threshold` for the
  comparison call-set (read the model's score scale during AC1).
- **Production `config.yaml`:** confirm it receives the same new keys as the small-example
  config (only the small config was inspected here).
```
