# User Experience

## Primary User: Pipeline Developer / Bioinformatician

The user is a bioinformatician who wants to run the Morales et al. RNA editing benchmark pipeline on TSCC (or a similar SLURM cluster with Apptainer).

## Before This Task (Current Pain Points)

1. Running `snakemake -n` in `pipelines/Morales_et_all/` succeeds, but actual execution fails because:
   - All tool paths (`~/bin/picard-tools/MarkDuplicates.jar`, etc.) are user-specific
   - No containers are specified, so tools must be installed natively
   - No log files are created, making debugging difficult
2. The dry-run does not validate container availability
3. The `Downstream/*.py` script paths are bare relative paths that only work if CWD is the pipeline directory AND the git submodule has been initialized

## After This Task (Target UX)

**Step 1: Build containers (one-time)**
```bash
# Build the 4 new containers (existing 5 are already built)
cd containers/star && docker build -t star . && apptainer build ../../singularity/star.sif docker-daemon://star:latest
cd containers/red_ml && docker build -t red_ml . && apptainer build ../../singularity/red_ml.sif docker-daemon://red_ml:latest
cd containers/fastx && docker build -t fastx . && apptainer build ../../singularity/fastx.sif docker-daemon://fastx:latest
cd containers/morales_downstream && docker build -t morales_downstream . && apptainer build ../../singularity/morales_downstream.sif docker-daemon://morales_downstream:latest
```

**Step 2: Configure**
```bash
# Edit config.yaml: set singularity_image_dir to your SIF path, set reference paths
# Initialize downstream scripts submodule (if running downstream rules):
git submodule update --init
```

**Step 3: Run**
```bash
cd pipelines/Morales_et_all
snakemake --profile ../../profiles/tscc2
```

## Key UX Invariants

- A single `snakemake -n` must complete without errors
- Log files must appear in `results/logs/` after rule execution
- No prompt for tool installation; no `module load` commands needed
- Container failures surface as clear Snakemake errors with log file paths
