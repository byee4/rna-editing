FROM quay.io/biocontainers/lodei:1.0.0--pyh7e72e81_0 AS lodei

FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="LoDEI"
LABEL org.opencontainers.image.description="LoDEI from Bioconda plus common FASTQ/BAM preprocessing and QC tools."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        multiqc \
        cutadapt \
        fastqc \
        rna-star \
        samtools \
    && rm -rf /var/lib/apt/lists/*

COPY --from=lodei /usr/local/bin /usr/local/bin
COPY --from=lodei /usr/local/lib /usr/local/lib
COPY --from=lodei /usr/local/share /usr/local/share
COPY --from=lodei /usr/local/ssl /usr/local/ssl

COPY validate.sh /usr/local/bin/validate-lodei
RUN chmod +x /usr/local/bin/validate-lodei

WORKDIR /work
ENTRYPOINT ["lodei"]
CMD ["--help"]
