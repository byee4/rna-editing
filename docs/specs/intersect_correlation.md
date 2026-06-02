# Spec: Harmonized edit calling + output-type-aware correlation

Status: **DRAFT — awaiting review**
Author: Claude (for Brian Yee)
Date: 2026-05-29
Scope: `pipelines/Morales_et_al/`

## 1. Motivation

Cross-tool Spearman correlations (`results/correlation/tool_correlation_*.tsv`) are
near-zero for almost every tool pair. Two root causes:

1. **Comparison artifact.** Correlation runs over the **union** of called sites
   (`(a>0)|(b>0)`) on an 18.9M-position matrix, so most compared positions have a real
   value for one tool and an imputed `0` for the other → it measures presence/absence
   disagreement, not agreement on shared sites. And it mixes **incomparable output types**
   (editing fraction vs QUAL vs supporting-read count vs group statistic) into one matrix.
2. **Non-equivalent calling.** Tools use different base-quality, coverage, reference, and
   SNP/repeat filters, so their site sets are disjoint for procedural reasons (see §2).

This spec does two things:

- **Part A (pipeline):** harmonize base-quality, min-coverage, edit-type, and
  SNP/repeat/Alu filtering across callers so site-set differences reflect the algorithms,
  not the parameters.
- **Part B (analysis):** replace the single mixed correlation with **intersection-based,
  output-type-grouped** comparisons (one plot per output type), plus a co-called edit table
  and presence/Jaccard overlap.

## 2. Input & parameter equivalence audit (current state — the problem Part A fixes)

### 2.1 Inputs

| Tool | BAM input | Reference |
|---|---|---|
| reditools (`reditools.py`) | `{aligner}/{cond}_{samp}.rmdup.bam` | `config.references.fasta` |
| reditools3 | `.rmdup.bam` | **`results/references/ref_iupac_masked.fasta`** (IUPAC-masked) |
| bcftools | `.rmdup.bam` | `config.references.fasta` |
| red_ml | `.rmdup.bam` | `config.references.fasta` |
| redinet (`REDItoolDnaRna.py`) | `.rmdup.bam` (per-chrom split) | `config.references.fasta` |
| sprint | **`.rmdup_mapq30.bam`** (star/hisat2) / `.rmdup.bam` (bwa) | `config.references.fasta` |
| jacusa2 | **`.rmdup_MD.bam`**, **WT group vs ADAR1KO group** (not per-sample) | `config.references.fasta` |

Functionally-required input divergences that we **keep** (documented, not changed):
- **reditools3** masked reference, **sprint** MAPQ rewrite (SPRINT rejects MAPQ=255),
  **jacusa2** group test + MD tag. These are intrinsic to the tools.

### 2.2 Parameters (current `config.yaml` + hardcoded shell in `tools.smk`)

| Tool | map-q | base-q | min cov | edit type | dbSNP/repeat/Alu |
|---|---|---|---|---|---|
| reditools | 20 | **20 (hardcoded)** | none | all subs | none |
| reditools3 | 20 | **30** | none | all subs | none |
| bcftools | 20 | 20 | max-depth only | all variants | none |
| red_ml | default | default | default | A→I | **dbSNP+simpleRepeat+Alu** |
| redinet | 20 | 20 | **5** | A→I | none |
| jacusa2 | default | default | default | all subs | none |

Inconsistencies Part A targets: base-quality (20 vs 30 vs default), min-coverage
(none vs 5 vs default), edit type (only enforced downstream in the parser), SNP/repeat/Alu
(only red_ml).

---

# PART A — Pipeline harmonization

## 3. Single source of truth: `params.common` in `config.yaml`

```yaml
params:
  common:
    base_quality: 30      # applied wherever a caller exposes a base-quality filter
    min_coverage: 10      # production config.yaml; the small examples/ config uses 5
    edit_type: "AG"       # canonical A→I edit; reverse-strand complement "TC" derived automatically
  # ...existing per-tool blocks remain for tool-specific knobs not covered by common...
```

- `base_quality` and `min_coverage` become the **only** place these two filters are set.
  Per-tool `base_quality`/`min_cov`/`min_column` keys are removed and replaced by
  references to `params.common`.
- `edit_type` is a single substitution code (`REF` + `ALT`, plus-strand orientation). The
  reverse-strand complement is computed in code (`AG`→`TC`, `CT`→`GA`, …) so callers and
  parsers agree on both strands.
- Map-quality is **out of scope** (already 20 across callers); left untouched.

> **Decided:** `base_quality: 30` everywhere. `min_coverage: 10` in the production
> `config.yaml`; the small `examples/` config sets `common.min_coverage: 5` (the tiny test
> dataset would otherwise be zeroed out).

## 4. Apply `common` filters per tool (`rules/tools.smk`)

For each caller, wire `params.common.base_quality` / `params.common.min_coverage` into the
flag the tool actually exposes. **Every flag below is marked VERIFY and will be confirmed
against the container's `--help` in build Phase 0 before wiring** (do not assume a flag
exists if `--help` disagrees — surface it instead).

| Tool | base-quality flag | min-coverage flag | notes |
|---|---|---|---|
| reditools (`reditools.py`) | `-bq {common.base_quality}` (replaces hardcoded 20) | `-c {common.min_coverage}` (VERIFY `-c`/`--min-column-length`) | stop hardcoding in shell |
| reditools3 (`reditools analyze`) | `-bq {common.base_quality}` (drop per-tool 30) | VERIFY flag exists; if none, post-filter on `Coverage-q30` column | |
| bcftools | `-Q {common.base_quality}` | post-call `bcftools view -e 'INFO/DP<{common.min_coverage}'` | mpileup has no min-cov; filter step |
| red_ml | VERIFY `red_ML.pl` exposes base-q; if not, **leave default + document** | VERIFY; if not, leave default | per instruction, ignore unexposed knobs |
| redinet (`REDItoolDnaRna.py`) | `-q 0,{common.base_quality}` | `-c 0,{common.min_coverage}` (replaces 5) | already structured this way |
| sprint | not exposed → **leave + document** | not exposed → **leave + document** | SPRINT has no such CLI knobs |
| jacusa2 | VERIFY `-q`/min-basecall-quality | VERIFY `-c`/min-coverage | group caller; apply if exposed |

Rule: where a tool **does not** expose the knob, leave it at the tool default and record
that in the rule comment + this table. Do **not** bolt on external pre-filtering to fake it.

## 5. dbSNP / simpleRepeat / Alu filtering (only where natively supported)

Resources already in `config.references`: `dbsnp`, `simple_repeat` (BED), `alu_bed`.

| Tool | Native support? | Action |
|---|---|---|
| red_ml | Yes (`--dbsnp --simpleRepeat --alu`) | **mostly unchanged**; make `--alu` conditional — pass it only if `config.references.alu_bed` is set **and the file exists**, else omit (red_ml runs without Alu) |
| bcftools | Yes (region exclusion) | add dbSNP + simpleRepeat **exclusion** via `bcftools view -T ^<bed>` (or `annotate`+`-e`); **Alu is not an exclusion** (it is an editing-enriched region red_ml uses as a positive feature) → not applied as a filter. VERIFY coordinate/format conversion of dbSNP txt→BED. |
| reditools / reditools3 | No native SNP/repeat exclusion in the main call | **leave (ignore, per instruction)** |
| redinet | No | **leave** |
| sprint | Uses `rmsk` internally for repeat-awareness; no dbSNP/Alu CLI | **leave (already repeat-aware via rmsk)** |
| jacusa2 | BED feature filtering possible (VERIFY) | if VERIFY confirms a BED exclusion filter, apply dbSNP+simpleRepeat; else leave |

**Annotation prep — dedicated rule + container (decided).** The dbSNP txt→BED conversion
and any sort/merge of dbSNP/simpleRepeat/Alu BEDs are factored into their **own rule**
(`prepare_editing_filters`) rather than inlined into a caller's shell or bundled into the
`wgs` image. That rule runs a standalone **bedtools** container pulled directly from Docker
Hub (no local Dockerfile):

```
module load singularitypro
singularity pull -F singularity/bedtools.sif docker://biocontainers/bedtools:v2.28.0_cv2
```

`config.containers.bedtools` points at the resulting SIF; `container_for("bedtools")`
resolves it. The rule emits normalized, sorted/merged BEDs that the `bcftools` rule then
consumes for region exclusion.

**Alu semantics (decided):** Alu is used the way RED-ML uses it — a positive region/feature,
not a universal exclusion filter. We do **not** apply Alu as a filter to other tools (doing
so would remove most true A→I sites). Alu usage (red_ml `--alu`) is **conditional on
`config.references.alu_bed` being set and the file existing**; if absent, Alu is dropped
from filtering entirely.

## 6. Edit type enforced everywhere

- New `params.common.edit_type` (default `"AG"`).
- **Callers:** none of the per-sample callers restrict substitution type at call time
  (red_ml/redinet are A→I by design; the rest emit all substitutions). So call-time
  behavior is unchanged.
- **Enforcement point = the comparison layer.** `compare_all_tools.py` currently hardcodes
  `("AG", "TC")` in six parsers. Replace with a single `--edit-type AG` argument; the
  script derives the strand complement and filters **all** tool parsers to exactly that
  edit (and its reverse complement). This guarantees every tool's matrix contains the same
  edit class.
- `compare_all_tools` rule passes `--edit-type {config[params][common][edit_type]}`.

---

# PART B — Output-type-aware, intersection-based comparison

## 7. Output-type registry

Each tool natively produces one or more quantities. We compare **only like with like**.

| Output type | Definition | Member tools (source) | Plot |
|---|---|---|---|
| `site_fraction` | editing fraction 0–1 at a position | reditools, reditools3, red_ml, redinet (fraction matrix) | `per-site-fraction-correlation.png` |
| `gene_fraction` | coverage-weighted editing fraction per gene | reditools, reditools3, red_ml, redinet (fraction×coverage, aggregated via GTF) | `per-gene-fraction-correlation.png` |
| `quality_score` | per-site confidence | red_ml (P_edit), redinet (ed_proba), bcftools (QUAL) — score matrix | `qual-or-score-correlation.png` |
| `read_count` | reads supporting the edit | reditools, reditools3 (fraction×coverage = edited reads), sprint (supporting reads, score matrix) | `read-count-correlation.png` |
| `group_score` | two-condition comparison statistic | jacusa2 (score matrix) | `group-or-comparison-score.png` |

Registry lives in the new script as a dict so adding a tool/type is one line:

```python
TOOL_OUTPUT_TYPES = {
    "reditools":  {"site_fraction": "fraction", "read_count": "edited_reads"},
    "reditools3": {"site_fraction": "fraction", "read_count": "edited_reads"},
    "red_ml":     {"site_fraction": "fraction", "quality_score": "score"},
    "redinet":    {"site_fraction": "fraction", "quality_score": "score"},
    "sprint":     {"read_count": "score"},
    "bcftools":   {"quality_score": "score"},
    "jacusa2":    {"group_score": "score"},
}
# value tokens: "fraction"->fraction matrix, "score"->score matrix,
#               "edited_reads"-> fraction matrix * coverage matrix
```

- `group_score` has a single member with the current toolset → no pairwise correlation
  possible. The script emits the table/plot only when a type has **≥2 member tools**;
  otherwise it logs "skipped (1 tool)" and writes a stub TSV documenting the single tool.
  (Kept in the registry so it activates automatically if a second group caller is added.)

## 8. Comparison method (intersection)

All output-type correlations and the co-call table use **intersection**, not union:

- Per aligner, collapse each tool's per-sample columns to one vector (mean across samples
  for fraction/score/edited_reads; presence = called in ≥1 sample).
- **Presence** signal = nonzero in `tool_score_matrix.tsv` (universal: every parser writes
  a nonzero score when it emits a site; the fraction matrix can't be used because
  sprint/bcftools/jacusa2 are all-zero there).
- For a tool pair within an output type:
  - `n_overlap` = sites/genes both called,
  - `jaccard` = `|A∩B|/|A∪B|`,
  - `spearman` = Spearman on the type's value over the **intersection** (`a>0 AND b>0`),
    `NaN` if `n_overlap < 3`.

## 9. New script: `scripts/compare_outputs.py` (single streaming pass)

Replaces the analysis role of `tool_correlation.py` and folds in the co-call table. Reads
`edit_fraction_matrix.tsv`, `tool_score_matrix.tsv`, and `edit_coverage_matrix.tsv` in
**lockstep chunks** (the three matrices are row- and column-aligned by construction in
`compare_all_tools.py`), so the ~4.5 GB files are never fully loaded.

```
compare_outputs.py
  --matrix-dir results/compare_all_tools
  --outdir     results/correlation
  --aligners   star bwa hisat2
  --gtf        <config.references.gtf>     # for gene_fraction aggregation
  --min-tools  2                            # co-call table threshold
  --edit-type  AG                           # for record/labeling (filtering already done upstream)
```

GTF handling: parse `gene` features into per-chrom sorted `(start, end, gene_id)` arrays;
map each site to a gene by bisect (sites with no gene are dropped from `gene_fraction`
only). No pyranges dependency (python3essential-safe).

### Outputs (per aligner unless noted)

Co-call / overlap (all tools):
- `intersect/edits_intersect_{aligner}.tsv` — positions called by ≥ `min_tools` tools:
  `chrom  pos  n_tools  tools  <one fraction col per tool>` (blank where not called or
  tool has no fraction).
- `intersect/tool_jaccard_{aligner}.tsv` + `..._overlap_counts_{aligner}.tsv` — presence
  Jaccard / `|A∩B|` over **all** tools (includes sprint/bcftools/jacusa2).

Per-output-type intersection correlation (one TSV + one PNG each, per aligner):
- `by_output_type/per-site-fraction-correlation_{aligner}.{tsv,png}`
- `by_output_type/per-gene-fraction-correlation_{aligner}.{tsv,png}`
- `by_output_type/qual-or-score-correlation_{aligner}.{tsv,png}`
- `by_output_type/read-count-correlation_{aligner}.{tsv,png}`
- `by_output_type/group-or-comparison-score_{aligner}.{tsv,png}` (stub if 1 tool)

Each correlation TSV also carries a companion `*_noverlap_{aligner}.tsv` with the pairwise
`n_overlap` so a high/low r can be read alongside its support.

Heatmaps reuse `plot_heatmap` from `tool_correlation.py` (Spearman: `vmin=-1,vmax=1`;
Jaccard plot: `vmin=0,vmax=1`).

## 10. Snakemake / config / rule-all wiring

**`rules/visualization.smk`** — add one rule, mirroring `tool_correlation`:

```python
rule compare_outputs:
    """Intersection co-call table + per-output-type correlation plots."""
    input:
        fraction="results/compare_all_tools/edit_fraction_matrix.tsv",
        score="results/compare_all_tools/tool_score_matrix.tsv",
        coverage="results/compare_all_tools/edit_coverage_matrix.tsv"
    output:
        expand("results/correlation/intersect/edits_intersect_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/intersect/tool_jaccard_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/per-site-fraction-correlation_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/per-gene-fraction-correlation_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/qual-or-score-correlation_{aligner}.tsv", aligner=_ALIGNERS),
        expand("results/correlation/by_output_type/read-count-correlation_{aligner}.tsv", aligner=_ALIGNERS),
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: 12000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 90 * (2 ** (attempt - 1))
    log:
        stdout="results/logs/compare_outputs.out",
        stderr="results/logs/compare_outputs.err"
    params:
        script=os.path.join(_VIZ_SCRIPTS, "compare_outputs.py"),
        outdir="results/correlation",
        aligners=" ".join(_ALIGNERS),
        gtf=config["references"]["gtf"],
        edit_type=config["params"]["common"]["edit_type"],
        min_tools=config.get("params", {}).get("common", {}).get("min_tools", 2)
    shell:
        r"""
        set -euo pipefail
        module load python3essential
        python3 {params.script} \
            --matrix-dir results/compare_all_tools \
            --outdir {params.outdir} \
            --aligners {params.aligners} \
            --gtf {params.gtf} \
            --edit-type {params.edit_type} \
            --min-tools {params.min_tools} \
            1> {log.stdout} 2> {log.stderr}
        """
```

**`compare_all_tools` rule** — add `--edit-type {config[params][common][edit_type]}`.

**`Snakefile` `rule all`** — replace the mixed
`expand("results/correlation/tool_correlation_{aligner}.tsv", ...)` target with the new
`compare_outputs` outputs (per-output-type + intersect). Keep `aligner_correlation_*`
(different axis: per-tool across aligners) unchanged.

**Removal (done in Part B):** the `tool_correlation` rule and `scripts/tool_correlation.py`
are deleted; `compare_outputs.py` is self-contained (carries its own `plot_heatmap`). The
old `results/correlation/tool_correlation_*` files are no longer produced.

## 11. Resolved decisions

1. **Filter values — DECIDED.** `base_quality: 30` everywhere. `min_coverage: 10` in
   production `config.yaml`; `5` in the small `examples/` config.
2. **Alu — DECIDED.** Alu is a positive feature (red_ml only), never an exclusion filter.
   `--alu` is passed only when `config.references.alu_bed` is set and the file exists; else
   omitted.
3. **bcftools dbSNP+simpleRepeat exclusion — DECIDED: add it** (native region filtering;
   includes the UCSC dbSNP txt→BED conversion).
4. **Old mixed `tool_correlation` plot — DECIDED: remove** from `rule all` in favor of the
   per-output-type plots (script retained only for its `plot_heatmap` helper).

## 12. Files touched

Part B (done):
- **new** `pipelines/Morales_et_al/scripts/compare_outputs.py`
- **new** `tests/test_compare_outputs.py`
- **deleted** `pipelines/Morales_et_al/scripts/tool_correlation.py` (mixed correlation)
- **edit** `pipelines/Morales_et_al/rules/visualization.smk` (add `compare_outputs`; drop old `tool_correlation`)
- **edit** `pipelines/Morales_et_al/Snakefile` (`rule all` targets)

Part A (pending):
- **pull** `singularity/bedtools.sif` from `docker://biocontainers/bedtools:v2.28.0_cv2` (no Dockerfile)
- **edit** `config.yaml` (`containers.bedtools` entry — done; `params.common`; remove per-tool base_quality/min_cov keys — pending)
- **edit** `pipelines/Morales_et_al/scripts/compare_all_tools.py` (`--edit-type` arg; remove hardcoded `("AG","TC")`)
- **edit** `pipelines/Morales_et_al/rules/references.smk` (new `prepare_editing_filters` rule using the bedtools container)
- **edit** `pipelines/Morales_et_al/rules/tools.smk` (wire `common.base_quality`/`min_coverage`; bcftools dbSNP+simpleRepeat exclusion; conditional red_ml `--alu`; jacusa2 filters where supported)
- **edit** `pipelines/Morales_et_al/rules/visualization.smk` (pass `--edit-type` to `compare_all_tools`)

## 13. Test plan

- **Unit** `tests/test_compare_outputs.py`: hand-built tiny score/fraction/coverage matrices
  (covering all five output types) + a 2-gene GTF. Assert: Jaccard/overlap match by hand;
  co-call table has exactly the ≥min_tools positions; intersection Spearman ignores
  `a==0 or b==0`; `read_count`/`gene_fraction` derivations (`fraction×coverage`,
  gene aggregation) are correct; single-member `group_score` produces a stub, not a crash.
- **Edit-type unit**: extend `compare_all_tools` test to confirm `--edit-type CT` filters
  to `CT`/`GA` and `AG` filters to `AG`/`TC`.
- **Flag verification (Phase 0 of build)**: run each container's `--help` and record the
  real base-quality/min-coverage/SNP-filter flags into §4/§5 before editing `tools.smk`.
- **Smoke run** on existing matrices in `examples/Morales_et_al` (no re-alignment):
  `python3 scripts/compare_outputs.py --matrix-dir results/compare_all_tools
   --outdir /tmp/cmp --aligners star bwa hisat2 --gtf <gtf> --edit-type AG`.
  Sanity: reditools↔reditools3 high in `site_fraction`; redinet⊆reditools overlap reflects
  containment; `qual-or-score` compares red_ml/redinet/bcftools only.
- **Dry-run DAG**: `snakemake -n` reaches `compare_outputs` targets; old `tool_correlation`
  target absent.

## 14. Acceptance criteria

1. `config.params.common` is the sole definition of base-quality, min-coverage, edit-type;
   no per-tool duplicate of these three remains.
2. Each caller in `tools.smk` either consumes `common.base_quality`/`common.min_coverage`
   via its native flag, or has a comment stating the knob is unexposed and left default
   (verified against `--help`).
3. dbSNP/simpleRepeat/Alu filtering is enabled for every tool that natively supports it
   (red_ml unchanged; bcftools dbSNP+simpleRepeat if §11.3 approved); others explicitly left.
4. `compare_all_tools.py` filters all tools to `config.params.common.edit_type`
   (+ strand complement); no hardcoded edit type remains.
5. One correlation TSV+PNG per output type is produced per aligner, each comparing only the
   tools that produce that type; `qual-or-score` excludes the fraction tools; `group_score`
   degrades gracefully to a stub with one member.
6. All correlations use intersection (`a>0 AND b>0`) and ship a companion `n_overlap` table.
7. `edits_intersect_{aligner}.tsv` + Jaccard/overlap matrices (all tools) exist.
8. Script streams matrices in chunks (peak RSS << matrix size); unit tests pass;
   `snakemake -n` includes the new targets.
