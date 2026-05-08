FROM eclipse-temurin:17-jre-jammy

LABEL org.opencontainers.image.title="Picard"
LABEL org.opencontainers.image.description="Picard command-line tools for duplicate marking and BAM metadata cleanup."

ENV DEBIAN_FRONTEND=noninteractive \
    PICARD_VERSION=3.4.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        samtools \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/picard \
    && wget -qO /opt/picard/picard.jar "https://github.com/broadinstitute/picard/releases/download/${PICARD_VERSION}/picard.jar" \
    && test -s /opt/picard/picard.jar

COPY picard /usr/local/bin/picard
COPY validate.sh /usr/local/bin/validate-picard
RUN chmod +x /usr/local/bin/picard /usr/local/bin/validate-picard

WORKDIR /work
CMD ["validate-picard"]
