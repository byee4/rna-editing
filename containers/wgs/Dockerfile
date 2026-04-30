FROM ubuntu:22.04

LABEL org.opencontainers.image.title="WGS preprocessing"
LABEL org.opencontainers.image.description="BWA, SAMtools, BCFtools, and tabix for WGS alignment, duplicate marking, MD tag population, coverage, and germline variant calling."

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bcftools \
        bwa \
        ca-certificates \
        samtools \
        tabix \
    && rm -rf /var/lib/apt/lists/*

COPY validate.sh /usr/local/bin/validate-wgs
RUN chmod +x /usr/local/bin/validate-wgs

WORKDIR /work
CMD ["validate-wgs"]
