# REDITs is an R-only library (no compiled code): REDIT_LLR.R and REDIT_regression.R define
# beta-binomial tests for differential RNA editing. Core functions need only base R + `stats`
# (the optional doParallel/foreach are for the user's own loops, not the functions). We bundle
# a thin pipeline wrapper, `redits_llr.R`, that sources REDIT_LLR.R and applies REDIT-LLR
# site-by-site to a per-site edited/total count matrix across two conditions.
#
# Reference: https://github.com/gxiaolab/REDITs
FROM rocker/r-ver:4.3.2

LABEL org.opencontainers.image.title="REDITs"
LABEL org.opencontainers.image.description="REDITs (REDIT-LLR / REDIT-regression) beta-binomial differential-editing tests, plus a per-site LLR wrapper. Reference: gxiaolab/REDITs."

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/redits:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

# REDITs source: provides REDIT_LLR.R and REDIT_regression.R, sourced by the wrapper.
RUN git clone --depth 1 https://github.com/gxiaolab/REDITs.git /opt/redits-src \
    && test -f /opt/redits-src/REDIT_LLR.R \
    && test -f /opt/redits-src/REDIT_regression.R

# Pipeline wrapper. REDITS_SRC points it at the upstream sources to `source()`.
ENV REDITS_SRC=/opt/redits-src
RUN mkdir -p /opt/redits
COPY redits_llr.R /opt/redits/redits_llr.R
COPY validate.sh /usr/local/bin/validate-redits
RUN chmod +x /opt/redits/redits_llr.R /usr/local/bin/validate-redits

WORKDIR /work
CMD ["validate-redits"]
