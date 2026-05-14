# Include modular workflows (paths relative to this file's directory: rules/)
include: "preprocessing.smk"
include: "tools.smk"
include: "morales_downstream.smk"
include: "references.smk"
include: "wgs.smk"

# ==========================================
# Target Outputs
# ==========================================
_WGS_DB_FILES = (
    [
        os.path.join(config["references"]["db_path"], f)
        for f in ["HEK293T_hg38_clean.json", "REDIportal.json", "Alu_GRCh38.json"]
    ]
    if config.get("wgs_samples") else []
)

# Define the target outputs for the entire workflow
rule all:
    input:
        # Preprocessing outputs (one BAM per aligner per sample)
        expand("results/mapped/{aligner}/{condition}_{sample}.rmdup.bam",
               aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        # Tool outputs (one result per aligner per sample / per aligner for JACUSA2)
        expand("results/tools/{aligner}/reditools/{condition}_{sample}.output",
               aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        expand("results/tools/{aligner}/bcftools/{condition}_{sample}.bcf",
               aligner=_ALIGNERS, condition=config["conditions"], sample=config["samples"]),
        expand("results/tools/{aligner}/jacusa2/Jacusa.out", aligner=_ALIGNERS),
        # Reference databases — built from WGS alignment when wgs_samples is configured
        _WGS_DB_FILES,
        # Downstream analysis — single run that processes all aligners together
        "results/downstream/multiple_analysis.done",
        # Downstream JSON outputs (per-tool site summaries)
        "results/downstream/Data_REDItool2.json",
        "results/downstream/Data_SPRINT.json",
        "results/downstream/Data_REDML.json",
        "results/downstream/Data_BCFTools.json",
        "results/downstream/Data_JACUSA2.json",
        "results/downstream/Data_REDItools2-Multiple.json",
        "results/downstream/Data_SPRINT-Multiple.json",
        "results/downstream/Data_BCFTools-Multiple.json",
        "results/downstream/Data_REDML-Multiple.json",
        # Downstream comparison figures and tables
        "results/downstream/Downstream/IndividualCompare.png",
        "results/downstream/Downstream/MultipleCompare.png",
        "results/downstream/Downstream/REDItools2_Table.csv",
        "results/downstream/Downstream/BCFTools_Table.csv",
        "results/downstream/Downstream/REDItools2-Multiple_Table.csv",
        "results/downstream/Downstream/BCFTools-Multiple_Table.csv",
        "results/downstream/Downstream/JACUSA2_Table.csv",
