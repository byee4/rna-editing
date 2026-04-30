# --- Shared Preprocessing and BAM Cleanup ---

# Picard: Mark duplicates to prevent PCR bias from inflating editing levels [17-19]
rule mark_duplicates:
    input:
        bam=WORKDIR + "/mapped/{sample}.{type}.bam"
    output:
        bam=WORKDIR + "/dedup/{sample}.{type}.bam",
        metrics=WORKDIR + "/dedup/{sample}.{type}.metrics.txt"
    container: container_for("picard")
    log:
        stderr=WORKDIR + "/logs/{sample}.{type}.mark_duplicates.err"
    shell:
        "picard MarkDuplicates I={input.bam} O={output.bam} M={output.metrics} "
        "REMOVE_DUPLICATES=true 2> {log.stderr}"


# JACUSA2: Mandatory MD tag population [10, 11]
rule samtools_calmd:
    input:
        bam=WORKDIR + "/dedup/{sample}.{type}.bam",
        ref=REF
    output:
        bam=WORKDIR + "/mapped/{sample}.{type}.md.bam"
    container: container_for("samtools")
    log:
        stderr=WORKDIR + "/logs/{sample}.{type}.calmd.err"
    shell:
        "samtools calmd -b {input.bam} {input.ref} > {output.bam} 2> {log.stderr}"
