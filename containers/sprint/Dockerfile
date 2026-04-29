FROM ubuntu:18.04

LABEL org.opencontainers.image.title="SPRINT"
LABEL org.opencontainers.image.description="SPRINT with Python 2.7, BWA 0.7.12, and SAMtools 1.2 for RNA editing detection."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/bwa-0.7.12:/opt/samtools-1.2:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libbz2-dev \
        liblzma-dev \
        libncurses5-dev \
        python \
        python-dev \
        python-pip \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget -qO /tmp/bwa-0.7.12.tar.bz2 https://downloads.sourceforge.net/project/bio-bwa/bwa-0.7.12.tar.bz2 \
    && tar -xjf /tmp/bwa-0.7.12.tar.bz2 -C /opt \
    && make -C /opt/bwa-0.7.12 \
    && wget -qO /tmp/samtools-1.2.tar.bz2 https://github.com/samtools/samtools/releases/download/1.2/samtools-1.2.tar.bz2 \
    && tar -xjf /tmp/samtools-1.2.tar.bz2 -C /opt \
    && make -C /opt/samtools-1.2 \
    && rm -f /tmp/bwa-0.7.12.tar.bz2 /tmp/samtools-1.2.tar.bz2

RUN git clone --depth 1 https://github.com/jumphone/SPRINT.git /opt/sprint \
    && python -m pip install --no-cache-dir --upgrade "pip<21" "setuptools<45" wheel \
    && if [ -f /opt/sprint/setup.py ]; then python /opt/sprint/setup.py install; fi

COPY validate.sh /usr/local/bin/validate-sprint
RUN chmod +x /usr/local/bin/validate-sprint

WORKDIR /opt/sprint
CMD ["validate-sprint"]
