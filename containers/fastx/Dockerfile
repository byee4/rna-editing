FROM condaforge/miniforge3:latest

LABEL org.opencontainers.image.title="FASTX-Toolkit"
LABEL org.opencontainers.image.description="FASTX-Toolkit (fastx_trimmer) installed via bioconda for FASTQ quality trimming in the Morales_et_al pipeline."

ENV PATH="/opt/conda/bin:${PATH}"

RUN mamba install -y -n base -c conda-forge -c bioconda \
        fastx_toolkit \
    && mamba clean -a -y

COPY validate.sh /usr/local/bin/validate-fastx
RUN chmod +x /usr/local/bin/validate-fastx

WORKDIR /work
CMD ["validate-fastx"]
