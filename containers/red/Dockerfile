FROM ubuntu:20.04

LABEL org.opencontainers.image.title="RED RNA Editing Detector"
LABEL org.opencontainers.image.description="RED runtime with Java, R, MySQL client libraries, and the RED application jar."

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        default-mysql-client \
        openjdk-11-jdk-headless \
        r-base \
        unzip \
        wget \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/red \
    && wget -qO /opt/red/RED.jar https://github.com/REDetector/redetector.github.io/raw/master/RED.jar \
    && test -s /opt/red/RED.jar

COPY validate.sh /usr/local/bin/validate-red
RUN chmod +x /usr/local/bin/validate-red

WORKDIR /work
CMD ["validate-red"]
