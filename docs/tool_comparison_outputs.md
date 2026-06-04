# Tool-comparison outputs: how to read every figure and table

The cross-tool comparison stage of `pipelines/Morales_et_al/Snakefile`
(`rules/visualization.smk`) writes everything under **`results/tool_comparison/`**:

```
results/tool_comparison/
  compare_all_tools/   the three site × sample matrices everything else is built from
  correlation/         per-tool across-aligner correlation, plus:
    intersect/         which tools co-call which sites (Jaccard / overlap)
    by_output_type/    cross-tool Spearman, one matrix per output quantity
  consensus/           characteristics stratified by how many tools agree
```

All `.tsv.gz` tables are tab-separated and gzip-compressed (`zcat file | column -t`
to view). All `.png` figures are written by the analysis scripts **only when
matplotlib is importable** (`module load python3essential`); the `.tsv.gz` behind
each figure is always written, so the figure is a convenience view of the table.

**Tools in these outputs.** The comparison set is `_COMPARE_TOOLS` =
`reditools, reditools3, red_ml, bcftools, redinet, jacusa2_call1, marine`
(plus the call-2 `jacusa2` contrast in the matrices). **SPRINT is deliberately
excluded** from every output below — its de-novo SNV-cluster calls are orthogonal
to the candidate-based callers and distort the matrices. SPRINT still runs and
still appears in the BigBed/trackhub tracks (`results/bigbed/sprint/`,
`results/trackhub/`).

---

## 1. `compare_all_tools/` — the source matrices

Three matrices, one row per called site (`chrom:pos`), one column per
`tool.aligner.condition_sample`. A `0` means that tool/sample did not call (or
does not report a value for) that site.

| File | Holds | How to read it |
|---|---|---|
| `edit_coverage_matrix.tsv.gz` | read depth at each called site | Per-tool depth. Tools that report no true depth (e.g. ML classifiers) are 0 here. |
| `edit_fraction_matrix.tsv.gz`  | editing fraction (0–1) | Only tools that natively report a fraction fill it. |
| `tool_score_matrix.tsv.gz`     | tool-internal confidence score | Heterogeneous axis (see below) — not comparable across tools by value. |

**Critical caveat (do not average across tools).** Each tool fills only the
field(s) it natively reports, so the matrices are *heterogeneously populated*.
A site is considered "called" by a tool if it is nonzero in **any** of the three
matrices for that tool's columns. The score axis differs per tool:

- **bcftools** → QUAL
- **jacusa2 / jacusa2_call1** → test statistic
- **redinet / red_ml** → class probability (0–1)
- **reditools / reditools3** → editing fraction proxy
- **marine** → `count/coverage` fraction (MARINE reports `count` and `coverage`,
  no native fraction; its rows are also gated at `coverage ≥ params.marine.min_coverage`,
  default 5).

`reditools3` is an exact duplicate of `reditools`; treat the pair as one tool when
counting agreement.

---

## 2. `correlation/intersect/` — who co-calls what

Per aligner (`star`, `bwa`, `hisat2`):

| File | Holds | How to read it |
|---|---|---|
| `edits_intersect_<aligner>.tsv.gz` | per-site co-call table: for each site, which tools called it and the total count | Find which tools agree on a given site; filter to `n ≥ 2` for consensus sites. |
| `tool_jaccard_<aligner>.tsv.gz` + `.png` | pairwise Jaccard overlap (0–1) of each tool pair's called-site sets | Heatmap: bright/high = the two tools call largely the same sites; dark/low = disjoint. Symmetric matrix, diagonal = 1. |
| `tool_overlap_counts_<aligner>.tsv.gz` | raw count of sites shared by each tool pair | The numerator behind the Jaccard; use to see absolute overlap, not just the ratio. |

---

## 3. `correlation/by_output_type/` — cross-tool agreement on values

Per aligner. Each matrix is a **Spearman correlation** computed **only over sites
co-called by both tools**, and **only among tools that actually produce that
quantity** (a tool that does not report the quantity is omitted from that matrix).

| File | Compares | How to read it |
|---|---|---|
| `per-site-fraction-correlation_<aligner>.tsv.gz` + `.png` | editing fraction, per site | High (→1) = tools rank edit levels the same way across sites. |
| `per-gene-fraction-correlation_<aligner>.tsv.gz` + `.png` | editing fraction aggregated per gene | Needs the GTF; a stub + note is written if no GTF is configured. |
| `qual-or-score-correlation_<aligner>.tsv.gz` + `.png` | each tool's score/QUAL | Only meaningful within comparable score types; low values often just reflect different score definitions. |
| `read-count-correlation_<aligner>.tsv.gz` + `.png` | read depth | High = tools agree on relative coverage at shared sites. |
| `<stem>_noverlap_<aligner>.tsv.gz` | n co-called sites behind each pair's correlation | **Read this alongside the correlation.** A correlation computed from few shared sites (small n) is unreliable — check n before trusting a cell. |

---

## 4. `correlation/` — across-aligner reproducibility

One matrix per comparison tool:

| File | Holds | How to read it |
|---|---|---|
| `aligner_correlation_<tool>.tsv.gz` + `.png` | pairwise Spearman of that tool's editing fraction **across aligners** (STAR/BWA/HISAT2) | High = the tool's calls are aligner-robust; low = its calls depend heavily on the aligner. One file per tool in `_COMPARE_TOOLS` (no `_sprint`). |

---

## 5. `consensus/` — characteristics by level of agreement

Per aligner. "Agreement level" stratifies sites/genes by how many tools called
them: **outersection** (= 1 tool, i.e. private) vs **intersection** (≥ 2, ≥ 3, …,
all). `reditools`/`reditools3` are collapsed to one tool for counting.

| File | Holds | How to read it |
|---|---|---|
| `site_characteristics_<aligner>.tsv.gz` + `.png` | coverage / fraction / score summarized at each agreement level (site-level) | Trend across levels: higher-agreement sites typically have higher depth and fraction. The PNG plots these distributions side by side. |
| `gene_characteristics_<aligner>.tsv.gz` | same, aggregated per gene | Gene-level view of the agreement trend (GTF required; stub + note otherwise). |
| `anticorrelation_gene_fraction_<aligner>.tsv.gz` | tool pairs that share **genes** but call **disjoint sites** within them | Identifies pairs (e.g. red_ml vs MARINE) that look uncorrelated only because they hit different positions of the same genes. |
| `anticorrelation_detail_<aligner>.tsv.gz` | per-gene detail for the single worst-anticorrelated pair | Drill-down behind the diagnostic. |
| `anticorrelation_<aligner>.png` | plot of the worst-anticorrelated pair | Visual of the disjoint-within-shared-gene pattern. |
| `consensus_report_<aligner>.md` | auto-generated human-readable summary | Start here per aligner: it narrates the site/gene counts and points at the anticorrelation files. |

---

## Reproduce

```bash
module load python3essential
# matrices
python3 pipelines/Morales_et_al/scripts/compare_all_tools.py --help
# intersect + by-output-type correlation
python3 pipelines/Morales_et_al/scripts/compare_outputs.py --help
# consensus characteristics
python3 pipelines/Morales_et_al/scripts/consensus_characteristics.py --help
# across-aligner correlation
python3 pipelines/Morales_et_al/scripts/aligner_correlation.py --help
```

Within the pipeline these are the `compare_all_tools`, `compare_outputs`,
`consensus_characteristics`, and `aligner_correlation` rules in
`rules/visualization.smk`.

## Related

- `docs/consensus_permissivity_analysis.md` — interpretation of consensus / tool
  dropout / permissivity, including MARINE.
- `docs/edit_fraction_differences_across_tools.md` — why per-tool edit fractions
  differ.
