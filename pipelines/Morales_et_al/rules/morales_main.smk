# Include modular workflows (paths relative to this file's directory: rules/)
# rule all and _WGS_DB_FILES live in the top-level Snakefile so that
# Snakemake 9 uses rule all as the default target.
include: "preprocessing.smk"
include: "tools.smk"
include: "morales_downstream.smk"
include: "references.smk"
include: "wgs.smk"
