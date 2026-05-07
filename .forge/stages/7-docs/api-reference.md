# Schema / API Reference: Morales_et_al Pipeline

This document covers the data schemas, config contracts, and script interfaces for the `pipelines/Morales_et_all/` data pipeline. There is no HTTP API; the public surface is: (1) `config.yaml` keys, (2) the samplesheet CSV schema, (3) the helper Python functions in `Snakefile`, and (4) the standalone scripts under `scripts/`.

---

## 1. Samplesheet CSV Schema

**File**: `pipelines/Morales_et_all/samplesheet.csv`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `conditions` | string | Yes | Experimental condition, e.g., `WT`, `ADAR1KO`. Used as wildcard `{condition}`. Must not contain `.`, `_`, or `/`. |
| `samples` | string | Yes | Sample/replicate identifier, e.g., `rep1`. Used as wildcard `{sample}`. Must not contain `.`, `_`, or `/`. |
| `fastq_1` | string (path) | Yes | Absolute path to R1 FASTQ.GZ. |
| `fastq_2` | string (path) | No | Absolute path to R2 FASTQ.GZ. Leave empty for single-end samples. |

**Notes**:
- Rows with the same `(conditions, samples)` pair are collapsed to a single entry; the last row wins.
- Wildcard constraints: `condition` and `sample` must match `[^/._]+`.

---

## 2. Config.yaml Schema

**File**: `pipelines/Morales_et_all/config.yaml`

### Top-level keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `threads` | int | Yes | Global CPU thread count for STAR and BWA-MEM rules. |
| `samplesheet` | string | Yes | Path to samplesheet CSV (relative to pipeline dir). |
| `aligners` | list[string] | No | Unused by rules; retained for forward compatibility. |
| `singularity_image_dir` | string | No | Default SIF search directory. Used by `container_for()` fallback. |
| `containers` | map[string, string] | Yes | Explicit SIF path per tool name. Keys: `fastx`, `star`, `picard`, `reditools`, `sprint`, `wgs`, `red_ml`, `jacusa2`, `morales_downstream`. |
| `references` | map | Yes | Reference file paths (see below). |
| `wgs_samples` | map[string, list[string]] | No | WGS sample name to FASTQ path list. Enables WGS rules and DB generation. |
| `downstream_scripts_dir` | string | Yes | Path to the `Benchmark-of-RNA-Editing-Detection-Tools/Downstream/` directory. |
| `params` | map | Yes | Tool-specific parameters (see below). |

### `references` subkeys

| Key | Type | Description |
|-----|------|-------------|
| `fasta` | string | GRCh38 reference FASTA path. |
| `star_index` | string | Pre-built STAR index directory path. |
| `gtf` | string | Gencode GTF annotation path. |
| `rmsk` | string | RepeatMasker `rmsk.txt` path (raw UCSC download). |
| `dbsnp` | string | dbSNP `.txt.gz` path. |
| `simple_repeat_src` | string | Raw UCSC `simpleRepeat.txt` path. |
| `simple_repeat` | string | Output path for generated merged BED. |
| `alu_bed` | string | Output path for generated Alu BED. |
| `rediportal_hg38` | string | REDIportal hg38 table `.txt.gz` path. |
| `db_path` | string | Output directory for JSON reference databases. |

### `params` subkeys

| Key | Subkey | Type | Default | Description |
|-----|--------|------|---------|-------------|
| `fastx_trimmer` | `quality` | int | `33` | Phred quality offset. |
| `fastx_trimmer` | `length` | int | `130` | Truncation length (bp). |
| `star` | `map_quality` | int | `20` | Minimum MAPQ post-STAR filtering. |
| `bcftools` | `max_depth` | int | `10000` | `--max-depth` for mpileup. |
| `bcftools` | `map_quality` | int | `20` | `-q` mapping quality filter. |
| `bcftools` | `base_quality` | int | `20` | `-Q` base quality filter. |
| `red_ml` | `p_value` | float | `0.5` | RED-ML p-value call threshold. |
| `jacusa2` | `pileup_filter` | string | `"D"` | JACUSA2 `-a` argument. |

---

## 3. Snakefile Helper Functions

**File**: `pipelines/Morales_et_all/Snakefile`

### `container_for(tool: str) -> str`

Returns the Singularity image path for a given tool name. Checks `config["containers"][tool]` first; falls back to `{SIF_DIR}/{tool}.sif`.

```python
container_for("star")  # → config["containers"]["star"] or f"{SIF_DIR}/star.sif"
```

### `is_paired(condition: str, sample: str) -> bool`

Returns `True` if the samplesheet entry for `(condition, sample)` has a non-empty `fastq_2` path.

### `samplesheet_fastq_path(wildcards) -> str`

Input function for `prepare_fastq`. Returns the source FASTQ.GZ path for the given `{condition}`, `{sample}`, `{read}` wildcards. Raises `ValueError` if `read == "R2"` and no R2 path is configured.

---

## 4. Standalone Scripts

### `scripts/build_downstream_dbs.py`

Builds the three JSON databases consumed by the downstream analysis scripts.

**CLI**:
```
python scripts/build_downstream_dbs.py \
  --hek-bed <path>     \
  --rediportal <path>  \
  --alu <path>         \
  --assembly hg38      \
  --outdir <dir>
```

**Arguments**:

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `--hek-bed` | path | Yes | 5-column BED of A>G/T>C SNPs from WGS alignment (`{wgs_sample}_hg38.bed`). |
| `--rediportal` | path | Yes | REDIportal hg38 `.txt.gz` table. |
| `--alu` | path | Yes | Merged Alu BED file. |
| `--assembly` | string | Yes | Assembly identifier (e.g., `hg38`). |
| `--outdir` | path | Yes | Output directory. Writes `HEK293T_hg38_clean.json`, `REDIportal.json`, `Alu_GRCh38.json`. |

---

### `scripts/sprint_to_deepred_vcf.py`

Converts SPRINT `.res` output to DeepRED VCF-format input.

**CLI**:
```
python scripts/sprint_to_deepred_vcf.py <input.res> <output.vcf>
```

**Functions**:
- `parse_edit_type(raw_type, input_path, line_number)` — Parses the edit type field and returns canonical `(REF, ALT)` tuple.
- `convert_sprint_res_to_deepred_vcf(input_path, output_path)` — Main conversion loop.

---

### `scripts/sprint_to_editpredict_positions.py`

Converts SPRINT `.res` output to EditPredict position TSV format.

**CLI**:
```
python scripts/sprint_to_editpredict_positions.py <input.res> <output.tsv>
```

**Functions**:
- `normalize_chromosome(raw_chromosome)` — Strips or adds `chr` prefix per EditPredict convention.
- `convert_sprint_positions(input_path, output_path)` — Main conversion loop.

---

## 5. Output Files

| Path | Format | Description |
|------|--------|-------------|
| `results/trimmed/{condition}_{sample}_{read}_trimmed.fastq.gz` | FASTQ.GZ | Quality-trimmed reads |
| `results/mapped/{condition}_{sample}.bam` | BAM | STAR-aligned sorted BAM |
| `results/mapped/{condition}_{sample}.rmdup.bam` | BAM | Duplicate-removed BAM |
| `results/tools/reditools/{condition}_{sample}.output` | TSV | REDItools2 output table |
| `results/tools/sprint/{condition}_{sample}_output` | Directory | SPRINT output directory |
| `results/tools/bcftools/{condition}_{sample}.bcf` | BCF | BCFtools variant calls |
| `results/tools/red_ml/{condition}_{sample}_output/` | Directory | RED-ML output directory |
| `results/tools/jacusa2/Jacusa.out` | TSV | JACUSA2 differential editing calls |
| `data/dbRNA-Editing/HEK293T_hg38_clean.json` | JSON | HEK293T SNP reference database |
| `data/dbRNA-Editing/REDIportal.json` | JSON | REDIportal reference database |
| `data/dbRNA-Editing/Alu_GRCh38.json` | JSON | Alu element reference database |
| `results/downstream/multiple_analysis.done` | Sentinel | Final downstream completion marker |
