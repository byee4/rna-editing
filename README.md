# RNA Editing Tool Containers

This repository builds Docker and Singularity/Apptainer containers for the RNA
editing tools summarized in `Dockerfile_description.md`.

See `docs/containerization.md` for the build layout, validation workflow, and
artifact locations under `/Volumes/X9Pro/container_data/rna-editing`.

The matched RNA/WGS workflow in `pipelines/editing_wgs` accepts single-end or
paired-end RNA-seq and WGS FASTQs per sample. It produces matched DNA/RNA
comparison calls, WGS-only coverage and germline variant outputs, plus RNA-only
SPRINT, REDItools v1 / REDInet, DeepRED, editPredict, and REDI-NET outputs; see
`pipelines/editing_wgs/README.md` for configuration and usage. The workflow
configs are `pipelines/editing_wgs/config.data.example.yaml` for the small
example inputs under `data/small_examples/random` and
`pipelines/editing_wgs/config.yaml` for the full `data/` inputs.

For HEK293-family variant references, `scripts/download_variant_data.sh`
creates modality-specific folders, downloads the public DepMap CCLE mutation
table, and writes follow-up fetch helpers for WGS SRA reads and GEO VCF
supplementary files. Review generated helper scripts before running them because
some sources require database-specific access tools or accession-specific URLs.

Run the pipeline with: 
```bash
module load singularitypro;
conda activate snakemake9;
cd examples;
unset SLURM_JOB_ID # required if running on an interactive node, which is reccomended
snakemake -kps /tscc/nfs/home/bay001/projects/codebase/rna-editing/pipelines/Morales_et_al/Snakefile \
--configfile /tscc/nfs/home/bay001/projects/codebase/rna-editing/examples/Morales_et_al/config_small.yaml \
--profile /tscc/nfs/home/bay001/projects/codebase/rna-editing/profiles/tscc2 \
--use-singularity
```

The Morales_et_al callers share harmonized base-quality, min-coverage, and edit-type
settings (`params.common` in the config); see
[`docs/edit_calling_parameters.md`](docs/edit_calling_parameters.md) for the verified
per-tool flag matrix and the dbSNP/simpleRepeat/Alu filtering policy.

### JACUSA2 call-1 (per-sample variants vs. the reference genome)

In addition to the `call-2` WT-vs-KO contrast (one `Jacusa.out` per aligner),
the Morales_et_al pipeline runs JACUSA2 `call-1`, which identifies variants
against the reference genome from a single condition (one MD-tagged BAM). Because
`call-1` is single-condition it is **per-sample**, so its edit set is compared
against the other per-sample tools (REDItools, SPRINT, RED-ML, BCFtools, REDInet, MARINE):
the `bases11` A,C,G,T counts give per-site coverage and editing fraction plus the
JACUSA2 score, which feed the comparison matrices, per-output-type correlations,
and BigBed tracks.

`call-1` reports every position it judges variant, not only A-to-I sites. How
those sites are filtered for the comparison is configurable via
`params.jacusa2.call1_filter`:

- `edit_type` (default) — **reditools-style**: keep only sites whose `ref->alt`
  matches `params.common.edit_type` (e.g. `AG` plus its reverse complement `TC`),
  matching how the other per-sample tools are filtered.
- `unfiltered` — **JACUSA2-style**: keep every site JACUSA2 `call-1` reported,
  regardless of substitution type.

The same setting governs both the cross-tool comparison
(`scripts/compare_all_tools.py`) and the BigBed track conversion
(`scripts/tool_output_to_bed.py`).

### MARINE (marine.py)

The Yeo Lab's [MARINE](https://github.com/yeolab/marine) A-to-I detector runs from
`marine.sif` on an MD-tagged BAM plus a gene-annotation BED6 derived from the reference GTF
(`generate_marine_annotation`). It is parallelized per-chromosome (split MD BAM → MARINE with
`--contigs` → join), mirroring the REDItools pattern. MARINE reports all twelve conversion
types genome-wide, so the joined output is gzipped
(`final_filtered_site_info.tsv.gz`) and an edit-type filter keeps only sites whose
`strand_conversion` matches `params.common.edit_type` (`AG` → `A>G`), producing
`final_filtered_site_info.AG.tsv` — the file fed into the comparison matrices, correlations,
consensus analysis, and BigBed tracks. The edit type is baked into the filename so changing
`edit_type` regenerates the filter without rerunning MARINE. `--strandedness` (default 2) is
configurable via `params.marine.strandedness`; `--paired_end` is set per-sample when the
samplesheet provides R2 reads. See `docs/tools_reference.md` for the full flag table.