# Spec: Tool-comparison refactor (Morales_et_al)

Status: planned · Target: `pipelines/Morales_et_al/Snakefile` + `rules/visualization.smk` + `rules/tools.smk` + configs + docs

This spec applies four adjustments to the Morales_et_al pipeline. Each section lists
the exact edits, the reasoning, and the verification step.

## Summary of changes

1. **Remove SPRINT from the comparison/correlation/consensus analyses** (keep it
   running as a caller and keep its BigBed/trackhub tracks).
2. **Add a MARINE `min_coverage` output filter** (default 5, config-adjustable) on
   top of the existing edit-type filter, so MARINE is assessed with parameters
   comparable to the other callers.
3. **Move `compare_all_tools/`, `consensus/`, and `correlation/`** under a single
   `results/tool_comparison/` parent (subfolders preserved).
4. **Document every figure and table** produced by the comparison stage in `docs/`,
   and **add MARINE** to `docs/consensus_permissivity_analysis.md`.

Decisions confirmed with the user:
- SPRINT: *comparison-only* removal — it still runs and still appears in BigBed/trackhub.
- Folder layout: *nested subfolders* under `tool_comparison/` (names unchanged).

---

## 1. Remove SPRINT from comparison / correlation / consensus

**Problem.** `_BED_TOOLS` (Snakefile lines 84–87) is the single list that drives
*both* the cross-tool comparison matrices *and* the BigBed/trackhub tracks. SPRINT
must leave the former but stay in the latter (and keep running).

**Approach.** Introduce a second, comparison-only tool list derived from
`_BED_TOOLS` with SPRINT removed. BigBed/trackhub keep using `_BED_TOOLS`; all
comparison rules switch to the new list.

### Edits

**`Snakefile`** — after the `_BED_TOOLS` definition (line 87) add:

```python
# Tools included in the cross-tool comparison/correlation/consensus matrices.
# SPRINT is intentionally excluded here (it remains a caller and keeps its
# BigBed/trackhub track via _BED_TOOLS) because its de-novo SNV-cluster calls
# are orthogonal to the candidate-based callers and distort the matrices.
_COMPARE_TOOLS = [t for t in _BED_TOOLS if t != "sprint"]
```

**`Snakefile` `rule all`** — change the `aligner_correlation` target (line 239) from
`tool=_BED_TOOLS` to `tool=_COMPARE_TOOLS`. (The `compare_all_tools`,
`compare_outputs`, and `consensus` targets are path-globs, not tool-expanded, so
they need no change here — see §3 for their path moves.)

**`rules/visualization.smk`**:
- `_all_tool_outputs` (lines 197–207): iterate `_COMPARE_TOOLS` instead of
  `_BED_TOOLS`, so SPRINT outputs are not pulled in as matrix inputs.
- `rule compare_all_tools` `params.tools` (line 228): change
  `_BED_TOOLS + ["jacusa2"]` → `_COMPARE_TOOLS + ["jacusa2"]`.
- `rule aligner_correlation` `output` expand (line 354) and `params.tools`
  (line 368): change `_BED_TOOLS` → `_COMPARE_TOOLS`.

`compare_outputs` and `consensus_characteristics` read tool columns *from the
matrices*, so dropping SPRINT from `compare_all_tools` removes it from those two
automatically — no further edits needed.

**Verify.** Dry-run shows `results/tool_comparison/correlation/aligner_correlation_sprint.tsv.gz`
is no longer a target; SPRINT BigBed (`results/bigbed/sprint/...`) and the SPRINT
caller outputs (`results/tools/{aligner}/sprint/...`) are still scheduled.

---

## 2. MARINE `min_coverage` output filter

**Context.** MARINE's `final_filtered_site_info.<EDIT_TYPE>.tsv.gz` is produced by
`rule filter_marine_by_edit_type` (`rules/tools.smk:722–739`), which keeps only rows
whose `strand_conversion` column equals the configured edit (e.g. `A>G`). MARINE's
output has a `coverage` column (confirmed in `scripts/compare_all_tools.py:360–388`,
`parse_marine`) but no coverage gate is currently applied, unlike the other callers
which receive `params.common.min_coverage` via their own CLI flags. This makes
MARINE more permissive than its peers.

**Approach.** Extend the existing filter rule to also drop rows with
`coverage < min_coverage`, controlled by a new config key. Default **5**.

> Note: this is a MARINE-specific *post-hoc output* filter and is deliberately
> separate from `params.common.min_coverage` (currently 10), which is applied at
> *call time* via each tool's own flag. They can differ; default 5 is per the
> request. This is called out so a future reader doesn't "reconcile" them.

### Edits

**`examples/Morales_et_al/config.yaml`** and
**`examples/Morales_et_al_small/config_small.yaml`** — under `params.marine`:

```yaml
  marine:
    min_read_quality: 20
    min_coverage: 5        # post-hoc filter on MARINE's `coverage` column
                           # (rows with coverage < this are dropped from
                           # final_filtered_site_info.<EDIT_TYPE>.tsv.gz)
```

**`rules/tools.smk` `rule filter_marine_by_edit_type`** — add a `min_cov` param and
extend the awk to filter on the `coverage` column as well as `strand_conversion`:

```python
    params:
        conversion=_MARINE_CONVERSION,
        min_cov=config["params"]["marine"].get("min_coverage", 5)
```

```awk
    zcat {input} | awk -v conv='{params.conversion}' -v mincov='{params.min_cov}' 'BEGIN{{FS=OFS="\t"}}
        NR==1 {{ for(i=1;i<=NF;i++){{ if($i=="strand_conversion") cc=i; if($i=="coverage") cov=i }} print; next }}
        cc>0 && $cc==conv && cov>0 && ($cov+0)>=mincov' | gzip > {output}
```

**Filename is unchanged** (`final_filtered_site_info.<EDIT_TYPE>.tsv.gz`) so the
downstream glob in `compare_all_tools.py` (`final_filtered_site_info.*.tsv.gz`,
line 452) keeps matching. Because `min_coverage` is a rule `param`, Snakemake's
default `params` rerun-trigger regenerates this file when the value changes
(MARINE itself does not rerun).

**Verify.** With `min_coverage: 5`, after the rule runs:
`zcat results/tools/star/marine/<cond>_<samp>/final_filtered_site_info.AG.tsv.gz`
has no data rows with `coverage < 5`; raising the value to e.g. 50 and re-running
only this rule produces a strictly smaller file.

---

## 3. Consolidate folders under `results/tool_comparison/`

**Target layout** (subfolders preserved):

```
results/tool_comparison/
  compare_all_tools/   edit_coverage_matrix.tsv.gz, edit_fraction_matrix.tsv.gz, tool_score_matrix.tsv.gz
  correlation/         aligner_correlation_<tool>.tsv.gz (+ .png)
    intersect/         edits_intersect_, tool_jaccard_ (+.png), tool_overlap_counts_
    by_output_type/    per-site/per-gene-fraction-, qual-or-score-, read-count-correlation (+.png, _noverlap)
  consensus/           site_/gene_characteristics_, anticorrelation_*, consensus_report_<aligner>.md
```

`results/logs/` and `results/bigbed/`, `results/bigwig/`, `results/trackhub/` are
**unchanged**.

The Python scripts take `--matrix-dir` and `--outdir` as arguments (they do not
hard-code these paths), so **only the Snakefile and `visualization.smk` change**;
script *docstrings* mention the old paths and may be updated cosmetically.

### Edits — `Snakefile` `rule all`

Replace the prefixes on these targets (lines 221–239):

| Old | New |
|---|---|
| `results/compare_all_tools/edit_coverage_matrix.tsv.gz` | `results/tool_comparison/compare_all_tools/edit_coverage_matrix.tsv.gz` |
| `results/compare_all_tools/edit_fraction_matrix.tsv.gz` | `results/tool_comparison/compare_all_tools/edit_fraction_matrix.tsv.gz` |
| `results/compare_all_tools/tool_score_matrix.tsv.gz` | `results/tool_comparison/compare_all_tools/tool_score_matrix.tsv.gz` |
| `results/correlation/intersect/...` | `results/tool_comparison/correlation/intersect/...` |
| `results/correlation/by_output_type/...` | `results/tool_comparison/correlation/by_output_type/...` |
| `results/consensus/...` | `results/tool_comparison/consensus/...` |
| `results/correlation/aligner_correlation_{tool}.tsv.gz` | `results/tool_comparison/correlation/aligner_correlation_{tool}.tsv.gz` |

### Edits — `rules/visualization.smk`

For each of the four comparison rules, update `input`, `output`, `params.outdir`,
and the `--matrix-dir`/`--outdir` shell args:

- **`compare_all_tools`** (lines 215–227): `output` matrices and `params.outdir`
  → `results/tool_comparison/compare_all_tools`.
- **`compare_outputs`** (lines 261–280, 290): `input` matrices →
  `results/tool_comparison/compare_all_tools/...`; `output` →
  `results/tool_comparison/correlation/...`; `params.outdir` →
  `results/tool_comparison/correlation`; `--matrix-dir results/compare_all_tools`
  → `--matrix-dir results/tool_comparison/compare_all_tools`.
- **`consensus_characteristics`** (lines 310–327, 336): same matrix-dir change;
  `output` and `params.outdir` → `results/tool_comparison/consensus`.
- **`aligner_correlation`** (lines 351–366, 374): `input` and `--matrix-dir` →
  `results/tool_comparison/compare_all_tools`; `output` and `params.outdir` →
  `results/tool_comparison/correlation`.

### Edits — docs referencing old paths

Update path references in: `docs/consensus_permissivity_analysis.md`,
`docs/tools_reference.md`, `docs/edit_fraction_differences_across_tools.md`,
`docs/specs/marine_integration.md`, `docs/specs/edit_calling_parameters.md`,
`docs/specs/intersect_correlation.md`.

**Verify.** `snakemake -n` lists all comparison outputs under
`results/tool_comparison/...` and no targets remain at the old top-level paths;
`grep -rn "results/compare_all_tools\|results/consensus/\|results/correlation/"
pipelines/Morales_et_al` returns nothing.

---

## 4. Documentation

### 4a. New file: `docs/tool_comparison_outputs.md`

A reference that explains **how to interpret every figure (`.png`) and table
(`.tsv.gz`/`.csv`/`.md`)** the comparison stage emits. One subsection per output,
each stating: what it contains, column/axis meaning, and how to read it.

**Matrices — `tool_comparison/compare_all_tools/`** (rows = `chrom:pos`, cols =
`tool.aligner.condition_sample`):
- `edit_coverage_matrix.tsv.gz` — read depth at each called site. 0 = not called by
  that tool/sample.
- `edit_fraction_matrix.tsv.gz` — editing fraction 0–1. Heterogeneously populated;
  only tools that natively report a fraction fill it (see caveat below).
- `tool_score_matrix.tsv.gz` — tool-internal score (bcftools QUAL, jacusa2 test
  statistic, redinet/red_ml class probability). Not comparable across tools.
- **Caveat to restate:** a site is "called" if nonzero in *any* of the three
  matrices for that tool's columns; never average a column across tools.

**Intersection — `tool_comparison/correlation/intersect/`**:
- `edits_intersect_<aligner>.tsv.gz` — per-site co-call table: which tools called
  each site and how many.
- `tool_jaccard_<aligner>.tsv.gz` + `.png` — pairwise Jaccard overlap of called
  site sets (0–1). Heatmap: bright = high overlap.
- `tool_overlap_counts_<aligner>.tsv.gz` — raw shared-site counts behind the Jaccard.

**By output type — `tool_comparison/correlation/by_output_type/`** (each compares
only the tools that produce that quantity, over co-called sites):
- `per-site-fraction-correlation_<aligner>.tsv.gz` + `.png` — Spearman of editing
  fraction across tools, per site.
- `per-gene-fraction-correlation_<aligner>.tsv.gz` + `.png` — same, aggregated per
  gene (requires GTF; stub + note if absent).
- `qual-or-score-correlation_<aligner>.tsv.gz` + `.png` — Spearman of score/QUAL.
- `read-count-correlation_<aligner>.tsv.gz` + `.png` — Spearman of read depth.
- `<stem>_noverlap_<aligner>.tsv.gz` — n co-called sites per tool pair (the support
  behind each correlation cell; small n = unreliable correlation).

**Aligner correlation — `tool_comparison/correlation/`**:
- `aligner_correlation_<tool>.tsv.gz` + `.png` — per-tool Spearman of editing
  fraction *across aligners* (STAR/BWA/HISAT2). High = aligner-robust calls.

**Consensus — `tool_comparison/consensus/`**:
- `site_characteristics_<aligner>.tsv.gz` + `.png` — coverage / fraction / score
  stratified by agreement level (outersection =1 tool vs intersection ≥2, ≥3, …).
- `gene_characteristics_<aligner>.tsv.gz` — same, gene-level.
- `anticorrelation_gene_fraction_<aligner>.tsv.gz` — tool pairs that share genes
  but call disjoint sites within them (gene-level anticorrelation diagnostic).
- `anticorrelation_detail_<aligner>.tsv.gz` + `anticorrelation_<aligner>.png` —
  detail + plot for the worst-anticorrelated pair.
- `consensus_report_<aligner>.md` — human-readable summary auto-generated per aligner.

Each entry notes which `module load` produced it (`python3essential`) and that
PNGs are written only when matplotlib is available.

### 4b. Update `docs/consensus_permissivity_analysis.md` to include MARINE

The doc currently omits MARINE from the per-tool tables and the parse conventions.
Add:
- **Parse convention:** MARINE reports `count` and `coverage` (no native edit
  fraction); fraction = `count/coverage`. After this refactor the table is also
  gated at `coverage ≥ params.marine.min_coverage` (default 5) — note this when
  comparing call volume to other tools.
- **Section 1 (consensus):** include MARINE in the called-site counting and the
  consensus-vs-private breakdown.
- **Section 2 (dropout):** describe MARINE as an independent de-novo caller (runs
  per-chromosome on the BAM, then strand-conversion + coverage filtered), not a
  candidate-based classifier.
- **Section 3 (permissivity):** add MARINE's row to the "sites called" table and
  re-evaluate Claim 2 (most stringent de-novo caller) now that MARINE is in the
  de-novo group alongside jacusa2/jacusa2_call1/reditools/sprint.
- Note that **SPRINT remains in this analysis doc** (it is a caller); only the
  automated `tool_comparison/` matrices exclude it (§1).

> The figures in `docs/figures/consensus_analysis/` were produced by an ad-hoc
> `consensus_analysis.py`; regenerating them with MARINE included is a follow-up
> if up-to-date numbers are required. The text/tables should be updated regardless.

---

## Out of scope / open items

- Regenerating the static PNGs in `docs/figures/consensus_analysis/` with MARINE
  data (numbers in the prose can be updated from a fresh run when available).
- No change to `params.common.min_coverage` (stays 10, call-time).
- Script docstring path strings are cosmetic; update opportunistically.

## Verification checklist

1. `conda run -p .conda/editing-wgs-snakemake snakemake -n` (or the Morales dry-run)
   succeeds and shows all comparison targets under `results/tool_comparison/`.
2. No SPRINT column in the regenerated matrices; SPRINT BigBed + caller outputs
   still scheduled.
3. MARINE filtered TSV honors `min_coverage`; changing the config value re-runs
   only `filter_marine_by_edit_type`.
4. `grep` finds no remaining references to the three old top-level result folders
   in the pipeline.
5. `docs/tool_comparison_outputs.md` covers every emitted figure/table;
   `consensus_permissivity_analysis.md` includes MARINE.
