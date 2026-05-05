# Conflicts and Resolutions

## C-001: RED vs RED-ML container

**Conflict**: `containers/red/` exists but is for RED (Java GUI app). The Morales pipeline calls `red_ML.pl` which is a different tool (RED-ML, Perl+R).

**Resolution**: Create `containers/red_ml/` as a NEW container. Do not modify or reuse `containers/red/`. The two tools are unrelated despite the similar names.

## C-002: STAR container identity

**Conflict**: `editing_wgs` maps `container_for("star")` → `lodei.sif`. LoDEI's biocontainer happens to bundle STAR. Creating a new `containers/star/` would create a second STAR image.

**Resolution**: Create `containers/star/` as a lean, purpose-built STAR + samtools container for the Morales pipeline. Don't use `lodei.sif` as the star container — that's an accidental dependency. The two SIF files can coexist; the Morales config will point to `star.sif`.

## C-003: Downstream scripts vs empty submodule

**Conflict**: The `Downstream/*.py` scripts in `downstream.smk` come from the Morales benchmark repo (`Benchmark-of-RNA-Editing-Detection-Tools`), which is an empty git submodule. The scripts don't exist in the current checkout.

**Resolution**: 
1. Add `downstream_scripts_dir` to `config.yaml` pointing to the submodule path.
2. Use `{params.downstream_dir}/REDItools2.py` in shell blocks.
3. Note in config comment that the submodule must be initialized (`git submodule update --init`).
4. The `morales_downstream` container provides Python 3 + pandas/numpy for these scripts.

## C-004: Tool path cleanup scope

**Conflict**: The `tools:` section in `config.yaml` has absolute paths like `~/bin/picard-tools/MarkDuplicates.jar`. Should these be removed or preserved as fallbacks?

**Resolution**: Replace the entire `tools:` section with a `containers:` block (matching editing_wgs pattern). Remove `picard_jar`, `reditools_script`, `sprint_bin`, `jacusa2_jar`, `red_ml_script`, `samtools_bin` — these are all superseded by containers. Keep only tool-specific PARAMETERS (like flags/thresholds) that differ from defaults.

## C-005: `add_md_tag` container

**Conflict**: `add_md_tag` runs `samtools calmd`. Both `containers/wgs/` (has samtools) and `containers/jacusa2/` (has samtools via mamba) could serve this role.

**Resolution**: Use `wgs` as the container for `add_md_tag` and `bcftools` rules. The `wgs` container is explicitly for "SAMtools, BCFtools" operations and avoids pulling in JACUSA2's mamba overhead.
