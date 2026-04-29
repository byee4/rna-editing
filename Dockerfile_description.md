Based on the technical requirements, languages, and dependencies detailed in the sources, the following Dockerfile templates can be generated for the primary RNA editing tools.
1. REDItools / REDItools2
REDItools requires Python 2.7 and the pysam module (version ≥ 0.15.2)
. REDItools2 (HPC-REDItools) further requires MPI implementations and mpi4py for parallelization
.
# Base image with Python 2.7 as required by REDItools [2]
FROM python:2.7-slim

# Install system dependencies: SAMtools, tabix, and MPI for REDItools2 [1, 2, 4, 6]
RUN apt-get update && apt-get install -y \
    samtools \
    tabix \
    libopenmpi-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install mandatory and optional Python modules [1, 2, 6]
RUN pip install pysam==0.15.2 \
    fisher==0.1.4 \
    mpi4py \
    numpy \
    scipy

# Clone the repository [7]
RUN git clone https://github.com/BioinfoUNIBA/REDItools.git /opt/reditools

# Set working directory to the scripts folder [8]
WORKDIR /opt/reditools/main
2. JACUSA2
JACUSA2 is a Java framework that requires Java v17 and Maven 3.0+ for compilation
. It also benefits from the JACUSA2helper R package for downstream analysis
.
# Build stage using Maven and Java 17 [10]
FROM maven:3.8-openjdk-17 AS build
RUN git clone https://github.com/dieterich-lab/JACUSA2.git /app
WORKDIR /app
RUN mvn package

# Final stage
FROM openjdk:17-slim
COPY --from=build /app/target/JACUSA2-*.jar /opt/jacusa2.jar

# Install SAMtools for BAM processing and MD tag population [13]
RUN apt-get update && apt-get install -y samtools && rm -rf /var/lib/apt/lists/*

# Note: JACUSA2helper R package would typically be installed in a separate R environment [12].
ENTRYPOINT ["java", "-jar", "/opt/jacusa2.jar"]
3. SPRINT
SPRINT is highly specific about its dependencies, requiring Python 2.7, SAMtools v1.2, and BWA v0.7.12
.
# SPRINT requires Python 2.7 and Unix [14]
FROM python:2.7-slim

# Install specific versions of SAMtools and BWA as mandated by the tool [14]
# Note: Specific binary downloads or compilations for these older versions are required.
RUN apt-get update && apt-get install -y \
    gcc \
    make \
    libncurses5-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install BWA v0.7.12 and SAMtools v1.2 [14]
# (Technical detail: These would be compiled from source or added via specific archives)

# Install SPRINT via setup.py [15]
RUN git clone https://github.com/jumphone/SPRINT.git /opt/sprint
WORKDIR /opt/sprint
RUN python setup.py install
4. LoDEI
LoDEI is a Python-based tool (99.7% of the repository) designed for Linux environments (tested on Ubuntu 22.04)
.
# Based on the LoDEI system requirements [16]
FROM python:3.9-slim

# Install required alignment and QC tools [18]
RUN apt-get update && apt-get install -y \
    fastqc \
    multiqc \
    cutadapt \
    star \
    samtools \
    && rm -rf /var/lib/apt/lists/*

# Install LoDEI [16, 17]
RUN pip install lodei

# LoDEI find command is the primary entry point [19]
ENTRYPOINT ["lodei", "find"]
5. RED (RNA Editing Detector)
RED is a Java-MySQL desktop application that also utilizes R for statistical analysis
. It requires Java 1.6.0_43+, MySQL 5.1.73+, and R 3.0.1+
.
# RED requires Java, MySQL, and R [21, 22]
FROM openjdk:8-jre-slim

# Install R and MySQL client [21, 23]
RUN apt-get update && apt-get install -y \
    r-base \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Download RED from SourceForge or GitHub [24, 25]
# (Technical detail: Binary would be placed in /opt/red)

# Note: This tool requires a running MySQL database to connect via JDBC [23].
ENTRYPOINT ["java", "-jar", "/opt/red/RED.jar"]
6. SAILOR
SAILOR is a Python-based tool geared toward C. elegans that is provided as a Singularity container or a CWL workflow
.
# SAILOR uses Python and variant callers [28, 29]
FROM python:3.8-slim

# Install Samtools and BCFtools as required for the mpileup step [28]
RUN apt-get update && apt-get install -y \
    samtools=1.3.1 \
    bcftools=1.2.1 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/yeo-lab/sailor.git /opt/sailor
WORKDIR /opt/sailor
# Note: SAILOR allows specifyng custom filtering criteria via command line [30].
Note on deprecated tools: Dockerfiles are not provided for tools such as RNAEditor or RDDpred as they are noted in the sources for having low compatibility with modern systems, requiring significant downgrades to obsolete versions of GATK (v3.7) or Java (v8), and are generally considered unmaintained