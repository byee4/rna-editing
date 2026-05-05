FROM python:3.8-slim

LABEL org.opencontainers.image.title="EditPredict"
LABEL org.opencontainers.image.description="EditPredict source checkout with a stable Snakemake wrapper for reference/position scoring."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir biopython h5py keras numpy pandas tensorflow-cpu

RUN git clone --depth 1 https://github.com/wjd198605/EditPredict.git /opt/editpredict

COPY fix_upstream.py /tmp/fix_editpredict_upstream.py
RUN python /tmp/fix_editpredict_upstream.py \
    && rm -f /tmp/fix_editpredict_upstream.py

COPY editpredict_score /usr/local/bin/editpredict_score
COPY validate.sh /usr/local/bin/validate-editpredict
RUN chmod +x /usr/local/bin/editpredict_score /usr/local/bin/validate-editpredict

WORKDIR /opt/editpredict
CMD ["validate-editpredict"]
