FROM maven:3.9-eclipse-temurin-17 AS build

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/dieterich-lab/JACUSA2.git /src/jacusa2
WORKDIR /src/jacusa2
RUN mvn -DskipTests package \
    && mkdir -p /opt/jacusa2 \
    && find target -maxdepth 1 -type f -name "*.jar" -print -quit | xargs -I{} cp {} /opt/jacusa2/jacusa2.jar

FROM eclipse-temurin:17-jre-jammy

LABEL org.opencontainers.image.title="JACUSA2"
LABEL org.opencontainers.image.description="Java 17 runtime with JACUSA2 and SAMtools for RNA editing and variant comparison workflows."

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        samtools \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/jacusa2/jacusa2.jar /opt/jacusa2/jacusa2.jar
COPY validate.sh /usr/local/bin/validate-jacusa2
RUN chmod +x /usr/local/bin/validate-jacusa2

WORKDIR /work
ENTRYPOINT ["java", "-jar", "/opt/jacusa2/jacusa2.jar"]
CMD ["--help"]
