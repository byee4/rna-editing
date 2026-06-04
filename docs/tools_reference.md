# RNA Editing Tools Reference

This document describes every tool run by the `pipelines/Morales_et_al` benchmark pipeline:
its purpose, the exact command line the Snakefile invokes, what each parameter means, and the
output table format with example rows from `examples/Morales_et_al_small`.

Commandlines were independently verified against the `--help` output of each tool inside its
Singularity/Apptainer container (see [Orthogonal verification](#orthogonal-verification)).

---

## Contents

1. [Shared filter parameters](#shared-filter-parameters)
2. [Preprocessing tools](#preprocessing-tools)
   - [fastx_trimmer](#fastx_trimmer)
   - [STAR](#star)
   - [BWA-MEM](#bwa-mem)
   - [HISAT2](#hisat2)
   - [Picard MarkDuplicates](#picard-markduplicates)
3. [RNA editing callers](#rna-editing-callers)
   - [REDItools (v1 / reditools.py)](#reditools-v1--reditoolspy)
   - [REDItools3 (reditools analyze)](#reditools3-reditools-analyze)
   - [SPRINT](#sprint)
   - [bcftools mpileup/call](#bcftools-mpileupcall)
   - [RED-ML](#red-ml)
   - [JACUSA2 call-2 (differential)](#jacusa2-call-2-differential)
   - [JACUSA2 call-1 (per-sample)](#jacusa2-call-1-per-sample)
   - [REDInet (REDItoolDnaRna → classifier)](#redinet-reditooldnarna--classifier)
   - [MARINE (marine.py)](#marine-marinepy)
4. [Orthogonal verification](#orthogonal-verification)

---

## Shared filter parameters

All callers receive these values from a single `params.common` block in `config.yaml`,
applied through each tool's own CLI flag wherever the tool exposes one.

| Parameter | Small-example value | Production value | Meaning |
|---|---|---|---|
| `base_quality` | 30 | 30 | Minimum per-base Phred quality |
| `min_coverage` | 5 | 10 | Minimum read depth at a site |
| `edit_type` | `AG` | `AG` | Only A→G (A→I) and its complement TC kept by `compare_all_tools` |
| `min_tools` | 2 | 2 | Co-call threshold for the summary comparison |

Where a tool does not expose a flag, it uses its internal default and this is noted per tool.
See `docs/edit_calling_parameters.md` for the full flag-to-tool matrix.

---

## Preprocessing tools

### fastx_trimmer

**Container:** `fastx.sif`  
**GitHub:** https://github.com/agordon/fastx_toolkit  
**Purpose:** Hard-clips reads to a fixed length to remove low-quality 3′ bases before alignment.

**Command:**
```
fastx_trimmer -Q{quality} -l {length} -z -i {input} -o {output}
```

| Flag | Value | Meaning |
|---|---|---|
| `-Q` | 33 | Phred quality encoding (Sanger/Illumina 1.8+) |
| `-l` | 130 | Trim read to this length (first 130 bases kept) |
| `-z` | — | Gzip-compress output |
| `-i` | input FASTQ | Input file |
| `-o` | output FASTQ.gz | Output file |

---

### STAR

**Container:** `star.sif`  
**Purpose:** Splice-aware alignment of RNA-seq reads to the genome.

**Command:**
```
STAR --runThreadN {threads} --genomeDir {star_index} \
     --readFilesIn {R1} [{R2}] --readFilesCommand zcat \
     --outSAMtype BAM SortedByCoordinate --outFileNamePrefix {prefix} \
     --outSAMattrRGline "ID:{id} SM:{id} PL:ILLUMINA LB:{id}"
samtools view -@ {threads} {samflag} -q 20 -b {aligned.bam} \
  | samtools sort -@ {threads} -T {tmp} -o {output.bam}
samtools index -@ {threads} {output.bam}
```

| Parameter | Value | Meaning |
|---|---|---|
| `--runThreadN` | config `threads` | Parallel threads |
| `--genomeDir` | `references.star_index` | Pre-built STAR genome index directory |
| `--readFilesCommand` | `zcat` | Decompress gzipped FASTQs on the fly |
| `--outSAMtype` | `BAM SortedByCoordinate` | Produce coordinate-sorted BAM |
| `samtools view -q` | 20 | Keep only alignments with MAPQ ≥ 20 |
| `samtools view -F 0x04` | — | Discard unmapped reads |
| `samtools view -f 0x2` | — | Keep only properly paired reads (paired-end only) |

> **Note:** STAR assigns MAPQ=255 to uniquely mapped reads. This value is rejected by SPRINT
> and is rewritten to 30 by the `sprint_mapq_bam` rule (see [SPRINT](#sprint)).

---

### BWA-MEM

**Container:** `wgs.sif`  
**Purpose:** Alignment of RNA-seq reads via BWA (used as a baseline in the aligner comparison).

**Command:**
```
bwa mem -t {threads} -R "@RG\tID:{id}\tSM:{id}\tPL:ILLUMINA\tLB:{id}" \
        {ref} {R1} [{R2}] \
  | samtools view -@ {threads} {samflag} -q 20 -b - \
  | samtools sort -@ {threads} -T {tmp} -o {output.bam}
samtools index -@ {threads} {output.bam}
```

| Flag | Value | Meaning |
|---|---|---|
| `-t` | config `threads` | Threads |
| `-R` | RG tag string | Read-group header line for downstream tools |
| `samtools view -q` | 20 | Minimum MAPQ filter |

---

### HISAT2

**Container:** `hisat2.sif`  
**Purpose:** Splice-aware alignment of RNA-seq reads (third aligner in the comparison).

**Command:**
```
hisat2 -p {threads} -x {hisat2_index} {-1 R1 -2 R2 | -U R1} \
       --rg-id "{id}" --rg "SM:{id}" --rg "PL:ILLUMINA" --rg "LB:{id}" \
  | samtools view -@ {threads} {samflag} -q 20 -b - \
  | samtools sort -@ {threads} -T {tmp} -o {output.bam}
samtools index -@ {threads} {output.bam}
```

| Flag | Value | Meaning |
|---|---|---|
| `-p` | config `threads` | Threads |
| `-x` | `references.hisat2_index` | HISAT2 index prefix |
| `samtools view -q` | 20 | Minimum MAPQ filter |

> HISAT2 may exit 141 (SIGPIPE) when the downstream pipe closes early; this is expected and
> handled in the pipeline.

---

### Picard MarkDuplicates

**Container:** `picard.sif`  
**Purpose:** Removes PCR/optical duplicates from the aligned BAM.

**Command:**
```
picard MarkDuplicates INPUT={input.bam} OUTPUT={rmdup.bam} \
       METRICS_FILE={metrics} REMOVE_DUPLICATES=true
```

| Parameter | Value | Meaning |
|---|---|---|
| `REMOVE_DUPLICATES` | `true` | Physically remove duplicates (not just flag them) |
| `METRICS_FILE` | `{sample}.duplication.info` | Per-sample duplication statistics |

JVM heap is set to 75% of the SLURM-allocated memory via `_JAVA_OPTIONS="-Xmx{mem}m"`.

---

## RNA editing callers

### REDItools (v1 / reditools.py)

**Container:** `reditools2.sif`  
**GitHub:** https://github.com/BioinfoUNIBA/REDItools  
**Mode:** Per-sample; RNA-only (no matched DNA).  
**Execution:** Parallelized by chromosome — the pipeline splits the BAM by chromosome via
`split_bam_by_chrom`, runs `reditools_by_chrom` on each, then merges with `join_reditools_output`.

**Command (per chromosome):**
```
reditools.py -S -C -s {strand} -bq {base_quality} -q 20 -l {min_coverage} \
    -f {chrom.bam} -r {ref} -g {chrom} -o {output}
```

| Flag | Value | Meaning |
|---|---|---|
| `-S` | — | Strict mode: only emit positions with at least one non-reference base |
| `-C` | — | Strand correction: discard positions with inconsistent strand signal |
| `-s` | `params.common.strandedness` → 0/1/2 | Strand: 0=unstranded, 1=second-strand, 2=first-strand |
| `-bq` | `params.common.base_quality` (30) | Minimum per-base quality score |
| `-q` | 20 | Minimum read (mapping) quality score |
| `-l` | `params.common.min_coverage` (5/10) | Minimum column depth (`--min-column-length`) |
| `-f` | per-chromosome BAM | Input BAM |
| `-r` | `references.fasta` | Reference FASTA |
| `-g` | chromosome name | Restrict output to this region |
| `-o` | output file | Output table path |

> `-c` is **not** a coverage flag in reditools.py — it creates the homopolymeric file.
> Coverage is set via `-l` / `--min-column-length`.

**Output format** (`results/tools/{aligner}/reditools/{condition}_{sample}.output`):

```
Region   Position   Reference   Strand   Coverage-q30   MeanQ   BaseCount[A,C,G,T]   AllSubs   Frequency   gCoverage-q30   gMeanQ   gBaseCount[A,C,G,T]   gAllSubs   gFrequency
chr12    6534513    C           2        74             34.49   [0, 73, 0, 1]        CT        0.01        -               -        -                     -          -
chr12    6534550    A           2        1879           35.16   [1878, 0, 1, 0]      AG        0.00        -               -        -                     -          -
```

| Column | Description |
|---|---|
| `Region` | Chromosome |
| `Position` | 1-based genomic coordinate |
| `Reference` | Reference base |
| `Strand` | Strand: 0=unknown, 1=+, 2=− |
| `Coverage-q30` | Read depth passing base-quality filter |
| `MeanQ` | Mean base quality at the position |
| `BaseCount[A,C,G,T]` | Read counts per base |
| `AllSubs` | Observed substitution types (e.g. `AG` = A→G change) |
| `Frequency` | Editing frequency (fraction of reads with the non-reference base) |
| `gCoverage-q30` … `gFrequency` | DNA columns (populated when matched DNA BAM is provided; `-` here for RNA-only mode) |

---

### REDItools3 (reditools analyze)

**Container:** `redinet.sif` (conda env `REDInet`, Python 3.10)  
**GitHub:** https://github.com/BioinfoUNIBA/REDItools2  
**Mode:** Per-sample; RNA-only.

**Command:**
```
python3.10 -m reditools analyze {input.bam} \
    -r {ref} \
    -o {output} \
    -s {strand} \
    -q {map_quality} \
    -bq {base_quality} \
    -l {min_coverage}
```

| Flag | Value | Meaning |
|---|---|---|
| (positional) | BAM path | Input alignment file |
| `-r` | `references.fasta` | Reference FASTA |
| `-o` | output `.txt` | Output table path |
| `-s` | `params.common.strandedness` → 0/1/2 | Strand: 0=unstranded, 1=second-strand, 2=first-strand |
| `-q` | `params.reditools3.map_quality` (20) | Minimum mapping quality |
| `-bq` | `params.common.base_quality` (30) | Minimum base quality |
| `-l` | `params.common.min_coverage` (5/10) | Minimum read depth (`--min-read-depth`) |

**Output format** (`results/tools/{aligner}/reditools3/{condition}_{sample}.txt`):

```
Region   Position   Reference   Strand   Coverage   MeanQ   BaseCount[A,C,G,T]   AllSubs   Frequency   gCoverage   gMeanQ   gBaseCount[A,C,G,T]   gAllSubs   gFrequency
chr12    6534513    C           *        74         34.49   [0, 73, 0, 1]        CT        0.01        -           -        -                     -          -
```

Columns are identical to REDItools v1. The `Strand` field shows `*` for unstranded mode
(vs. `0`/`1`/`2` in v1).

---

### SPRINT

**Container:** `sprint.sif` (Python 2.7, BWA 0.7.12, SAMtools 1.2)  
**GitHub:** https://github.com/jumphone/SPRINT  
**Mode:** Per-sample; SNP-free, internally uses BWA re-alignment of unmapped reads to recover
hyper-edited sites.

**MAPQ rewrite prerequisite:** STAR and HISAT2 emit MAPQ=255 for unique alignments, which
SPRINT rejects. The `sprint_mapq_bam` rule rewrites MAPQ to 30 using `rewrite_mapq.py`
(a pysam-based script bundled in the SPRINT container) before running SPRINT. BWA assigns
real MAPQ values and skips this rewrite step.

```
python3 /usr/local/bin/rewrite_mapq.py {input.bam} {output.bam} 30
samtools index {output.bam}
```

**SPRINT command:**
```
python /opt/sprint/sprint_from_bam.py \
    -rp {rmsk.txt} {input.bam} {ref} {output_dir} samtools
```

| Argument | Value | Meaning |
|---|---|---|
| `-rp` | `data/rmsk.txt` | RepeatMasker table (unzipped from `references.rmsk`) for Alu/repeat annotation |
| (positional 1) | BAM path | Input BAM (MAPQ-rewritten for STAR/HISAT2) |
| (positional 2) | reference FASTA | Reference genome |
| (positional 3) | output directory | Will contain `SPRINT_identified_regular.res` and `tmp/` |
| (positional 4) | `samtools` | SAMtools binary path (uses the one on PATH inside the container) |

SPRINT does not expose base-quality or min-coverage flags — it uses internal defaults based
on cluster-size thresholds (`-csad1`, `-csad2`, `-csnar`, `-csnr`).

**Output format** (`SPRINT_identified_regular.res` inside the output directory):

```
#Chrom   Start(0base)   End(1base)   Type   Supporting_reads   Strand   AD:DP
chr21    26076057       26076058     TC     1                  -        1:2
chr21    26076069       26076070     TC     1                  -        1:2
```

| Column | Description |
|---|---|
| `#Chrom` | Chromosome |
| `Start` | 0-based start coordinate |
| `End` | 1-based end coordinate |
| `Type` | Substitution type (e.g. `TC` = T→C on forward strand, equivalent to A→G on reverse) |
| `Supporting_reads` | Number of reads supporting the editing event |
| `Strand` | Strand of the editing site |
| `AD:DP` | Allele depth : total depth |

---

### bcftools mpileup/call

**Container:** `wgs.sif`  
**Mode:** Per-sample; general variant caller repurposed for editing detection.  
**SNP/repeat filtering:** dbSNP and simpleRepeat positions are excluded via an exclusion BED
built by the `prepare_editing_filters` rule (bedtools). Alu is not excluded.

**Command:**
```
bcftools mpileup -Ou --max-depth {max_depth} -q {map_q} -Q {base_q} \
    -f {ref} {input.bam} \
  | bcftools call -mv -Ou \
  | bcftools view -e 'INFO/DP<{min_cov}' -T ^{exclude.bed} -O b -o {output.bcf}
```

| Flag | Stage | Value | Meaning |
|---|---|---|---|
| `--max-depth` | `mpileup` | `params.bcftools.max_depth` (10000) | Per-position pileup depth cap |
| `-q` | `mpileup` | `params.bcftools.map_quality` (20) | Minimum mapping quality |
| `-Q` | `mpileup` | `params.common.base_quality` (30) | Minimum base quality |
| `-f` | `mpileup` | reference FASTA | Reference genome |
| `-m` | `call` | — | Multiallelic-caller model |
| `-v` | `call` | — | Output variant sites only (skip invariant) |
| `-e 'INFO/DP<N'` | `view` | `params.common.min_coverage` (5/10) | Exclude sites with depth below threshold |
| `-T ^{bed}` | `view` | `results/references/editing_exclude.bed` | Exclude positions in dbSNP + simpleRepeat BED |
| `-O b` | `view` | — | Output BCF (binary VCF) |

**Output format** (BCF; readable via `bcftools view`):

Standard VCF 4.x format. Key INFO/FORMAT fields:

```
#CHROM  POS     ID  REF  ALT  QUAL   FILTER  INFO                        FORMAT   SAMPLE
chr12   6535615 .   T    C    33.1   .       DP=9;...                    GT:PL    0/1:63,0,66
```

---

### RED-ML

**Container:** `red_ml.sif` (Perl + R 4.3.2 + randomForest)  
**GitHub:** https://github.com/BGIRED/RED-ML  
**Mode:** Per-sample; machine-learning classifier (random forest) trained on RNA-seq features.

**Command:**
```
red_ML.pl --rnabam {input.bam} --reference {ref} \
          --dbsnp {dbsnp} --simpleRepeat {simple_repeat} \
          [--alu {alu_bed}] --outdir {output_dir} -p {pval}
```

| Flag | Value | Meaning |
|---|---|---|
| `--rnabam` | deduplicated BAM | Input RNA-seq alignment |
| `--reference` | `references.fasta` | Reference FASTA |
| `--dbsnp` | `references.dbsnp` | UCSC dbSNP table (gz) — used internally to filter SNPs |
| `--simpleRepeat` | `references.simple_repeat` | Merged simpleRepeat BED |
| `--alu` | `references.alu_bed` | Alu BED (optional; positive feature for the classifier) |
| `--outdir` | output directory | Results directory |
| `-p` | `params.red_ml.p_value` (0.5) | Probability threshold: sites with `P_edit ≥ p` reported |

RED-ML does not expose base-quality or min-coverage CLI flags — filtering is handled
internally by the tool.

**Output files** inside the output directory:

| File | Description |
|---|---|
| `RNA_editing.sites.txt` | Sites passing the probability threshold (the primary result) |
| `variation.sites.feature.txt` | All variant sites with feature values used by the classifier |
| `mut.txt.gz` | All variant sites with raw pileup information |
| `snp.txt` | Putative SNP positions filtered out |
| `stat.txt` | Run statistics |

**Primary output format** (`RNA_editing.sites.txt`):

```
#Chromosome  Position  Read_depth  Reference  Reference_support_reads  Alternative  Alternative_support_reads  P_edit
chr12        6535615   9           T          4                        C            5                          0.7535
chr12        6536792   62          T          20                       C            42                         0.6432
chr12        6537154   5500        T          1888                     C            3612                       0.9595
```

| Column | Description |
|---|---|
| `#Chromosome` | Chromosome |
| `Position` | 1-based coordinate |
| `Read_depth` | Total read depth |
| `Reference` | Reference base |
| `Reference_support_reads` | Reads matching reference |
| `Alternative` | Non-reference (edited) base |
| `Alternative_support_reads` | Reads supporting the edit |
| `P_edit` | Predicted probability of being a genuine RNA editing site |

---

### JACUSA2 call-2 (differential)

**Container:** `jacusa2.sif` (OpenJDK 17, JACUSA2 v2.1.16)  
**GitHub:** https://github.com/dieterich-lab/JACUSA2  
**Mode:** Cross-condition replicate comparison (condition1 vs condition2).  
**Input BAMs:** MD-tagged via `samtools calmd` (`add_md_tag` rule) to supply the MD/NM SAM
tags that JACUSA2 requires for mismatch detection.

**Command:**
```
java -jar /opt/jacusa2/jacusa2.jar call-2 \
    -a D -q {base_quality} -c {min_coverage} -p {threads} \
    -r {output} \
    {wt_bam1},{wt_bam2},... {ko_bam1},{ko_bam2},...
```

| Flag | Value | Meaning |
|---|---|---|
| `call-2` | — | Subcommand: two-condition comparison |
| `-a D` | `params.jacusa2.pileup_filter` (`D`) | Pileup filter: `D` discards deletion-containing positions |
| `-q` | `params.common.base_quality` (30) | Minimum base quality (BASQ) |
| `-c` | `params.common.min_coverage` (5/10) | Minimum coverage per condition |
| `-p` | 5 (threads) | Parallel worker threads |
| `-r` | `results/tools/{aligner}/jacusa2/Jacusa.out` | Output file |
| positional group 1 | comma-separated condition1 BAMs | e.g., WT replicates |
| positional group 2 | comma-separated condition2 BAMs | e.g., ADAR1KO replicates |

**Output format** (`Jacusa.out`):

The first line is a `##` comment recording the full command line and JACUSA2 version.

```
## JACUSA2 Version: 2.1.16 (main) call-2 -a D -q 30 -c 5 ...
#contig  start     end       name    score     strand  bases11      bases12      bases13      bases21      bases22      bases23      info  filter  ref
chr12    6534470   6534471   call-2  1.2466    .       0,0,5,0      0,0,5,0      0,0,7,0      0,0,5,0      0,0,7,0      0,2,4,0      ...         G
```

| Column | Description |
|---|---|
| `#contig` | Chromosome |
| `start` | 0-based start |
| `end` | 1-based end |
| `name` | Subcommand used (`call-2`) |
| `score` | Likelihood-ratio test score |
| `strand` | Strand (`.` = unstranded) |
| `bases1N` | A,C,G,T counts for condition 1 replicate N |
| `bases2N` | A,C,G,T counts for condition 2 replicate N |
| `info` | Estimation diagnostics |
| `filter` | Applied JACUSA2 filters (e.g. `D` = deleted) |
| `ref` | Reference base |

---

### JACUSA2 call-1 (per-sample)

**Container:** `jacusa2.sif`  
**Mode:** Per-sample variant calling against the reference genome. Unlike call-2, no second
condition is required; it detects any site where the read allele distribution deviates
significantly from a single reference base.

**Command:**
```
java -jar /opt/jacusa2/jacusa2.jar call-1 \
    -a D -q {base_quality} -c {min_coverage} -p {threads} \
    -r {output} {input.bam}
```

Parameters are identical to call-2 except only one BAM is passed.

**Output format** (`results/tools/{aligner}/jacusa2_call1/{condition}_{sample}.out`):

```
## JACUSA2 Version: 2.1.16 (main) call-1 -a D -q 30 -c 5 ...
#contig  start     end       name    score     strand  bases11      info  filter  ref
chr12    6534512   6534513   call-1  0.3632    .       0,73,0,1     ...         C
```

Columns are as call-2, with a single `bases11` column (A,C,G,T counts for the one sample).

**Downstream filter option (`params.jacusa2.call1_filter`):**

| Value | Behaviour |
|---|---|
| `edit_type` | Keep only sites matching `params.common.edit_type` (A→G / T→C); used for cross-tool comparison |
| `unfiltered` | Report all sites JACUSA2 called; used for genome-browser tracks |

---

### REDInet (REDItoolDnaRna → classifier)

**Containers:** `reditools2.sif` (step 1), `redinet.sif` (steps 2–3)  
**GitHub:** https://github.com/BioinfoUNIBA/REDInet  
**Mode:** Per-sample; two-stage pipeline: REDItoolDnaRna.py generates candidate sites,
REDInet_Inference classifies them with a pre-trained Temporal Convolutional Network.

#### Step 1 — REDItoolDnaRna.py (per chromosome)

Run in parallel per chromosome via `reditools_redinet_by_chrom`, then merged by
`join_reditools_redinet_output`.

```
python /opt/reditools/main/REDItoolDnaRna.py \
    -i {chrom.bam} \
    -f {ref} \
    -o {output_dir} \
    -s {strand} \
    -e -u \
    -q 0,{base_quality} \
    -m 0,{map_quality} \
    -c 0,{min_cov} \
    -t {threads}
```

| Flag | Value | Meaning |
|---|---|---|
| `-i` | per-chromosome BAM | Input RNA-seq BAM |
| `-f` | `references.fasta` | Reference FASTA |
| `-o` | output directory | Writes `outTable_{PID}` file inside this directory |
| `-s` | `params.common.strandedness` → 0/1/2 | Strand: 0=unstranded, 1=second-strand (read1 fwd), 2=first-strand (read1 rev) |
| `-e` | — | Exclude multi-hit reads in RNA-seq |
| `-u` | — | Consider mapping quality in RNA-seq filtering |
| `-q 0,N` | 30 | Min base quality: DNA=0 (no DNA BAM), RNA=`base_quality` |
| `-m 0,N` | 0,20 | Min mapping quality: DNA=0, RNA=`map_quality` |
| `-c 0,N` | 0,5 | Min read coverage: DNA=0, RNA=`min_coverage` |
| `-t` | 1 | Threads (parallelism handled by Snakemake per-chromosome dispatch) |

The per-chromosome `outTable_{PID}` files are merged and then bgzipped + tabix-indexed:

```
bgzip -c outTable_merged > {sample}.output.gz
tabix -s 1 -b 2 -e 2 -S 1 {sample}.output.gz
```

`tabix` flags: `-s 1` (sequence column 1), `-b 2`/`-e 2` (start/end column 2), `-S 1`
(skip 1 header line).

#### Step 2 — REDInet light inference

```
python REDInet_Inference_light_ver.py \
    -r {input.gz} \
    -m REDInet.h5 \
    -o {output_prefix} \
    -c {cov_threshold} \
    -f {agfreq_threshold} \
    -s {min_ag_subs} \
    -ref {ref}
```

| Flag | Value | Meaning |
|---|---|---|
| `-r` | tabix-indexed `.output.gz` | REDItools outTable (bgzipped + tabix-indexed) |
| `-m` | `REDInet.h5` | Pre-trained TCN model file |
| `-o` | output prefix | Base path for `.predictions.tsv`, `.feature_vectors.tsv`, `.REDInet_ligth_ver_parameters.tsv` |
| `-c` | `params.redinet.cov_threshold` (5) | Minimum coverage for REDInet candidates |
| `-f` | `params.redinet.agfreq_threshold` (0.01) | Minimum A→G editing frequency |
| `-s` | `params.redinet.min_ag_subs` (1) | Minimum number of A→G substitution reads |
| `-ref` | `references.fasta` | Reference FASTA |

If no candidate sites pass the pre-filters, the pipeline writes empty output files without
error (the REDInet wrapper handles this gracefully).

**Output files:**

| File | Description |
|---|---|
| `{sample}.predictions.tsv` | Per-site classification result (primary output) |
| `{sample}.feature_vectors.tsv` | Feature matrix used for classification |
| `{sample}.REDInet_ligth_ver_parameters.tsv` | Run parameters |

**Predictions format** (`{condition}_{sample}.predictions.tsv`):

```
region  position  Strand  FreqAGrna  [A,C,G,T]  start  stop  int_len  TabixLen  snp_proba  ed_proba  y_hat
```

| Column | Description |
|---|---|
| `region` | Chromosome |
| `position` | Coordinate |
| `Strand` | Strand |
| `FreqAGrna` | A→G editing frequency in RNA |
| `[A,C,G,T]` | Base counts |
| `snp_proba` | Probability of being an SNP |
| `ed_proba` | Probability of being a genuine edit |
| `y_hat` | Binary classification: 1=editing, 0=SNP |

---

### MARINE (marine.py)

**Container:** `marine.sif` (conda env `marine`, Python 3.8)  
**GitHub:** https://github.com/yeolab/marine  
**Mode:** Per-sample; bulk A-to-I detection on an MD-tagged BAM with gene annotation.  
**Parallelization:** Per-chromosome, mirroring REDItools. The MD-tagged BAM is split by
chromosome (`split_marine_md_bam_by_chrom`, reusing the `get_chrom_list` checkpoint), MARINE
runs on each single-chromosome BAM with `--contigs {chrom}` (`marine_by_chrom`), and the
per-chrom `final_filtered_site_info.tsv` files are concatenated (header kept once) and
gzipped by `join_marine_output`.

> **Container note:** MARINE imports `numba`/`matplotlib`, which fail under a read-only
> `$HOME`. The rule exports `NUMBA_CACHE_DIR` and `MPLCONFIGDIR` to fresh temp dirs.
> The entrypoint is `/opt/conda/envs/marine/bin/python /opt/marine/marine.py`.

**Command:**
```
python /opt/marine/marine.py \
    --bam_filepath {input.bam} --output_folder {outdir} \
    --annotation_bedfile_path {marine_annotation_bed} \
    --contigs {chrom} --strandedness {strandedness} \
    --min_read_quality {min_read_quality} --min_base_quality {base_quality} \
    [--paired_end] --cores {threads}
```

| Flag | Value | Meaning |
|---|---|---|
| `--bam_filepath` | `{aligner}/{cond}_{samp}.rmdup_MD.bam` | MD-tagged, indexed BAM (from `add_md_tag`) |
| `--annotation_bedfile_path` | `references.marine_annotation_bed` | Gene BED6 (`generate_marine_annotation`, from GTF `gene` features) |
| `--contigs` | chromosome wildcard | Restricts processing to the split chromosome |
| `--strandedness` | `params.common.strandedness` → 0/1/2 (default reverse_stranded = 2) | Strand model; configurable |
| `--min_read_quality` | `params.marine.min_read_quality` (20) | Minimum MAPQ |
| `--min_base_quality` | `params.common.base_quality` (30) | Minimum base quality (harmonized with other callers) |
| `--paired_end` | set per-sample iff `is_paired()` is true | Dedupe overlapping mate coverage (slower, accurate) |
| `--cores` | rule `threads` (4) | CPUs; matched to allocated threads |

Barcode flags (`--barcode_tag`, `--barcode_whitelist_file`) are single-cell only and omitted
for bulk. Intermediate files are not kept (`--keep_intermediate_files` is not passed).

**Output:** `final_filtered_site_info.tsv` (per output folder). MARINE reports **all** twelve
conversion types genome-wide, so the raw joined file is gzipped to
`final_filtered_site_info.tsv.gz`, and `filter_marine_by_edit_type` derives the comparison
input by keeping only rows whose `strand_conversion` equals the configured edit type
(`params.common.edit_type` "AG" → `A>G`). The edit type is baked into the filtered filename
(`final_filtered_site_info.AG.tsv`) so changing `edit_type` regenerates the filter without
rerunning MARINE (the TSCC profile uses `rerun-triggers: mtime`).

Key columns of `final_filtered_site_info.tsv`:

| Column | Description |
|---|---|
| `contig`, `position` | 1-based site coordinate |
| `ref`, `alt`, `strand` | Reference/alt base and strand |
| `count` | Edited-read count |
| `coverage` | Site coverage (edit fraction = `count / coverage`; MARINE has no fraction column) |
| `conversion` | Genomic ref>alt (e.g. `T>C`) |
| `strand_conversion` | Strand-corrected conversion (e.g. `A>G`); the column the edit-type filter matches |

---

## Shared candidate-site pipeline (GIREMI + EditPredict)

**Containers:** `reditools2.sif` (mpileup + adapters), `bedtools.sif` (intersects)
**Scripts:** `mpileup_to_candidates.py`, `finalize_candidates.py`
**Purpose:** Build one caller-independent candidate set per sample, consumed by both GIREMI
and EditPredict, so the two methods see the same sites and stay independent of the other
callers.

Flow (only `mpileup` fans out per chromosome; the rest run once per sample):

```
split_bam_by_chrom → candidate_sites_by_chrom (samtools mpileup | mpileup_to_candidates.py)
  → join_candidate_sites (newline-safe awk merge → candidates.bed.gz, retained)
  → annotate_candidate_strand (bedtools intersect: gene strand + dbSNP membership)
  → finalize_candidate_sites (GIREMI 6-col SNV list + EditPredict positions, both gzipped)
```

| Filter | Source | Meaning |
|---|---|---|
| coverage | `params.common.min_coverage` | min read depth (BQ-filtered in the adapter) |
| base quality | `params.common.base_quality` | per-base Phred floor, applied from the pileup quality string |
| `min_alt_reads` | `params.candidates.min_alt_reads` (default 2) | min reads supporting the editing substitution — bounds candidate-set size |

All substitution types are kept (GIREMI's mutual-information step needs SNP anchors); the
A→I strand is fixed by the substitution (`A>G`→`+`, `T>C`→`−`), other types take the gene
strand, and `#` is written only for strand-uninformative intergenic sites. The EditPredict
positions view is the A→I subset.

---

### GIREMI

**Container:** `giremi.sif` (GIREMI 0.3.1 + htslib 1.9 + R + Python)
**GitHub:** https://github.com/zhqingit/giremi
**Mode:** Per-sample, RNA-only, candidate-based; identifies A→I edits by mutual information
between a candidate site and nearby SNPs.

**Command:**
```
giremi -f {ref} -l {candidate_snv_list} -o {prefix} \
       -m {min_coverage} -p {paired} -s {strand} {bam}
```

| Flag | Value | Meaning |
|---|---|---|
| `-f` | `ref_iupac_masked.fasta` | faidx'd reference |
| `-l` | finalized GIREMI 6-col SNV list | candidate SNVs (`chrom start0 end1 gene\|Inte dbSNP strand`) |
| `-m` | `params.common.min_coverage` | min coverage at candidate sites |
| `-p` | `is_paired()` → 1/0 | paired/single-end |
| `-s` | `strand_flags.reditools` (0/1/2) | strand model (read-1 sense/antisense; matches REDItools) |

**Output** (`{condition}_{sample}.txt.gz`): GIREMI `.res` table (written by `giremi.r` via R
`write.table`, so the header has one fewer field than the data rows). Editing sites are
`ifRNAE ∈ {1 (MI), 2 (GLM)}`; `RNAE_t` holds the substitution class, `tot_count` the depth,
`estimated_allelic_ratio` the editing level. Parsed by `parse_giremi` into the comparison
matrices and consensus.

---

### EditPredict

**Container:** `editpredict.sif` (TensorFlow CPU + Keras Alu model)
**GitHub:** https://github.com/wjd198605/EditPredict
**Mode:** Per-sample CNN classifier; scores the shared A→I candidate positions from flanking
sequence. It discovers nothing itself — its call set is candidate sites passing the model.

**Command (via the `editpredict_score` wrapper):**
```
editpredict_score --reference {ref_iupac_masked.fasta} \
                  --positions {candidate_positions} --output {scores}
```
Internally: `get_seq.py` extracts the flanking sequence, `editPredict.py` scores it. The
container's `editPredict.py` was patched (`containers/editpredict/fix_upstream.py`) to emit a
mappable TSV `chrom  pos  prob_edit  pred_class` (upstream printed only raw arrays and
corrupted chrom names). The masked reference turns IUPAC codes into N (unscorable) instead of
crashing the one-hot encoder.

**Output** (`{condition}_{sample}_scores.txt.gz`): `chrom pos prob_edit pred_class`. Sites
with `prob_edit ≥ 0.5` (`parse_editpredict`) enter the comparison matrices. EditPredict
reports no coverage, so coverage is 0 and fraction/score carry the probability.

> **Rebuild note:** `editpredict.sif` must be rebuilt after the `fix_upstream.py` change for
> the mappable output to take effect.

---

### REDITs (differential)

**Container:** `redits.sif` (R 4.3.2, base-R only)
**GitHub:** https://github.com/gxiaolab/REDITs
**Mode:** Two-condition statistical test (REDIT-LLR, beta-binomial), **not** a caller. Runs
when `jacusa2_comparison` is set, reusing its condition1/condition2 groups.

**Flow:** `build_redits_counts.py` builds a per-site **integer** `edited,total` matrix from
the chosen caller's native columns (REDItools `BaseCount` + `Coverage` — never
`fraction × coverage`), keeping sites covered in all samples; `redits_llr.R` runs REDIT-LLR
per site.

**Output:** `results/differential_editing/redits/{aligner}/redit_llr_{caller}.tsv.gz`
(`chrom  pos  p_value`). Not part of the per-sample overlap matrices.

---

### LoDEI (differential)

**Container:** `lodei.sif` (Bioconda LoDEI 1.0.0)
**GitHub:** https://github.com/rna-editing1/lodei
**Mode:** Windowed two-group differential editing. Gated on a `lodei_comparison` block.

**Command:**
```
lodei find -a {group1_bams} -b {group2_bams} -f {ref} -g {gtf} -o {outdir} \
           -c {cores} -w {window_size} -m {min_coverage} -l {library}
```

| Flag | Value | Meaning |
|---|---|---|
| `-a` / `-b` | condition1 / condition2 BAMs | the two groups |
| `-f` | `ref_iupac_masked.fasta` | reference (same as used for BAMs) |
| `-g` | `references.gtf` | annotation (regions searched for local editing) |
| `-w` | `params.lodei.window_size` (25) | half-window; full window = 2w+1 |
| `-m` | `params.common.min_coverage` | min coverage in all samples |
| `-l` | `params.lodei.library` (SR) | library type |

The rule exports `MPLCONFIGDIR` to a writable temp dir (LoDEI imports matplotlib). Output is
a directory of differentially edited regions under `results/tools/{aligner}/lodei/`.

---

## Orthogonal verification

All command-line flags listed above were confirmed against the `--help` output of each tool
invoked directly from its Singularity container, using:

```bash
module load singularitypro
singularity exec singularity/{tool}.sif {tool_cmd} --help
```

| Tool | Container | Verification method |
|---|---|---|
| `reditools.py` | `reditools2.sif` | `reditools.py --help` → confirmed `-S`, `-C`, `-bq`, `-q`, `-l`, `-f`, `-r`, `-g`, `-o` |
| `reditools analyze` | `redinet.sif` | `python3.10 -m reditools analyze --help` → confirmed `-r`, `-o`, `-s`, `-q`, `-bq`, `-l` |
| `sprint_from_bam.py` | `sprint.sif` | `python sprint_from_bam.py --help` → confirmed `-rp`, positional BAM/ref/outdir/samtools |
| `bcftools mpileup` | `wgs.sif` | `bcftools mpileup --help` → confirmed `--max-depth`, `-q`, `-Q`, `-f` |
| `bcftools call` | `wgs.sif` | `bcftools call --help` → confirmed `-m`, `-v` |
| `bcftools view` | `wgs.sif` | `bcftools view --help` → confirmed `-e`, `-T ^` |
| `red_ML.pl` | `red_ml.sif` | `red_ML.pl --help` → confirmed `--rnabam`, `--reference`, `--dbsnp`, `--simpleRepeat`, `--alu`, `--outdir`, `-p` |
| `jacusa2.jar call-2` | `jacusa2.sif` | `jacusa2.jar call-2 --help` → confirmed `-a`, `-q`, `-c`, `-p`, `-r`; version confirmed from output header: `2.1.16` |
| `jacusa2.jar call-1` | `jacusa2.sif` | `jacusa2.jar call-1 --help` → confirmed same flags as call-2 |
| `REDItoolDnaRna.py` | `reditools2.sif` | `REDItoolDnaRna.py --help` → confirmed `-i`, `-f`, `-o`, `-s`, `-e`, `-u`, `-q`, `-m`, `-c`, `-t` |
| `REDInet_Inference_light_ver.py` | `redinet.sif` | Wrapper `redinet_classify --help` + script internals → confirmed `-r`, `-o`, `-c`, `-f`, `-s`, `-ref` |

Additionally, JACUSA2 version and exact flags were cross-checked against the `## JACUSA2 Version:` comment lines embedded in actual output files from `examples/Morales_et_al_small`, which record the full command that produced them.
