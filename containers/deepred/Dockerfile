FROM condaforge/miniforge3:latest

LABEL org.opencontainers.image.title="DeepRed wrapper"
LABEL org.opencontainers.image.description="Mamba-managed runtime scaffold for DeepRed RNA editing prediction; upstream MATLAB/source/model artifacts must be supplied before production use."

ENV PYTHONUNBUFFERED=1
ENV LD_LIBRARY_PATH="/opt/conda/lib"

RUN mamba install -y -n base -c conda-forge \
        python=3.11 \
        perl \
        numpy \
        pandas \
        scikit-learn \
        xorg-libxt \
        xorg-libxext \
        xorg-libxmu \
        xorg-libxpm \
    && mamba clean -a -y

COPY deepred_predict /usr/local/bin/deepred_predict
COPY validate.sh /usr/local/bin/validate-deepred
RUN chmod +x /usr/local/bin/deepred_predict /usr/local/bin/validate-deepred

WORKDIR /work
CMD ["validate-deepred"]
