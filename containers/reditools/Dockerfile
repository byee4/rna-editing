FROM python:2.7-buster

LABEL org.opencontainers.image.title="REDItools and REDItools2"
LABEL org.opencontainers.image.description="Python 2.7, pysam, MPI, and REDItools scripts for RNA editing analysis."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/reditools/main:/opt/reditools2/src/cineca:${PATH}"

RUN sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g; s|security.debian.org/debian-security|archive.debian.org/debian-security|g; s|deb.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list \
    && sed -i '/buster-updates/d' /etc/apt/sources.list \
    && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99archive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libbz2-dev \
        liblzma-dev \
        libopenmpi-dev \
        libssl-dev \
        libz-dev \
        openmpi-bin \
        samtools \
        tabix \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir --upgrade "pip<21" "setuptools<45" wheel \
    && python -m pip install --no-cache-dir "numpy==1.16.6" \
    && python -m pip install --no-cache-dir \
        "pysam==0.15.4" \
        "fisher==0.1.4" \
        "mpi4py==3.0.3"

RUN git clone --depth 1 https://github.com/BioinfoUNIBA/REDItools.git /opt/reditools \
    && git clone --depth 1 https://github.com/BioinfoUNIBA/REDItools2.git /opt/reditools2

COPY validate.sh /usr/local/bin/validate-reditools
RUN chmod +x /usr/local/bin/validate-reditools

WORKDIR /opt/reditools/main
CMD ["validate-reditools"]
