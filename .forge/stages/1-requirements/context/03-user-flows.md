# User Flows

## Pipeline Data Flow

```
data/fastq/{condition}_{sample}_{read}.fastq
         |
         v [trim_reads — fastx container]
results/trimmed/{condition}_{sample}_{read}_trimmed.fastq.gz
         |
         v [star_mapping — star container]
results/mapped/{condition}_{sample}.bam + .bam.bai
         |
         v [mark_duplicates — picard container]
results/mapped/{condition}_{sample}.rmdup.bam + .duplication.info
         |
         +---> [reditools — reditools container] ---> results/tools/reditools/{condition}_{sample}.output
         +---> [sprint — sprint container] -------> results/tools/sprint/{condition}_{sample}_output/
         +---> [bcftools — wgs container] --------> results/tools/bcftools/{condition}_{sample}.bcf
         +---> [red_ml — red_ml container] -------> results/tools/red_ml/{condition}_{sample}_output/
         +---> [add_md_tag — wgs container] ------> results/mapped/{condition}_{sample}.rmdup_MD.bam
                                                         |
                                                         v [jacusa2 — jacusa2 container] (aggregates ALL samples)
                                                    results/tools/jacusa2/Jacusa.out
         |
         v [run_downstream_parsers — morales_downstream container]
results/downstream/parsers.done
         |
         v [update_alu — morales_downstream container]
results/downstream/alu_updated.done
         |
         v [individual_analysis — morales_downstream container]
results/downstream/individual_analysis.done
         |
         v [reanalysis_multiple — morales_downstream container]
results/downstream/reanalysis_multiple.done
         |
         v [multiple_analysis — morales_downstream container]
results/downstream/multiple_analysis.done  <-- FINAL TARGET
```

## Wildcard Structure

- `{condition}` ∈ `{WT, ADAR1KO}` (from `config["conditions"]`)
- `{sample}` ∈ `{clone1, clone2, clone3}` (from `config["samples"]`)
- `{read}` ∈ `{R1, R2}` (for paired-end reads, used in trim_reads and star_mapping)

## Rule Dependency Graph

```
trim_reads (per condition × sample × read)
    → star_mapping (per condition × sample)
    → mark_duplicates (per condition × sample)
    → reditools / sprint / bcftools / red_ml / add_md_tag (per condition × sample, parallel)
    → jacusa2 (aggregates WT_{clone1,2,3} and ADAR1KO_{clone1,2,3}) [depends on add_md_tag for all 6 samples]
    → run_downstream_parsers [depends on reditools × 6, sprint × 6, red_ml × 6, bcftools × 6, jacusa2 × 1]
    → update_alu → individual_analysis → reanalysis_multiple → multiple_analysis
```

## Total Rule Count

- 3 preprocessing rules (trim_reads, star_mapping, mark_duplicates)
- 6 tool rules (reditools, sprint, bcftools, red_ml, add_md_tag, jacusa2)
- 5 downstream rules (run_downstream_parsers, update_alu, individual_analysis, reanalysis_multiple, multiple_analysis)
- **Total: 14 rules** — all need `container:`, `log:`, and `resources:`
