#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${CONTAINER_DATA_ROOT:-/Volumes/X9Pro/container_data/rna-editing}"
PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
TOOLS="${TOOLS:-reditools jacusa2 sprint lodei red sailor}"
APPTAINER_IMAGE="${APPTAINER_IMAGE:-ghcr.io/apptainer/apptainer:1.4.4}"
APPTAINER_TMPFS_SIZE="${APPTAINER_TMPFS_SIZE:-4g}"

mkdir -p "${DATA_ROOT}/docker-cache" "${DATA_ROOT}/images" "${DATA_ROOT}/sif" \
  "${DATA_ROOT}/tmp/apptainer-cache"

build_image() {
  local tool="$1"
  local tag="rna-editing/${tool}:latest"
  local context="${ROOT_DIR}/containers/${tool}"

  echo "==> Building ${tag}"
  if ! DOCKER_BUILDKIT=1 docker build \
      --platform "${PLATFORM}" \
      --tag "${tag}" \
      --cache-from "type=local,src=${DATA_ROOT}/docker-cache/${tool}" \
      --cache-to "type=local,dest=${DATA_ROOT}/docker-cache/${tool},mode=max" \
      "${context}"; then
    echo "Host-cache export is unavailable with this Docker builder; retrying ${tag} without external BuildKit cache."
    docker build --platform "${PLATFORM}" --tag "${tag}" "${context}"
  fi
}

validate_docker() {
  local tool="$1"
  local tag="rna-editing/${tool}:latest"

  echo "==> Validating Docker image ${tag}"
  docker run --rm --platform "${PLATFORM}" --entrypoint "/usr/local/bin/validate-${tool}" "${tag}"
}

archive_image() {
  local tool="$1"
  local tag="rna-editing/${tool}:latest"
  local archive="${DATA_ROOT}/images/${tool}.tar"

  echo "==> Saving Docker archive ${archive}"
  docker save "${tag}" -o "${archive}"
}

build_sif() {
  local tool="$1"
  local archive="${DATA_ROOT}/images/${tool}.tar"
  local sif="${DATA_ROOT}/sif/${tool}.sif"

  echo "==> Building Singularity/Apptainer image ${sif}"
  rm -f "${sif}"
  docker run --rm --privileged --platform "${PLATFORM}" \
    --tmpfs "/tmp:exec,size=${APPTAINER_TMPFS_SIZE}" \
    -e APPTAINER_CACHEDIR=/workspace/tmp/apptainer-cache \
    -e APPTAINER_TMPDIR=/tmp/apptainer-tmp \
    -v "${DATA_ROOT}:/workspace" \
    "${APPTAINER_IMAGE}" \
    /bin/sh -lc "mkdir -p /workspace/tmp/apptainer-cache /tmp/apptainer-tmp && apptainer build '/workspace/sif/${tool}.sif' 'docker-archive:///workspace/images/${tool}.tar'"
}

validate_sif() {
  local tool="$1"
  local sif="${DATA_ROOT}/sif/${tool}.sif"

  echo "==> Validating Singularity/Apptainer image ${sif}"
  docker run --rm --privileged --platform "${PLATFORM}" \
    --tmpfs "/tmp:exec,size=${APPTAINER_TMPFS_SIZE}" \
    -e APPTAINER_CACHEDIR=/workspace/tmp/apptainer-cache \
    -e APPTAINER_TMPDIR=/tmp/apptainer-tmp \
    -v "${DATA_ROOT}:/workspace" \
    "${APPTAINER_IMAGE}" \
    /bin/sh -lc "mkdir -p /workspace/tmp/apptainer-cache /tmp/apptainer-tmp && apptainer exec '/workspace/sif/${tool}.sif' '/usr/local/bin/validate-${tool}'"
}

for tool in ${TOOLS}; do
  build_image "${tool}"
  validate_docker "${tool}"
  archive_image "${tool}"
  build_sif "${tool}"
  validate_sif "${tool}"
done

echo "All requested containers validated successfully."
