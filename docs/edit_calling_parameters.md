# Edit-calling parameter harmonization (Morales_et_al)

To make cross-tool comparisons reflect the algorithms rather than mismatched
settings, the Morales_et_al pipeline drives **base-quality**, **min-coverage**, and
**edit-type** from a single `params.common` block in `config.yaml`, applied through
each tool's own CLI flag wherever the tool exposes one. Where a tool does not expose a
knob, it is left at the tool default and noted below (not faked with external
pre-filtering).

```yaml
params:
  common:
    base_quality: 30      # production config; small example uses 30 too
    min_coverage: 10      # production config; small example config uses 5
    edit_type: "AG"       # A->I; reverse-strand complement "TC" derived automatically
    min_tools: 2          # co-call threshold for compare_outputs
```

## Verified flag matrix

Flags were confirmed against each container's `--help` (Apptainer SIFs under
`singularity/`).

| Tool (entrypoint) | base-quality | min-coverage | dbSNP / simpleRepeat / Alu |
|---|---|---|---|
| reditools `reditools.py` | `-bq <base_quality>` | `-l <min_coverage>` (min-column-length) | none exposed → left as-is |
| reditools3 `reditools analyze` | `-bq <base_quality>` | `-l <min_coverage>` (min-read-depth) | none exposed → left as-is |
| bcftools `mpileup`/`call` | `-Q <base_quality>` (min-BQ) | post-call `view -e 'INFO/DP<min_coverage>'` | **dbSNP + simpleRepeat excluded** via `view -T ^<exclude.bed>`; Alu not excluded |
| RED-ML `red_ML.pl` | not exposed → tool default | not exposed → tool default | native `--dbsnp --simpleRepeat --alu`; `--alu` passed only if `alu_bed` is set and the file exists |
| REDInet `REDItoolDnaRna.py` | `-q 0,<base_quality>` | `-c 0,<min_coverage>` | none exposed → left as-is |
| JACUSA2 `call-2` | `-q <base_quality>` (min-BASQ) | `-c <min_coverage>` | `-b` is region *inclusion* only, no exclusion → left as-is |
| SPRINT `sprint_from_bam.py` | not exposed → tool default | not exposed → tool default | repeat-aware internally via `rmsk`; no dbSNP/Alu CLI → left as-is |

Notes:
- **Mapping quality** is intentionally *not* harmonized here (out of scope); it stays at
  each tool's existing per-tool setting (mostly 20).
- **reditools.py `-c`** is *not* a coverage flag (it creates the omopolymeric file);
  min-coverage is `-l` / `--min-column-length`.
- **Alu is a positive feature, not an exclusion filter** — it is enriched for genuine
  A->I editing, so it is only consumed by RED-ML's `--alu` (the way RED-ML intends) and is
  never subtracted from any tool's call set.

## dbSNP / simpleRepeat exclusion BED

The `prepare_editing_filters` rule (bedtools container,
`docker://biocontainers/bedtools:v2.28.0_cv2`) builds the exclusion BED used by bcftools:

1. dbSNP UCSC table (`references.dbsnp`, e.g. `snp151CodingDbSnp.txt.gz`) → BED via
   `awk '{print $2"\t"$3"\t"$4}'`.
2. concatenate with `references.simple_repeat` (already a merged BED).
3. `bedtools sort` + `bedtools merge` → `results/references/editing_exclude.bed`.

## Edit type

`compare_all_tools.py` takes `--edit-type` (default `AG`) and filters **every** tool's
parsed sites to that substitution and its reverse-strand complement (`AG`→`TC`,
`CT`→`GA`, …), so every tool's matrix contains the same edit class. Callers that emit all
substitutions (reditools, bcftools, jacusa2) are filtered at this comparison layer;
RED-ML and REDInet are A->I by design.

See `docs/specs/intersect_correlation.md` for the full design.
