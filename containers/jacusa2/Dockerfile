FROM condaforge/miniforge3:latest

LABEL org.opencontainers.image.title="JACUSA2"
LABEL org.opencontainers.image.description="Conda runtime with the self-contained JACUSA2 release JAR, OpenJDK 17, and SAMtools for RNA editing and variant comparison workflows."

USER root

RUN mamba install -y -n base -c conda-forge -c bioconda \
        openjdk=17 \
        curl \
        samtools \
    && mamba clean -a -y \
    && mkdir -p /opt/jacusa2 \
    && curl -fL \
        "https://github.com/dieterich-lab/JACUSA2/releases/download/v2.1.16/JACUSA_v2.1.16.jar" \
        -o /opt/jacusa2/jacusa2.jar \
    && echo "bf78cffe7e67c87b4f7ef2bef809c1fd0cab903edec8b32d6850e4827a587df6  /opt/jacusa2/jacusa2.jar" \
        | sha256sum -c - \
    && test -s /opt/jacusa2/jacusa2.jar

ENV PATH="/opt/conda/bin:${PATH}"

COPY validate.sh /usr/local/bin/validate-jacusa2
RUN chmod +x /usr/local/bin/validate-jacusa2

WORKDIR /work
ENTRYPOINT ["java", "-jar", "/opt/jacusa2/jacusa2.jar"]
CMD ["--help"]
