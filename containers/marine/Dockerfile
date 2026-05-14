FROM continuumio/miniconda3:23.10.0-1

LABEL org.opencontainers.image.title="MARINE"
LABEL org.opencontainers.image.description="MARINE 1.0.2 — bulk and single-cell A-to-I RNA editing detection."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/conda/bin:/opt/marine/bin/MARINE:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        samtools \
    && rm -rf /var/lib/apt/lists/*

# Clone MARINE at the pinned release tag
RUN git clone --depth 1 --branch 1.0.2 https://github.com/YeoLab/MARINE.git /opt/marine \
    || git clone --depth 1 https://github.com/YeoLab/MARINE.git /opt/marine

# Create a dedicated conda environment from the project's own spec
RUN conda env create -n marine -f /opt/marine/bin/MARINE/marine_environment.yml \
    && conda clean -afy

# Ensure marine.py is executable
RUN chmod +x /opt/marine/bin/MARINE/marine.py

COPY validate.sh /usr/local/bin/validate-marine
RUN chmod +x /usr/local/bin/validate-marine

WORKDIR /opt/marine/bin/MARINE
CMD ["validate-marine"]
