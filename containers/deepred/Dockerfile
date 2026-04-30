FROM python:3.8-slim

LABEL org.opencontainers.image.title="DeepRed wrapper"
LABEL org.opencontainers.image.description="Runtime scaffold for DeepRed RNA editing prediction; upstream source/model artifacts must be supplied before production use."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir numpy pandas scikit-learn

COPY deepred_predict /usr/local/bin/deepred_predict
COPY validate.sh /usr/local/bin/validate-deepred
RUN chmod +x /usr/local/bin/deepred_predict /usr/local/bin/validate-deepred

WORKDIR /work
CMD ["validate-deepred"]
