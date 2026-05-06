FROM python:3.11-slim

LABEL org.opencontainers.image.title="Morales Downstream Analysis"
LABEL org.opencontainers.image.description="Python 3.11 with pandas and numpy for the Benchmark-of-RNA-Editing-Detection-Tools/Downstream/*.py scripts called from the Morales_et_al pipeline."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir \
        "numpy>=1.24,<2.0" \
        "pandas>=2.0,<3.0" \
        "scipy>=1.10,<2.0"

COPY validate.sh /usr/local/bin/validate-morales_downstream
RUN chmod +x /usr/local/bin/validate-morales_downstream

WORKDIR /work
CMD ["validate-morales_downstream"]
