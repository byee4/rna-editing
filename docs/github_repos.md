There exists numerous mentions of GitHub repositories for RNA editing tools, preprocessing utilities, and benchmarking resources. The following is a comprehensive list of these GitHub mentions:

### Primary RNA Editing Detection Tools
*   **REDItools / REDItools2 (HPC-REDItools)**: The core suite and its parallelized version are hosted at [https://github.com/BioinfoUNIBA/REDItools](https://github.com/BioinfoUNIBA/REDItools) and [https://github.com/BioinfoUNIBA/REDItools2](https://github.com/BioinfoUNIBA/REDItools2).
*   **JACUSA / JACUSA2**: Tools for replicate-aware variant calling are available at [https://github.com/dieterich-lab/JACUSA](https://github.com/dieterich-lab/JACUSA) and [https://github.com/dieterich-lab/JACUSA2](https://github.com/dieterich-lab/JACUSA2).
*   **SPRINT**: An SNP-free toolkit for identifying editing sites is located at [https://github.com/jumphone/SPRINT](https://github.com/jumphone/SPRINT).
*   **GIREMI / L-GIREMI**: Mutual-information-based tools for short and long reads are at [https://github.com/zhqingit/giremi](https://github.com/zhqingit/giremi) and [https://github.com/gxiaolab/L-GIREMI](https://github.com/gxiaolab/L-GIREMI).
*   **RES-Scanner**: A package for genome-wide identification using matched DNA-RNA data is at [https://github.com/ZhangLabSZ/RES-Scanner](https://github.com/ZhangLabSZ/RES-Scanner).
*   **RESIC**: A graph-alignment-based tool for classifying regular and hyper-edited sites is available at [https://github.com/Lammlab/Resic](https://github.com/Lammlab/Resic).
*   **RED (REDetector)**: A Java-MySQL software for identifying sites with GUI support is at [https://github.com/REDetector/RED](https://github.com/REDetector/RED).
*   **LoDEI**: A tool for detecting differential RNA editing regions is at [https://github.com/rna-editing1/lodei](https://github.com/rna-editing1/lodei).
*   **SAILOR**: Used for identifying editing locations, particularly in *C. elegans*, at [https://github.com/YeoLab/sailor](https://github.com/YeoLab/sailor).
*   **REDITs**: A package providing beta-binomial models for differential editing tests is at [https://github.com/gxiaolab/REDITs](https://github.com/gxiaolab/REDITs).

### Machine Learning and Deep Learning Tools
*   **REDInet**: A Temporal Convolutional Network classifier is hosted at [https://github.com/BioinfoUNIBA/REDInet](https://github.com/BioinfoUNIBA/REDInet).
*   **RED-ML**: A logistic-regression-based classifier is available at [https://github.com/BGIRED/RED-ML](https://github.com/BGIRED/RED-ML).
*   **DeepRed**: The first deep-learning RNA-editing predictor is at [https://github.com/wenjiegroup/DeepRed](https://github.com/wenjiegroup/DeepRed).
*   **EditPredict**: A sequence-only CNN model is at [https://github.com/wjd198605/EditPredict](https://github.com/wjd198605/EditPredict).
*   **DEMINING / DeepDDR**: Tools for separating RNA edits from DNA mutations are at [https://github.com/YangLab/DEMINING](https://github.com/YangLab/DEMINING).

### Nanopore and Long-Read Specialized Tools
*   **Dinopore**: Site-level inosine caller for Nanopore data at [https://github.com/darelab2014/Dinopore](https://github.com/darelab2014/Dinopore).
*   **RNANO**: Predicts multiple modifications from direct RNA sequencing at [https://github.com/abhhba999/RNANO](https://github.com/abhhba999/RNANO).
*   **ModiDeC**: A multi-RNA modification classifier at [https://github.com/mem3nto0/ModiDeC-RNA-modification-classifier](https://github.com/mem3nto0/ModiDeC-RNA-modification-classifier).
*   **Dorado**: Official ONT basecaller with modification support at [https://github.com/nanoporetech/dorado/](https://github.com/nanoporetech/dorado/).
*   **CHEUI**: For concurrent identification of m6A and m5C at [https://github.com/comprna/CHEUI](https://github.com/comprna/CHEUI).
*   **TandemMod**: Transferable deep learning for multiple modification types at [https://github.com/yulab2021/TandemMod](https://github.com/yulab2021/TandemMod).
*   **NanoSim**: A Nanopore read simulator at [https://github.com/bcgsc/NanoSim](https://github.com/bcgsc/NanoSim).

### Preprocessing, Alignment, and Quality Control
*   **FastQC**: Standard quality control tool at [https://github.com/s-andrews/FastQC](https://github.com/s-andrews/FastQC).
*   **TrimGalore**: A wrapper for quality and adapter trimming at [https://github.com/FelixKrueger/TrimGalore](https://github.com/FelixKrueger/TrimGalore).
*   **RASER**: A specialized splice-aware aligner for RNA at [https://github.com/jaegyoonahn/RASER](https://github.com/jaegyoonahn/RASER).
*   **pysam**: Python wrapper for SAMtools at [https://github.com/pysam-developers/pysam](https://github.com/pysam-developers/pysam).
*   **pblat**: Parallelized version of BLAT at [https://github.com/icebert/pblat](https://github.com/icebert/pblat).
*   **Sniffles2**: For structural variant detection at [https://github.com/fritzsedlazeck/Sniffles](https://github.com/fritzsedlazeck/Sniffles).

### Benchmarking and Resource Repositories
*   **RNA Editing Benchmark (2023)**: Code and options for benchmarking major detection tools are at [https://github.com/davidrm-bio/Benchmark-of-RNA-Editing-Detection-Tools](https://github.com/davidrm-bio/Benchmark-of-RNA-Editing-Detection-Tools).
*   **GTEx edQTL Pipeline**: For multiomics integration at [https://github.com/vargasliqin/GTEx_edQTL](https://github.com/vargasliqin/GTEx_edQTL).
*   **PacBio GitHub**: A general repository for PacBio-developed HiFi tools is at [https://github.com/PacificBiosciences](https://github.com/PacificBiosciences).
*   **Monocle 3**: Single-cell analysis documentation at [https://cole-trapnell-lab.github.io/monocle3/](https://cole-trapnell-lab.github.io/monocle3/).

### General Detection & Comprehensive Profiling
*   **BioinfoUNIBA/REDItools**: This is a pure-Python suite for genomic-scale RNA editing analysis using heuristic filters and statistical tests. It includes three main scripts: `REDItoolDnaRna.py` for matched DNA-RNA comparisons, `REDItoolKnown.py` for interrogating known editing positions, and `REDItoolDenovo.py` for discovery from RNA-seq data alone. The package implements empirical filters for base quality, mapping quality, and homopolymeric regions to minimize technical artifacts.
*   **BioinfoUNIBA/REDItools2 (HPC-REDItools)**: An MPI-parallelized re-engineering of the original REDItools suite. It is designed to scale near-linearly with available CPU cores, making it suitable for processing massive datasets like GTEx or TCGA. It employs a master/slave layout where a master process dispatches genomic intervals to slave processes for high-throughput analysis.
*   **dieterich-lab/JACUSA**: A Java-based variant caller designed for replicate-aware comparisons of matched sequencing samples. It utilizes Dirichlet-multinomial distributions to model allele counts and a likelihood-ratio test to produce per-site scores. It is highly optimized for identifying RNA-DNA and RNA-RNA substitution differences.
*   **dieterich-lab/JACUSA2**: This successor framework captures more complex read signatures, including insertions, deletions, and read truncations. It adds support for Oxford Nanopore data and features a approximately three-fold performance increase over the original tool. It includes experimental methods for identifying reverse transcriptase-induced arrest events.
*   **jumphone/SPRINT**: An SNP-free toolkit that identifies editing and hyper-editing sites by clustering SNV duplets based on their genomic distance. It utilizes internal BWA mapping and rescues hyper-edited reads by re-aligning unmapped reads after A-to-G base masking. SPRINT does not require matched DNA data or reference to SNP databases.
*   **REDetector/RED**: A Java-MySQL software package that provides a graphical user interface for the identification and visualization of editing sites. It integrates multiple rule-based and statistical filters and utilizes a MySQL backend for efficient high-throughput data storage and querying. Potential editing sites can be visualized at both the genome and individual site levels.
*   **ZhangLabSZ/RES-Scanner**: A Perl-based pipeline for genome-wide identification and annotation of editing sites using matched DNA and RNA data. It offers multiple statistical models for genotype calling, including Bayesian and binomial models.

### Machine Learning & Deep Learning Tools
*   **BioinfoUNIBA/REDInet**: A Temporal Convolutional Network (TCN) classifier designed to classify editing events using frequency window matrices. It is trained on millions of examples from REDIportal and does not require matched genomic data.
*   **YangLab/DEMINING**: A CNN-based framework developed to distinguish genuine RNA editing events from expressed DNA mutations using RNA-seq data alone. It encodes sites by the co-occurrence frequency of mutations with their sequence context.
*   **wenjiegroup/DeepRed**: One of the first deep-learning predictors for RNA editing, utilizing a CNN/ensemble hybrid model trained on flanking genomic sequences.
*   **wjd198605/EditPredict**: A sequence-only CNN model that supports multiple species and predicts editing sites without the need for RNA-seq data.

### Long-Read & Nanopore Specialized Tools
*   **darelab2014/Dinopore**: A deep-learning model for site-level detection of inosine from native RNA Nanopore sequencing. It exploits characteristic ionic-current deviations and base-calling errors to identify modifications.
*   **Chen et al./DeepEdit**: A neural network-based tool for single-molecule, phased detection of A-to-I editing from Nanopore current. Unlike site-level callers, it can phase multiple editing events occurring within the same RNA molecule.
*   **yulab2021/TandemMod**: A transferable deep-learning framework designed to simultaneously detect multiple RNA modifications, including inosine, m6A, and m5C, from direct-RNA data.
*   **gxiaolab/L-GIREMI**: An adaptation of the mutual-information framework specifically tuned for identified editing in PacBio long-read sequences.
*   **nanoporetech/dorado**: The official Oxford Nanopore basecaller that includes support for modified base calling, particularly for m6A and pseudouridine.

### Single-Cell & Differential Editing Tools
*   **rna-editing1/lodei**: A Python-based tool that uses a sliding-window approach to detect regional differential RNA editing between sample sets. It calculates a local differential editing index (LoDEI) and uses non-canonical mismatches as empirical noise to derive q-values.
*   **gxiaolab/scAllele**: A dedicated variant caller for single-cell data that refined alignments through local read reassembly. It preserves molecule-of-origin information and scores candidates using a GLM to reduce false indel detection.
*   **yeo-lab/sailor**: A Python-based pipeline for identifying high-confidence editing locations, packaged as a Singularity container or CWL workflow. It utilizes an empirical Bayesian scoring system to distinguish signal from noise, particularly in neural datasets.
*   **YeoLab/FLARE**: A Snakemake pipeline that identifies statistically enriched editing clusters from SAILOR or JACUSA2 output using Poisson modeling.
*   **gxiaolab/REDITs**: A package providing beta-binomial models for statistically robust differential editing tests.

### Preprocessing & Infrastructure
*   **s-andrews/FastQC**: The industry standard Java-based tool for evaluating the quality of raw sequencing data in FASTQ or BAM formats.
*   **icebert/pblat**: A parallelized version of the BLAT tool for high-speed sequence alignment. It is frequently used in editing pipelines to identify and rescue reads that map to multiple genomic locations.
*   **fritzsedlazeck/Sniffles2**: A structural variant detector optimized for long-read data, often used to filter out complex genomic variations.
*   **BioinfoUNIBA/QEdit**: A implementation of the Recoding Editing Index (REI) for quantifying ADAR2 activity at specific recoding sites.