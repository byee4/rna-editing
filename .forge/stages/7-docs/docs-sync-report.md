# Documentation Sync Report

Generated: 2026-05-07

## Summary

| Check | Status | Details |
|-------|--------|---------|
| Rule inventory vs user-guide table | SYNCED | All 22 non-localrule rules documented (14 core + 3 reference + 5 wgs = 22; all accounted for in user-guide.md stage tables) |
| Config keys vs api-reference table | SYNCED | All config keys present in api-reference.md; no undocumented keys found |
| Env vars (scripts/validate_containers.sh) vs deployment-runbook | SYNCED | `CONTAINER_DATA_ROOT`, `SIF_OUTPUT_DIR`, `DOCKER_PLATFORM`, `TOOLS` — all four documented |
| Container list vs docs | SYNCED | All 9 container keys in `config.yaml` documented in api-reference.md and user-guide.md |
| README accuracy | STALE — see below | README.md covers `editing_wgs` pipeline only; does not mention `Morales_et_all` pipeline. See readme-updates.md. |

## Detail

### Rule inventory check

Rules counted in `.smk` files (excluding `prepare_fastq` localrule):

- `preprocessing.smk`: trim_reads, star_mapping, mark_duplicates (3)
- `tools.smk`: reditools, sprint, bcftools, red_ml, add_md_tag, jacusa2 (6)
- `downstream.smk`: run_downstream_parsers, update_alu, individual_analysis, reanalysis_multiple, multiple_analysis (5)
- `rules/references.smk`: generate_simple_repeat, generate_alu_bed, build_dbrna_editing (3)
- `rules/wgs.smk`: wgs_bwa_mem, wgs_deduplicate, wgs_md_tags, wgs_call_variants, wgs_vcf_to_ag_tc_bed (5)

Total: 22 rules. All documented in user-guide.md stage tables. **SYNCED.**

### Config key check

Keys in `config.yaml`: `threads`, `samplesheet`, `aligners`, `singularity_image_dir`, `containers` (9 keys), `references` (10 subkeys), `wgs_samples`, `downstream_scripts_dir`, `params` (8 leaf values).

All present in api-reference.md §2. **SYNCED.**

### Environment variable check

Variables in `scripts/validate_containers.sh`:
- `CONTAINER_DATA_ROOT` (default `/Volumes/X9Pro/container_data`) — documented in deployment-runbook.md
- `SIF_OUTPUT_DIR` (default `${CONTAINER_DATA_ROOT}/singularity_images`) — documented
- `DOCKER_PLATFORM` (default `linux/amd64`) — documented
- `TOOLS` (default `reditools jacusa2 sprint lodei red sailor`) — documented

**SYNCED.**

### README accuracy

`README.md` at repository root covers the `editing_wgs` pipeline and container build workflow. It does not mention the `Morales_et_all` pipeline, the new containers (star, red_ml, fastx, morales_downstream), or the samplesheet-driven approach. Suggested updates in `readme-updates.md`.

**STALE** — warning only, not a blocker.
