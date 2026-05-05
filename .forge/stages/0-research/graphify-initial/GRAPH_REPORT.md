# Graph Report - /tscc/projects/ps-yeolab3/bay001/codebase/rna-editing  (2026-05-05)

## Corpus Check
- 167 files · ~70,705 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 260 nodes · 254 edges · 92 communities (79 shown, 13 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 21 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Container Image Registry|Container Image Registry]]
- [[_COMMUNITY_ML RNA Editing Tools|ML RNA Editing Tools]]
- [[_COMMUNITY_REDInet and REDItools|REDInet and REDItools]]
- [[_COMMUNITY_FASTQ Utility Scripts|FASTQ Utility Scripts]]
- [[_COMMUNITY_Pipeline Orchestration|Pipeline Orchestration]]
- [[_COMMUNITY_Read Alignment and Indexing|Read Alignment and Indexing]]
- [[_COMMUNITY_SPRINT to DeepRED Adapter|SPRINT to DeepRED Adapter]]
- [[_COMMUNITY_DeepRED MATLAB Optimization|DeepRED MATLAB Optimization]]
- [[_COMMUNITY_SPRINT to EditPredict Adapter|SPRINT to EditPredict Adapter]]
- [[_COMMUNITY_Pipeline Tests|Pipeline Tests]]
- [[_COMMUNITY_DeepRED MEX Utilities|DeepRED MEX Utilities]]
- [[_COMMUNITY_DeepRED MATLAB RepMat|DeepRED MATLAB RepMat]]
- [[_COMMUNITY_EditPredict Compatibility Fix|EditPredict Compatibility Fix]]
- [[_COMMUNITY_Beads Workflow Tooling|Beads Workflow Tooling]]
- [[_COMMUNITY_SAILOR Container|SAILOR Container]]
- [[_COMMUNITY_LoDEI Container|LoDEI Container]]
- [[_COMMUNITY_RED Container|RED Container]]
- [[_COMMUNITY_Component 84|Component 84]]
- [[_COMMUNITY_Component 85|Component 85]]
- [[_COMMUNITY_Component 86|Component 86]]
- [[_COMMUNITY_Component 87|Component 87]]
- [[_COMMUNITY_Component 88|Component 88]]
- [[_COMMUNITY_Component 89|Component 89]]
- [[_COMMUNITY_Component 90|Component 90]]
- [[_COMMUNITY_Component 91|Component 91]]

## God Nodes (most connected - your core abstractions)
1. `editing_wgs Full Production Config` - 22 edges
2. `editing Pipeline (pipelines/editing)` - 17 edges
3. `WGS Pipeline (pipelines/WGS)` - 13 edges
4. `DeepRED Deep Learning Predictor` - 11 edges
5. `main()` - 10 edges
6. `editing_wgs Primary Pipeline` - 10 edges
7. `SPRINT RNA Editing Caller` - 10 edges
8. `REDItools v1 Candidate Extractor` - 10 edges
9. `JACUSA2 DNA/RNA Comparison Caller` - 9 edges
10. `REDInet TCN Classifier` - 8 edges

## Surprising Connections (you probably didn't know these)
- `JACUSA2 Tool (Morales et al. config)` --semantically_similar_to--> `JACUSA2 DNA/RNA Comparison Caller`  [INFERRED] [semantically similar]
  pipelines/Morales_et_all/config.yaml → CLAUDE.md
- `SPRINT Tool (Morales et al. config)` --semantically_similar_to--> `SPRINT RNA Editing Caller`  [INFERRED] [semantically similar]
  pipelines/Morales_et_all/config.yaml → CLAUDE.md
- `REDItools2 Tool (Morales et al. config)` --semantically_similar_to--> `REDItools v1 Candidate Extractor`  [INFERRED] [semantically similar]
  pipelines/Morales_et_all/config.yaml → CLAUDE.md
- `GRCh38 Reference (Morales et al. config)` --semantically_similar_to--> `GRCh38 Reference FASTA`  [INFERRED] [semantically similar]
  pipelines/Morales_et_all/config.yaml → CLAUDE.md
- `STAR Aligner (Morales et al. config)` --semantically_similar_to--> `STAR RNA Aligner`  [INFERRED] [semantically similar]
  pipelines/Morales_et_all/config.yaml → CLAUDE.md

## Communities (92 total, 13 thin omitted)

### Community 0 - "Container Image Registry"
Cohesion: 0.08
Nodes (30): deepred.sif (DeepRED container), editpredict.sif (editPredict container), lodei.sif (STAR container image), Picard Duplicate Marking, picard.sif (Picard container), rna_processing.smk Module, STAR RNA Aligner, amd64 Platform Target for TSCC (+22 more)

### Community 1 - "ML RNA Editing Tools"
Cohesion: 0.09
Nodes (27): DeepRED Deep Learning Predictor, editPredict CNN Scoring Tool, JACUSA2 DNA/RNA Comparison Caller, jacusa2.sif (JACUSA2/SAMtools container), rna_editing.smk Module, SPRINT RNA Editing Caller, sprint.sif (SPRINT container), sprint_to_deepred_vcf.py Adapter Script (+19 more)

### Community 2 - "REDInet and REDItools"
Cohesion: 0.1
Nodes (22): REDInet TCN Classifier, redinet.sif (REDInet container), REDItools v1 Candidate Extractor, reditools.sif (REDItools container), Python 2.7 Runtime Requirement, REDItools Docker Container, SPRINT Docker Container, deepred.sif Container (editing pipeline) (+14 more)

### Community 3 - "FASTQ Utility Scripts"
Cohesion: 0.22
Nodes (17): filter_fastq_by_names_paired(), filter_fastq_by_names_single(), GenomicInterval, infer_default_output_prefix(), interval_overlaps(), iter_fastq(), main(), mapped_reads_overlapping_genes() (+9 more)

### Community 4 - "Pipeline Orchestration"
Cohesion: 0.13
Nodes (17): GRCh38 Reference FASTA, editing_wgs Primary Pipeline, Singularity/Apptainer Container Runtime, SLURM Job Scheduler, Snakemake Workflow Engine, TSCC HPC Cluster, editing-wgs-snakemake Conda Environment, snakemake-minimal 9.19.0 (+9 more)

### Community 5 - "Read Alignment and Indexing"
Cohesion: 0.15
Nodes (17): BCFtools Variant Calling, BWA-MEM WGS Aligner, indexing.smk Module, preprocessing.smk Module, SAMtools BAM Processing, editing_wgs Snakefile, wgs_processing.smk Module, wgs.sif (BWA/SAMtools/BCFtools container) (+9 more)

### Community 6 - "SPRINT to DeepRED Adapter"
Cohesion: 0.2
Nodes (9): convert_sprint_res_to_deepred_vcf(), main(), parse_edit_type(), Return REF and ALT bases from a SPRINT edit type token., Write DeepRed chromosome/position/ref/alt rows from SPRINT RES calls., Run the SPRINT-to-DeepRed VCF conversion command., SPRINT one-based end coordinates and edit types become DeepRed rows., Tests for converting SPRINT RES rows into DeepRed candidate SNVs. (+1 more)

### Community 7 - "DeepRED MATLAB Optimization"
Cohesion: 0.46
Nodes (7): absolute(), mexFunction(), mymax(), permute(), permuteCols(), permuteInt(), permuteRows()

### Community 8 - "SPRINT to EditPredict Adapter"
Cohesion: 0.38
Nodes (6): convert_sprint_positions(), main(), normalize_chromosome(), Return the chromosome token format accepted by EditPredict get_seq.py., Write EditPredict chromosome/locus rows from a SPRINT regular RES file., Run the SPRINT-to-EditPredict position conversion command.

### Community 9 - "Pipeline Tests"
Cohesion: 0.4
Nodes (3): EditingWgsDryRunTest, Dry-run tests for all configured editing_wgs sample branches., All sample branches build a DAG, including the shared STAR index.

### Community 11 - "DeepRED MATLAB RepMat"
Cohesion: 1.0
Nodes (3): memrep(), mexFunction(), repmat()

### Community 12 - "EditPredict Compatibility Fix"
Cohesion: 0.83
Nodes (3): main(), patch_edit_predict(), patch_get_seq()

## Knowledge Gaps
- **81 isolated node(s):** `Tests for converting SPRINT RES rows into DeepRed candidate SNVs.`, `SPRINT one-based end coordinates and edit types become DeepRed rows.`, `Dry-run tests for all configured editing_wgs sample branches.`, `All sample branches build a DAG, including the shared STAR index.`, `Return REF and ALT bases from a SPRINT edit type token.` (+76 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `editing_wgs Full Production Config` connect `Container Image Registry` to `ML RNA Editing Tools`, `REDInet and REDItools`, `Read Alignment and Indexing`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **Why does `editing Pipeline (pipelines/editing)` connect `REDInet and REDItools` to `ML RNA Editing Tools`, `Pipeline Orchestration`, `Read Alignment and Indexing`?**
  _High betweenness centrality (0.053) - this node is a cross-community bridge._
- **Why does `editing_wgs Primary Pipeline` connect `Pipeline Orchestration` to `ML RNA Editing Tools`, `REDInet and REDItools`, `Read Alignment and Indexing`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `editing_wgs Full Production Config` (e.g. with `editing_wgs Gene Example Config (APP/GAPDH)` and `editing_wgs Random Example Config`) actually correct?**
  _`editing_wgs Full Production Config` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `WGS Pipeline (pipelines/WGS)` (e.g. with `editing Pipeline (pipelines/editing)` and `editing_wgs Primary Pipeline`) actually correct?**
  _`WGS Pipeline (pipelines/WGS)` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Tests for converting SPRINT RES rows into DeepRed candidate SNVs.`, `SPRINT one-based end coordinates and edit types become DeepRed rows.`, `Dry-run tests for all configured editing_wgs sample branches.` to the rest of the system?**
  _81 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Container Image Registry` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._