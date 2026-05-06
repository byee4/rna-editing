FROM rocker/r-ver:4.3.2

LABEL org.opencontainers.image.title="RED-ML"
LABEL org.opencontainers.image.description="Perl + R + RED-ML (red_ML.pl) for RNA editing detection by machine learning. Reference: BGIRED/RED-ML."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/red_ml/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        perl \
        wget \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages (RED-ML uses caret + randomForest + ROCR + data.table)
RUN Rscript -e 'install.packages(c("caret","data.table","ROCR","randomForest","e1071"), repos="https://cloud.r-project.org/", Ncpus=2)'

# Clone RED-ML and place red_ML.pl on PATH
RUN git clone --depth 1 https://github.com/BGIRED/RED-ML.git /opt/red_ml \
    && test -f /opt/red_ml/bin/red_ML.pl \
    && chmod +x /opt/red_ml/bin/red_ML.pl

COPY validate.sh /usr/local/bin/validate-red_ml
RUN chmod +x /usr/local/bin/validate-red_ml

WORKDIR /work
CMD ["validate-red_ml"]
