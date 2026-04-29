FROM ubuntu:18.04

LABEL org.opencontainers.image.title="SAILOR"
LABEL org.opencontainers.image.description="SAILOR with samtools 1.3.1 and bcftools 1.2 for RNA editing workflows."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/samtools-1.3.1:/opt/bcftools-1.2:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libbz2-dev \
        liblzma-dev \
        libncurses5-dev \
        python \
        python-pip \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget -qO /tmp/samtools-1.3.1.tar.bz2 https://github.com/samtools/samtools/releases/download/1.3.1/samtools-1.3.1.tar.bz2 \
    && tar -xjf /tmp/samtools-1.3.1.tar.bz2 -C /opt \
    && make -C /opt/samtools-1.3.1 \
    && wget -qO /tmp/bcftools-1.2.tar.bz2 https://github.com/samtools/bcftools/releases/download/1.2/bcftools-1.2.tar.bz2 \
    && tar -xjf /tmp/bcftools-1.2.tar.bz2 -C /opt \
    && make -C /opt/bcftools-1.2 \
    && rm -f /tmp/samtools-1.3.1.tar.bz2 /tmp/bcftools-1.2.tar.bz2

RUN git clone --depth 1 https://github.com/YeoLab/sailor.git /opt/sailor \
    && python -m pip install --no-cache-dir --upgrade "pip<21" "setuptools<45" wheel

COPY validate.sh /usr/local/bin/validate-sailor
RUN chmod +x /usr/local/bin/validate-sailor

WORKDIR /opt/sailor
CMD ["validate-sailor"]
