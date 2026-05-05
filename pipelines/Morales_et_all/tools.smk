rule reditools:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        "results/tools/reditools/{condition}_{sample}.output"
    params:
        ref=config["references"]["fasta"],
        script=config["tools"]["reditools_script"]
    shell:
        """
        python {params.script} -S -C -bq 20 -q 20 -f {input.bam} -r {params.ref} -o {output}
        """

rule sprint:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        "results/tools/sprint/{condition}_{sample}_output" 
    params:
        ref=config["references"]["fasta"],
        rmsk=config["references"]["rmsk"],
        sprint_bin=config["tools"]["sprint_bin"],
        samtools_bin=config["tools"]["samtools_bin"]
    shell:
        """
        {params.sprint_bin} -rp {params.rmsk} {input.bam} {params.ref} {output} {params.samtools_bin}
        """

rule bcftools:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        "results/tools/bcftools/{condition}_{sample}.bcf"
    params:
        ref=config["references"]["fasta"],
        max_depth=config["params"]["bcftools"]["max_depth"],
        map_q=config["params"]["bcftools"]["map_quality"],
        base_q=config["params"]["bcftools"]["base_quality"]
    shell:
        """
        bcftools mpileup -Ou --max-depth {params.max_depth} -q {params.map_q} -Q {params.base_q} -f {params.ref} {input.bam} | \
        bcftools call -mv -O b -o {output}
        """

rule red_ml:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        directory("results/tools/red_ml/{condition}_{sample}_output")
    params:
        ref=config["references"]["fasta"],
        dbsnp=config["references"]["dbsnp"],
        simple_repeat=config["references"]["simple_repeat"],
        alu=config["references"]["alu_bed"],
        script=config["tools"]["red_ml_script"],
        pval=config["params"]["red_ml"]["p_value"]
    shell:
        """
        perl {params.script} --rnabam {input.bam} --reference {params.ref} \
             --dbsnp {params.dbsnp} --simpleRepeat {params.simple_repeat} \
             --alu {params.alu} --outdir {output} -p {params.pval}
        """

# ---------------------------------------------------------
# JACUSA2 Aggregate Rules
# ---------------------------------------------------------
rule add_md_tag:
    input:
        bam="results/mapped/{condition}_{sample}.rmdup.bam"
    output:
        bam="results/mapped/{condition}_{sample}.rmdup_MD.bam"
    params:
        ref=config["references"]["fasta"]
    shell:
        """
        samtools calmd {input.bam} {params.ref} > {output.bam}
        """

rule jacusa2:
    input:
        wt_bams=expand("results/mapped/WT_{sample}.rmdup_MD.bam", sample=config["samples"]),
        ko_bams=expand("results/mapped/ADAR1KO_{sample}.rmdup_MD.bam", sample=config["samples"])
    output:
        "results/tools/jacusa2/Jacusa.out"
    params:
        jacusa_jar=config["tools"]["jacusa2_jar"],
        pileup=config["params"]["jacusa2"]["pileup_filter"]
    threads: 5
    shell:
        """
        wt_list=$(echo {input.wt_bams} | tr ' ' ',')
        ko_list=$(echo {input.ko_bams} | tr ' ' ',')
        java -jar {params.jacusa_jar} call-2 -a {params.pileup} -p {threads} -r {output} $wt_list $ko_list
        """