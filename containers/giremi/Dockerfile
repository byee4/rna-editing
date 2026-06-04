# GIREMI ships a PRECOMPILED 64-bit binary (`giremi`, ~164 KB) plus `giremi.r`
# (the GLM/MI R step the binary shells out to) and `mark_snp.py`. There is no source
# or Makefile in the repo, so this image is a *runtime-compatibility* build, not a compile:
# the legacy binary is dynamically linked against htslib's `libhts.so.1` soname, which
# htslib shipped through v1.9 (v1.10+ bumped the soname). We therefore build htslib 1.9
# (and a matching samtools 1.9 for `faidx`) from source to provide `libhts.so.1`, and add
# R for the GLM step and Python for `mark_snp.py`.
#
# Reference: https://github.com/zhqingit/giremi
# Usage (verified against README):
#   giremi -f ref.fa -l snv.list -o out [-m min_cov] [-p paired] [-s strand] in.bam
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="GIREMI"
LABEL org.opencontainers.image.description="GIREMI (precompiled binary + giremi.r + mark_snp.py) for genome-independent A-to-I editing identification by mutual information. Reference: zhqingit/giremi."

ENV DEBIAN_FRONTEND=noninteractive \
    HTSLIB_VERSION=1.9 \
    SAMTOOLS_VERSION=1.9 \
    PATH="/opt/giremi:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libbz2-dev \
        libcurl4-openssl-dev \
        liblzma-dev \
        libncurses5-dev \
        libssl-dev \
        python3 \
        r-base-core \
        wget \
        zlib1g-dev \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

# htslib 1.9 — provides libhts.so.1, the soname the legacy giremi binary requires.
RUN wget -q "https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2" \
    && tar -xjf "htslib-${HTSLIB_VERSION}.tar.bz2" \
    && cd "htslib-${HTSLIB_VERSION}" \
    && ./configure && make -j"$(nproc)" && make install \
    && cd .. && rm -rf "htslib-${HTSLIB_VERSION}" "htslib-${HTSLIB_VERSION}.tar.bz2" \
    && ldconfig

# samtools 1.9 — for `samtools faidx` (GIREMI needs the reference .fai). Linked to the
# htslib 1.9 above so the whole image is one consistent htslib generation.
RUN wget -q "https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2" \
    && tar -xjf "samtools-${SAMTOOLS_VERSION}.tar.bz2" \
    && cd "samtools-${SAMTOOLS_VERSION}" \
    && ./configure --with-htslib=system && make -j"$(nproc)" && make install \
    && cd .. && rm -rf "samtools-${SAMTOOLS_VERSION}" "samtools-${SAMTOOLS_VERSION}.tar.bz2"

# GIREMI checkout: the binary, the R script it invokes, and the dbSNP-marking helper.
# Keep them together in /opt/giremi (on PATH) because the binary locates giremi.r relative
# to its own directory.
RUN git clone --depth 1 https://github.com/zhqingit/giremi.git /opt/giremi \
    && chmod +x /opt/giremi/giremi \
    && test -f /opt/giremi/giremi.r \
    && test -f /opt/giremi/mark_snp.py

COPY validate.sh /usr/local/bin/validate-giremi
RUN chmod +x /usr/local/bin/validate-giremi

WORKDIR /work
CMD ["validate-giremi"]
