# Why Edit Fractions Differ Across Editing Tools

**Scope:** MARINE, REDItools3, SPRINT, and JACUSA2 *call-1* as wired in
`pipelines/Morales_et_al/Snakefile` (rules in `rules/tools.smk`).
**Evidence:** `examples/Morales_et_al_small/` (`star` aligner, 6 clones), drawn from
`results/tool_comparison/compare_all_tools/{edit_fraction,edit_coverage,tool_score}_matrix.tsv.gz`
and the raw per-tool outputs under `results/tools/star/`.

---

## TL;DR

The four tools disagree on edit fraction because they disagree on **three independent
things**, in this order of impact:

1. **What counts as the denominator (coverage).** Each tool applies its own read/base
   filters and overlap handling, so the *same locus* yields a *different depth*. Same
   numerator ÷ different denominator = different fraction.
2. **Whether a site is reported at all (the detection floor).** A coverage floor and an
   edit-fraction floor decide which sites even appear. MARINE *natively* has neither, but
   the pipeline now applies a **post-hoc coverage floor** (`marine.min_coverage`, default
   **5**) to MARINE's output, so by default MARINE is coverage-floored on par with
   REDItools3 (`-l 5`) and JACUSA2 *call-1* (`-c 5`); none of the three has a fraction
   floor (REDItools3's two-decimal rounding acts as a soft one). SPRINT ignores pileup
   depth entirely.
3. **What the reported number even means.** REDItools3 and MARINE report a true
   `edited/coverage` fraction; JACUSA2 reports a likelihood-ratio **score** and a
   fraction; SPRINT reports **supporting reads** and *no fraction at all* (its fraction
   is recorded as 0 in the comparison matrices).

The single clearest illustration is one canonical site (worked **Example 4** below):
**23 edited reads** at `chr12:6535556` becomes fraction **0.742** for REDItools3/JACUSA2
(denominator 31) but **0.657** for MARINE (denominator 35) — identical evidence, different
coverage accounting.

---

## How each tool is invoked here

All four read the same per-sample, deduplicated BAM (`*.rmdup.bam`; JACUSA2 and MARINE
use the MD-tagged `*.rmdup_MD.bam`). Shared config knobs
(`examples/Morales_et_al_small/config_small.yaml`):

| Knob | Value (small example) | Applies to |
|---|---|---|
| `common.base_quality` | 30 | all four (base-quality floor) |
| `common.min_coverage` | 5 | REDItools3 (`-l`), JACUSA2 (`-c`) at **call time**; not SPRINT |
| `marine.min_coverage` | 5 | MARINE **post-hoc** (`filter_marine_by_edit_type` drops rows with `coverage < 5`) |
| `common.strandedness` | `reverse_stranded` | all four (mapped to each tool's flag) |
| `common.edit_type` | `AG` | MARINE post-filter; comparison filter |
| `reditools3.map_quality` | 20 | REDItools3 (`-q`) |
| `marine.min_read_quality` | 20 | MARINE (`--min_read_quality`, a MAPQ floor) |

The coverage floor reaches each tool by a **different route**: REDItools3 and JACUSA2 apply
`common.min_coverage=5` *at call time* (sites below it are never pileup-tested), while MARINE
is filtered *after the fact* by a separate `marine.min_coverage` knob (default 5; it natively
reports every site). SPRINT has no coverage floor at all. The two MARINE knobs differ on
purpose: `common.min_coverage` is the call-time gate for the pileup tools, and
`marine.min_coverage` lets you tune MARINE's post-hoc gate independently (see Example 1).

---

## Tool 1 — MARINE

### Pseudocode
```
for each read in BAM (MAPQ >= min_read_quality, paired_end if applicable):
    for each aligned base (base_quality >= min_base_quality):
        if base != reference_base:
            record conversion (ref>alt) at this position, on this strand
for each position with >= 1 recorded conversion:
    count    = reads supporting the conversion
    coverage = reads spanning the position (after the same quality filters)
    emit (position, ref, alt, strand, count, coverage, conversion=ref>alt)
# Downstream (filter_marine_by_edit_type rule):
keep only rows where strand_conversion == "A>G" AND coverage >= marine.min_coverage (=5)
# Fraction is NOT emitted by MARINE; the comparison computes count / coverage.
```

### Plain English
MARINE walks every read and tallies **every** mismatch type genome-wide, then reports any
position where at least **one** read shows a mismatch — natively it has **no coverage floor
and no edit-fraction floor**, so a single edited read in a depth-1 pileup is a valid site.
The pipeline then post-filters MARINE's output to the `A>G` rows **and** to
`coverage >= marine.min_coverage` (default 5). That post-hoc floor is what makes MARINE
comparable to REDItools3/JACUSA2: by default it no longer keeps the depth-1–4 hyper-edited
clusters it natively finds (lower the knob to recover them). It still has **no fraction
floor**, so it reports 1-in-thousands sites at deep loci. MARINE counts coverage with its
own read filters, which generally yields a *slightly larger* denominator than
REDItools3/JACUSA2 — so for shared sites its fraction tends to be a touch lower.

---

## Tool 2 — REDItools3

### Pseudocode
```
for each position with coverage >= min_coverage (-l 5):
    pileup = bases with base_quality >= 30 from reads with MAPQ >= 20
    A,C,G,T = strand-aware base counts
    coverage = A+C+G+T
    if any non-reference base present:
        AllSubs   = observed substitution(s)
        Frequency = (non-reference count) / coverage      # rounded to 2 decimals
        emit (position, strand, coverage, [A,C,G,T], AllSubs, Frequency)
# Comparison scores a site only when its Frequency column is > 0.
```

### Plain English
REDItools3 is the conservative "middle of the road" caller. It only looks at positions with
**coverage ≥ 5**, applies MAPQ and base-quality filters, and reports a clean
`edited/coverage` frequency. Its reported frequency is rounded to two decimals, so a
genuine 1-in-700 edit (0.0014) prints as `0.00` and is treated as *not edited* by the
comparison. The net effect: REDItools3 reports the **fewest spurious low-fraction sites**
and has the **highest median fraction** of the four (it keeps only sites where the edit is
both real-depth and frequent enough to round above zero). In this dataset **every** site
REDItools3 scores is also caught by JACUSA2 and/or MARINE — it has **no private sites**.

---

## Tool 3 — SPRINT

### Pseudocode
```
align reads; identify mismatch loci that cluster spatially (hyper-editing signal)
for each candidate cluster:
    collapse PCR duplicates; require >= 1 supporting (independent) read
    classify SNV vs editing using cluster geometry + reference repeats (-rp rmsk)
emit SPRINT_identified_regular.res:
    Chrom  Start  End  Type(e.g. AG/TC)  Supporting_reads  Strand  AD:DP
# The .res format carries NO frequency column, so the comparison records:
#   coverage = Supporting_reads, fraction = 0, score = Supporting_reads
```

### Plain English
SPRINT does not build a per-position pileup the way the others do. It finds **clusters** of
mismatches that look like ADAR hyper-editing, collapses duplicates, and reports the number
of **supporting reads** behind each cluster. It has **no `min_coverage`** and reports no
edit fraction — so in the comparison matrices SPRINT's "coverage" is really its supporting-
read count (median **1**) and its fraction is always **0**. SPRINT is therefore *orthogonal*
to the pileup-based tools: it works from an independent candidate list, which is why it can
own sites no one else reports, but also why its numbers are not directly comparable on an
edit-fraction axis.

---

## Tool 4 — JACUSA2 *call-1*

### Pseudocode
```
for each position with coverage >= min_coverage (-c 5):
    bases11 = strand-aware [A,C,G,T] counts (base_quality >= 30)
    fit a Dirichlet-multinomial model to the base composition
    score = log-likelihood ratio (observed composition vs. a no-variant null)
    if score indicates significant deviation from the reference base:
        coverage = sum(bases11)
        fraction = alt_count / coverage
        emit (position, strand, bases11, score, fraction)
# A statistically significant deviation can occur at ANY fraction given enough depth.
```

### Plain English
JACUSA2 *call-1* is a **statistical** caller: it asks "is this base composition
significantly different from a clean reference position?" rather than "is the edit fraction
above a threshold?". With deep coverage, even a **1-in-700** minority allele is statistically
significant, so JACUSA2 flags it. This makes it the **most permissive at low fraction**
(median fraction **0.001**) and gives it the **most called sites** of the four. It enforces
`min_coverage=5` but has **no fraction floor**, so it sweeps up the deep, ultra-low-fraction
sites that REDItools3 rounds away.

---

## Three (+1) worked examples from `Morales_et_al_small` (star aligner)

### Example 1 — low-coverage hyper-edit, now filtered for all: `chr12:6344580` (A>G, +)
A depth-4 pileup. REDItools3 and JACUSA2 never see it (below their call-time `min_coverage=5`).
MARINE *natively* finds it, but the post-hoc `marine.min_coverage=5` filter now drops it too —
so under the default config **no tool reports it**.

| Tool | Native call | After default filters | count / coverage | Fraction | Why |
|---|---|---|---|---|---|
| MARINE (ADAR1KO_clone1) | ✅ | ❌ dropped | 3 / 4 | 0.75 | coverage 4 < `marine.min_coverage=5` |
| MARINE (WT_clone3) | ✅ | ❌ dropped | 4 / 4 | 1.00 | coverage 4 < `marine.min_coverage=5` |
| REDItools3 | ❌ | ❌ | — | — | coverage 4 < `min_coverage=5` |
| JACUSA2 call-1 | ❌ | ❌ | — | — | coverage 4 < `min_coverage=5` |
| SPRINT | ❌ | ❌ | — | — | not in its cluster list |

**Lesson:** this is exactly the site class the new `marine.min_coverage` filter targets.
Previously MARINE alone recovered these low-depth (often high-fraction) hyper-edits, which
made its call set and fraction distribution incomparable to the pileup tools. With the
default `marine.min_coverage=5` the depth-1–4 tail is removed (it no longer appears in the
`tool_comparison` matrices), aligning MARINE's coverage floor with REDItools3/JACUSA2. To
deliberately recover this site class, lower `marine.min_coverage` to ≤ 4.

### Example 2 — JACUSA2-only, high coverage / ultra-low fraction: `chr21:25982458` (T>C on –, i.e. A>G)
Same pileup seen by REDItools3, but the two tools *disagree on whether it is an edit*.

| Tool | Pileup `[A,C,G,T]` | coverage | edited reads | Reported value | Called? |
|---|---|---|---|---|---|
| JACUSA2 call-1 (ADAR1KO_clone3) | `0,1,0,710` | 711 | 1 | score **0.086**, frac 0.0014 | ✅ |
| REDItools3 (ADAR1KO_clone3) | `[0,1,0,710]` | 711 | 1 | Frequency **0.00** | ❌ (rounds to 0) |
| MARINE | — | — | — | — | ❌ |
| SPRINT | — | — | — | — | ❌ |

**Lesson:** identical evidence (`0,1,0,710`), opposite verdicts. JACUSA2's statistical test
declares 1/711 significant; REDItools3's two-decimal frequency rounds it to `0.00` and the
comparison drops it. This is *philosophy*, not depth.

### Example 3 — SPRINT-only, support-read logic: `chr21:26076073` (TC, –)
SPRINT's `.res` row is `chr21  26076072  26076073  TC  1  -  1:2`.

> **Note (2026 refactor):** SPRINT is now **excluded from the `tool_comparison` matrices**
> and the correlation/consensus analyses, precisely because its support-read "coverage" and
> absent fraction are not comparable on a pileup axis (this section is the rationale). SPRINT
> still runs and its calls remain in `results/tools/{aligner}/sprint/` and the BigBed/trackhub
> tracks — so this site is still produced, just no longer mixed into the cross-tool tables.

| Tool | Reported? | "coverage" | Fraction | Why |
|---|---|---|---|---|
| SPRINT (WT_clone1) | ✅ | 1 (= supporting reads) | 0 (no frac column) | own cluster list, no depth floor |
| REDItools3 | ❌ | — | — | depth 2 < `min_coverage=5` |
| JACUSA2 call-1 | ❌ | — | — | depth 2 < `min_coverage=5` |
| MARINE | ❌ | — | — | not retained as A>G here |

**Lesson:** SPRINT's "coverage" is supporting reads, and it carries no fraction — so it is
not comparable on the fraction axis at all. Its uniqueness comes from an independent
detection algorithm, not from a looser threshold.

### Example 4 — consensus site, the same edit measured four ways: `chr12:6535556` (A>G, +; ADAR1KO_clone3)
All depth-based tools agree there is an edit; **they disagree on the number**.

| Tool | edited reads | coverage (denominator) | **Edit fraction** | Native score |
|---|---|---|---|---|
| REDItools3 | 23 (`[8,0,23,0]`) | 31 | **0.742** | Frequency 0.74 |
| JACUSA2 call-1 | 23 (`8,0,23,0`) | 31 | **0.742** | LLR score 6.66 |
| MARINE | 23 | **35** | **0.657** | 0.657 |
| SPRINT | — | — | not called | — |

**Lesson:** the numerator is identical (23 edited reads), but MARINE counts a **larger
coverage denominator** (35 vs 31) under its own read filters, so its fraction is lower
(0.657 vs 0.742). This is the cleanest demonstration that *coverage accounting* — not the
edit itself — drives most of the fraction spread between MARINE and the pileup tools.

---

## Summary table — edit characteristics (star aligner, all 6 clones)

Computed over every site each tool scores `> 0` in
`results/tool_comparison/compare_all_tools/*_matrix.tsv.gz`. **MARINE reflects the post-hoc
`marine.min_coverage=5` filter; SPRINT is no longer in these matrices** (its row below is
from its raw `.res` output, retained here only to characterize the tool).

| Tool | # sites | Median coverage | Median fraction | Mean fraction | % sites cov < 5 | Coverage floor | Fraction floor | Reported quantity |
|---|---|---|---|---|---|---|---|---|
| **MARINE** | 597 | 6621 | 0.0003 | 0.023 | **0.0%** | `marine.min_coverage` (post-hoc, 5) | none | `count / coverage` |
| **REDItools3** | 200 | 27 | **0.0500** | 0.268 | 0.0% | `-l 5` | ~0.005 (rounding) | `Frequency` |
| **SPRINT** *(not in matrices)* | 14 | 1 | 0.0000 | 0.000 | 100% | none | none | supporting reads (no fraction) |
| **JACUSA2 call-1** | 1163 | 3484 | 0.0010 | 0.039 | 0.0% | `-c 5` | none | LLR score + `alt/coverage` |

> **Effect of the MARINE filter.** Before `marine.min_coverage=5`, MARINE reported ~849
> sites with **23.6%** below depth-5 and a **mean fraction of 0.209** — the high mean came
> almost entirely from those low-depth hyper-edits (e.g. 3/4, 4/4). Removing the sub-5 tail
> drops the count to ~597, pushes `% cov < 5` to **0%**, and collapses the mean fraction to
> **0.023**, putting MARINE on the same coverage footing as REDItools3/JACUSA2.

Reading the table:
- **JACUSA2 call-1** = most sites, lowest median fraction → permissive *statistical* caller.
- **MARINE** = deep, ultra-low-fraction sites; with the default coverage filter its
  low-depth/high-fraction hyper-edit tail is removed, so it is now coverage-floored like the
  pileup tools and only its absent fraction floor distinguishes it.
- **REDItools3** = fewest depth-based sites, **highest median fraction**, nothing below
  depth 5 → conservative middle ground; every site is co-called.
- **SPRINT** = tiny, support-read-only, fraction not defined → orthogonal cluster caller,
  now scored on its own axis outside the comparison matrices.

---

## Practical guidance

- **Do not compare edit fractions across tools without normalizing the denominator.**
  MARINE vs REDItools3/JACUSA2 fraction gaps are largely a coverage-definition artifact
  (Example 4).
- **SPRINT belongs on a separate axis** (supporting reads / presence), not the fraction
  axis — it has no fraction and a non-pileup coverage. It is therefore **excluded from the
  `tool_comparison` matrices** by design; read it from `results/tools/*/sprint/` and the
  BigBed tracks instead.
- **Low-fraction disagreement (REDItools3 vs JACUSA2)** is expected and informative:
  REDItools3 favors precision (rounds away 1-in-hundreds), JACUSA2 favors statistical
  sensitivity. Use the consensus (`min_tools`) layer to require corroboration.
- **`marine.min_coverage` is the high-leverage knob for MARINE** (default 5): raising it
  culls more of MARINE's low-depth tail and tightens the cross-tool gap; lowering it (≤ 4)
  re-admits the low-depth hyper-edits MARINE uniquely finds. It is intentionally separate
  from `common.min_coverage` (the call-time floor for REDItools3/JACUSA2), so MARINE can be
  tuned without touching the pileup tools.
