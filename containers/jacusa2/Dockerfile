FROM condaforge/miniforge3:latest

LABEL org.opencontainers.image.title="JACUSA2"
LABEL org.opencontainers.image.description="Conda runtime with JACUSA2, OpenJDK 17, and SAMtools for RNA editing and variant comparison workflows."

USER root

RUN mamba install -y -n base -c conda-forge -c bioconda \
        openjdk=17 \
        jacusa2=2.1.16 \
        samtools \
    && mamba clean -a -y \
    && mkdir -p /opt/jacusa2 \
    && find /opt/conda/share -type f -name "JACUSA*.jar" -print -quit \
        | xargs -r -I{} cp {} /opt/jacusa2/jacusa2.jar \
    && test -s /opt/jacusa2/jacusa2.jar

ENV PATH="/opt/conda/bin:${PATH}"

COPY validate.sh /usr/local/bin/validate-jacusa2
RUN chmod +x /usr/local/bin/validate-jacusa2

WORKDIR /work
ENTRYPOINT ["java", "-jar", "/opt/jacusa2/jacusa2.jar"]
CMD ["--help"]
