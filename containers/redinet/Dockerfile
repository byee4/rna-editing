FROM python:3.9-slim

LABEL org.opencontainers.image.title="REDInet"
LABEL org.opencontainers.image.description="REDInet package checkout with a stable wrapper for classifying REDItools-derived editing tables."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        samtools \
        tabix \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir \
        numpy==1.26.4 \
        pandas==2.2.2 \
        pysam==0.22.1 \
        scikit-learn==1.4.2 \
        tqdm==4.66.2 \
        tensorflow-cpu==2.14.0

RUN git clone --depth 1 https://github.com/BioinfoUNIBA/REDInet.git /opt/redinet

COPY redinet_classify /usr/local/bin/redinet_classify
COPY validate.sh /usr/local/bin/validate-redinet
RUN chmod +x /usr/local/bin/redinet_classify /usr/local/bin/validate-redinet

WORKDIR /opt/redinet
CMD ["validate-redinet"]
