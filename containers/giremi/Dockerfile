# GIREMI ships a PRECOMPILED 64-bit binary (`giremi`, ~164 KB, built GCC 5.4 / Ubuntu
# 16.04, Feb 2016) plus `giremi.r` (the GLM/MI R step the binary shells out to) and
# `mark_snp.py`. There is no source or Makefile in the repo, so we cannot recompile it
# and must instead supply the htslib it was built against.
#
# IMPORTANT — htslib version: the binary links htslib's `libhts.so.1` soname. That soname
# was kept from htslib ~1.0 through 1.9, but the ABI (pileup internals, struct layouts)
# was NOT stable across those releases. Building htslib 1.9 satisfies the *soname* yet the
# 2016 binary segfaults the moment it enters mpileup, because its compiled-in struct
# offsets no longer match. We therefore pin htslib to **1.3** (Dec 2015, giremi's build
# era), which is ABI-compatible with the binary and runs it through to "Analysis DONE!".
# (Verified empirically: 1.9 -> SIGSEGV in mpileup; 1.3 -> completes.)
#
# samtools is NOT built from source: the giremi rule receives the reference .fai as a
# pipeline input, so faidx is never run here. The apt `samtools` (its own libhts.so.3,
# a different soname) coexists with htslib 1.3's libhts.so.1 without conflict and only
# serves validate.sh's `samtools --version` smoke test.
#
# Reference: https://github.com/zhqingit/giremi
# Usage (verified against README):
#   giremi -f ref.fa -l snv.list -o out [-m min_cov] [-p paired] [-s strand] in.bam
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="GIREMI"
LABEL org.opencontainers.image.description="GIREMI (precompiled binary + giremi.r + mark_snp.py) for genome-independent A-to-I editing identification by mutual information. Reference: zhqingit/giremi."

ENV DEBIAN_FRONTEND=noninteractive \
    HTSLIB_VERSION=1.3 \
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
        r-cran-ggplot2 \
        samtools \
        wget \
        zlib1g-dev \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

# htslib 1.3 — provides the ABI-correct libhts.so.1 the legacy giremi binary needs (see
# the header note; 1.9 has the same soname but a mismatched ABI that segfaults in mpileup).
RUN wget -q "https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2" \
    && tar -xjf "htslib-${HTSLIB_VERSION}.tar.bz2" \
    && cd "htslib-${HTSLIB_VERSION}" \
    && ./configure && make -j"$(nproc)" && make install \
    && cd .. && rm -rf "htslib-${HTSLIB_VERSION}" "htslib-${HTSLIB_VERSION}.tar.bz2" \
    && ldconfig

# GIREMI checkout: the binary, the R script it invokes, and the dbSNP-marking helper.
# Keep them together in /opt/giremi (on PATH).
#
# giremi.r patch: the binary writes a TAB-separated table whose `type` column is empty for
# zero-coverage sites, then reads it back with R `read.table(header=T)` using the DEFAULT
# whitespace separator — which collapses the empty field and aborts with "line N did not
# have 24 elements". Pin the read to sep="\t" so empty fields are preserved.
RUN git clone --depth 1 https://github.com/zhqingit/giremi.git /opt/giremi \
    && chmod +x /opt/giremi/giremi \
    && test -f /opt/giremi/giremi.r \
    && test -f /opt/giremi/mark_snp.py \
    && sed -i 's/read.table(file=finput,header=T,comment.char="")/read.table(file=finput,header=T,sep="\\t",comment.char="")/' /opt/giremi/giremi.r \
    && grep -q 'sep="\\t"' /opt/giremi/giremi.r

COPY validate.sh /usr/local/bin/validate-giremi
RUN chmod +x /usr/local/bin/validate-giremi

WORKDIR /work
CMD ["validate-giremi"]
