# Explicitly use docker.io and the 'jammy' (Ubuntu 22.04) tag
FROM docker.io/mambaorg/micromamba:jammy

LABEL org.opencontainers.image.title="HISAT2 + SAMtools (Mamba)"
LABEL org.opencontainers.image.description="HISAT2 and SAMtools installed via Mamba for RNA-seq alignment."

# Micromamba setup
ENV HISAT2_VERSION=2.2.1 \
    SAMTOOLS_VERSION=1.19 \
    PATH="/opt/conda/bin:${PATH}"

# Install tools
RUN micromamba install -y -n base -c bioconda -c conda-forge \
        hisat2=${HISAT2_VERSION} \
        samtools=${SAMTOOLS_VERSION} \
    && micromamba clean --all --yes

USER root

# Ensure the bin directory exists for our scripts
RUN mkdir -p /usr/local/bin

COPY validate.sh /usr/local/bin/validate-hisat2
RUN chmod +x /usr/local/bin/validate-hisat2

WORKDIR /work
CMD ["validate-hisat2"]
