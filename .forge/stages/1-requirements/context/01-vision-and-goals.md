# Vision and Goals

## Project Vision

The RNA editing detection project houses multiple Snakemake pipelines for identifying RNA editing events from sequencing data. The goal is that every pipeline in this repository is fully reproducible: anyone with access to the repository, the reference genome files, and the SIF container images can run any pipeline without installing tools locally.

The `editing_wgs` pipeline is already at this standard. The `Morales_et_all` pipeline is not — it hardcodes user-home tool paths and has no container directives.

## Goal for This Task

Bring `pipelines/Morales_et_all/` to the same reproducibility standard as `pipelines/editing_wgs/`:

1. **Containerized tools**: Every rule runs its tool from a Singularity/Apptainer container, not from a user-specific installation.
2. **Logged execution**: Every rule emits stdout and stderr to named log files for debugging.
3. **Resource-declared**: Every rule declares memory and runtime for SLURM scheduling.
4. **Portable config**: No user-specific paths in committed config files; all tool executables resolved from containers.
5. **Discoverable scripts**: Downstream Python scripts referenced via a config key, not bare relative paths.

## Success Metric

A new developer with no prior tool installations can clone the repo, download reference genomes, build the 4 new SIF files (plus reuse 5 existing ones), and run:

```bash
cd pipelines/Morales_et_all
snakemake --profile ../../profiles/tscc2 -n
```

...and get a valid dry-run job list with no errors.

## Non-Goals

- Performance optimization of the RNA editing tools themselves
- Adding new analysis capabilities
- Modifying the `editing_wgs` pipeline
