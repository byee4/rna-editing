rule trim_reads:
    input:
        reads="data/fastq/{condition}_{sample}_{read}.fastq"
    output:
        "results/trimmed/{condition}_{sample}_{read}_trimmed.fastq.gz"
    params:
        q=config["params"]["fastx_trimmer"]["quality"],
        l=config["params"]["fastx_trimmer"]["length"]
    shell:
        """
        fastx_trimmer -Q{params.q} -l {params.l} -z -i {input.reads} -o {output}
        """

rule star_mapping:
    input:
        r1="results/trimmed/{condition}_{sample}_R1_trimmed.fastq.gz",
        r2="results/trimmed/{condition}_{sample}_R2_trimmed.fastq.gz"
    output:
        bam="results/mapped/{condition}_{sample}.bam",
        bai="results/mapped/{condition}_{sample}.bam.bai"
    params:
        ref_dir=config["references"]["star_index"],
        prefix="results/mapped/{condition}_{sample}_",
        map_qual=config["params"]["star"]["map_quality"]
    threads: config["threads"]
    shell:
        """
        # Align with STAR
        STAR --runThreadN {threads} --genomeDir {params.ref_dir} \
             --readFilesIn {input.r1} {input.r2} --readFilesCommand zcat \
             --outSAMtype BAM SortedByCoordinate --outFileNamePrefix {params.prefix}
        
        # Filter (unmapped, improper pairs, mapping quality) and Sort
        samtools view -@ {threads} -F 0x04 -f 0x2 -q {params.map_qual} -b {params.prefix}Aligned.sortedByCoord.out.bam | \
        samtools sort -@ {threads} -T {params.prefix}tmp -o {output.bam}
        
        # Index
        samtools index -@ {threads} {output.bam}
        
        # Cleanup STAR intermediate files
        rm {params.prefix}Aligned.sortedByCoord.out.bam
        """

rule mark_duplicates:
    input:
        bam="results/mapped/{condition}_{sample}.bam"
    output:
        rmdup_bam="results/mapped/{condition}_{sample}.rmdup.bam",
        metrics="results/mapped/{condition}_{sample}.duplication.info"
    params:
        picard=config["tools"]["picard_jar"]
    shell:
        """
        java -jar {params.picard} INPUT={input.bam} OUTPUT={output.rmdup_bam} \
             METRICS_FILE={output.metrics} REMOVE_DUPLICATES=true
        """