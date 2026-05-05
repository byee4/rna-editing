# Create placeholder rules to replicate the sequential os.system calls in Main.py

rule run_downstream_parsers:
    input:
        reditools=expand("results/tools/reditools/{condition}_{sample}.output", condition=config["conditions"], sample=config["samples"]),
        sprint=expand("results/tools/sprint/{condition}_{sample}_output", condition=config["conditions"], sample=config["samples"]),
        redml=expand("results/tools/red_ml/{condition}_{sample}_output", condition=config["conditions"], sample=config["samples"]),
        bcftools=expand("results/tools/bcftools/{condition}_{sample}.bcf", condition=config["conditions"], sample=config["samples"]),
        jacusa="results/tools/jacusa2/Jacusa.out"
    output:
        touch("results/downstream/parsers.done")
    shell:
        """
        python Downstream/REDItools2.py
        python Downstream/SPRINT.py
        python Downstream/REDML.py
        python Downstream/BCFtools.py
        python Downstream/JACUSA2.py
        """

rule update_alu:
    input:
        "results/downstream/parsers.done"
    output:
        touch("results/downstream/alu_updated.done")
    shell:
        """
        python Downstream/Alu.py
        """

rule individual_analysis:
    input:
        "results/downstream/alu_updated.done"
    output:
        touch("results/downstream/individual_analysis.done")
    shell:
        """
        python Downstream/Individual-Analysis.py
        """

rule reanalysis_multiple:
    input:
        "results/downstream/individual_analysis.done"
    output:
        touch("results/downstream/reanalysis_multiple.done")
    shell:
        """
        python Downstream/Re-Analysis-Multiple.py
        """

rule multiple_analysis:
    input:
        "results/downstream/reanalysis_multiple.done"
    output:
        touch("results/downstream/multiple_analysis.done")
    shell:
        """
        python Downstream/Multiple-Analysis.py
        """