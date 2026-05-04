# --- Shared Preprocessing and BAM Cleanup ---

# Picard MarkDuplicates removes PCR duplicates that can inflate editing levels [17-19].
# Sources: GitHub https://github.com/broadinstitute/picard; docs https://broadinstitute.github.io/picard/
rule mark_duplicates:
    input:
        bam=WORKDIR + "/mapped/{sample}.{type}.bam"
    output:
        bam=WORKDIR + "/dedup/{sample}.{type}.bam",
        metrics=WORKDIR + "/dedup/{sample}.{type}.metrics.txt"
    wildcard_constraints:
        type="rna|wgs"
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 180 * (2 ** (attempt - 1))
    container: container_for("picard")
    log:
        stderr=WORKDIR + "/logs/{sample}.{type}.mark_duplicates.err"
    shell:
        "picard MarkDuplicates I={input.bam} O={output.bam} M={output.metrics} "
        "REMOVE_DUPLICATES=true ASSUME_SORT_ORDER=coordinate TMP_DIR=$TMPDIR "
        "2> {log.stderr}"


# SAMtools calmd populates MD tags required by downstream JACUSA2 comparisons [10, 11].
# Sources: GitHub https://github.com/samtools/samtools; publication https://doi.org/10.1093/bioinformatics/btp352
rule samtools_calmd:
    input:
        bam=WORKDIR + "/dedup/{sample}.{type}.bam",
        ref=REF
    output:
        bam=WORKDIR + "/mapped/{sample}.{type}.md.bam"
    wildcard_constraints:
        type="rna|wgs"
    resources:
        mem_mb=lambda wildcards, attempt: 32000 * (1.5 ** (attempt - 1)),
        runtime=lambda wildcards, attempt: 180 * (2 ** (attempt - 1))
    container: container_for("samtools")
    log:
        stderr=WORKDIR + "/logs/{sample}.{type}.calmd.err"
    shell:
        "samtools calmd -b {input.bam} {input.ref} > {output.bam} 2> {log.stderr}"
