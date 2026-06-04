FROM continuumio/miniconda3:23.10.0-1

LABEL org.opencontainers.image.title="MARINE"
LABEL org.opencontainers.image.description="MARINE (main) — bulk and single-cell A-to-I RNA editing detection."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/conda/envs/marine/bin:/opt/conda/bin:/opt/marine:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        samtools \
    && rm -rf /var/lib/apt/lists/*

# Clone MARINE main branch
RUN git clone --depth 1 https://github.com/yeolab/marine.git /opt/marine

# Create a dedicated conda environment from the project's own spec
RUN conda env create -n marine -f /opt/marine/marine_environment2.yaml \
    && conda clean -afy

# Ensure marine.py is executable
RUN chmod +x /opt/marine/marine.py

COPY validate.sh /usr/local/bin/validate-marine
RUN chmod +x /usr/local/bin/validate-marine

WORKDIR /opt/marine
CMD ["validate-marine"]
