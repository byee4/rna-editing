FROM ubuntu:22.04

LABEL org.opencontainers.image.title="STAR + SAMtools"
LABEL org.opencontainers.image.description="STAR 2.7.x aligner and SAMtools for RNA-seq alignment in the Morales_et_al pipeline."

ENV DEBIAN_FRONTEND=noninteractive \
    STAR_VERSION=2.7.11a \
    PATH="/opt/star/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        samtools \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/star/bin \
    && wget -qO /tmp/star.tar.gz "https://github.com/alexdobin/STAR/archive/refs/tags/${STAR_VERSION}.tar.gz" \
    && tar -xzf /tmp/star.tar.gz -C /tmp \
    && cp "/tmp/STAR-${STAR_VERSION}/bin/Linux_x86_64_static/STAR" /opt/star/bin/STAR \
    && chmod +x /opt/star/bin/STAR \
    && rm -rf /tmp/star.tar.gz "/tmp/STAR-${STAR_VERSION}"

COPY validate.sh /usr/local/bin/validate-star
RUN chmod +x /usr/local/bin/validate-star

WORKDIR /work
CMD ["validate-star"]
