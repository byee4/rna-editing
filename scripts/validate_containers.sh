#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${CONTAINER_DATA_ROOT:-/Volumes/X9Pro/container_data}"
PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
TOOLS="${TOOLS:-reditools jacusa2 sprint lodei red sailor}"
APPTAINER_IMAGE="${APPTAINER_IMAGE:-ghcr.io/apptainer/apptainer:1.4.4}"
SIF_DIR="${SIF_OUTPUT_DIR:-${DATA_ROOT}/singularity_images}"
ARCHIVE_DIR="${DOCKER_ARCHIVE_DIR:-${DATA_ROOT}/images}"
CACHE_ROOT="${DOCKER_CACHE_ROOT:-${DATA_ROOT}/docker-cache}"
TMP_ROOT="${CONTAINER_TMP_ROOT:-${DATA_ROOT}/tmp}"
APPTAINER_CACHE_ROOT="${APPTAINER_CACHE_ROOT:-${TMP_ROOT}/apptainer-cache}"
APPTAINER_TMP_ROOT="${APPTAINER_TMP_ROOT:-${TMP_ROOT}/apptainer-tmp}"
HOST_TMP_ROOT="${HOST_TMP_ROOT:-${TMP_ROOT}/host-tmp}"
BUILDX_CONFIG="${BUILDX_CONFIG:-${TMP_ROOT}/buildx-config}"
BUILDX_BUILDER="${BUILDX_BUILDER:-rna-editing-x9pro}"
REUSE_EXISTING_ARCHIVES="${REUSE_EXISTING_ARCHIVES:-1}"
APPTAINER_TMPFS_SIZE="${APPTAINER_TMPFS_SIZE:-4g}"

export TMPDIR="${HOST_TMP_ROOT}"
export BUILDX_CONFIG
export APPTAINER_CACHEDIR="${APPTAINER_CACHE_ROOT}"
export APPTAINER_TMPDIR="${APPTAINER_TMP_ROOT}"
export SINGULARITY_CACHEDIR="${APPTAINER_CACHE_ROOT}"
export SINGULARITY_TMPDIR="${APPTAINER_TMP_ROOT}"

mkdir -p "${ARCHIVE_DIR}" "${CACHE_ROOT}" "${SIF_DIR}" "${TMP_ROOT}" \
  "${APPTAINER_CACHE_ROOT}" "${APPTAINER_TMP_ROOT}" "${HOST_TMP_ROOT}" \
  "${BUILDX_CONFIG}"

print_storage_state() {
  echo "==> Storage state"
  df -h / /Volumes/X9Pro /Volumes/Macintosh\ HD 2>/dev/null || true
  echo "==> Externalized environment"
  printf 'CONTAINER_DATA_ROOT=%s\n' "${DATA_ROOT}"
  printf 'SIF_OUTPUT_DIR=%s\n' "${SIF_DIR}"
  printf 'DOCKER_ARCHIVE_DIR=%s\n' "${ARCHIVE_DIR}"
  printf 'DOCKER_CACHE_ROOT=%s\n' "${CACHE_ROOT}"
  printf 'CONTAINER_TMP_ROOT=%s\n' "${TMP_ROOT}"
  printf 'TMPDIR=%s\n' "${TMPDIR}"
  printf 'DOCKER_CONFIG=%s\n' "${DOCKER_CONFIG:-<host default, required for Docker CLI plugins>}"
  printf 'BUILDX_CONFIG=%s\n' "${BUILDX_CONFIG}"
  printf 'BUILDX_BUILDER=%s\n' "${BUILDX_BUILDER}"
  printf 'REUSE_EXISTING_ARCHIVES=%s\n' "${REUSE_EXISTING_ARCHIVES}"
  printf 'APPTAINER_TMPFS_SIZE=%s\n' "${APPTAINER_TMPFS_SIZE}"
  printf 'APPTAINER_CACHEDIR=%s\n' "${APPTAINER_CACHEDIR}"
  printf 'APPTAINER_TMPDIR=%s\n' "${APPTAINER_TMPDIR}"
}

ensure_builder() {
  if docker buildx inspect "${BUILDX_BUILDER}" >/dev/null 2>&1; then
    return
  fi

  echo "==> Creating temporary Buildx builder ${BUILDX_BUILDER}"
  docker buildx create --name "${BUILDX_BUILDER}" --driver docker-container >/dev/null
}

cleanup_builder() {
  docker buildx rm "${BUILDX_BUILDER}" >/dev/null 2>&1 || true
}

build_archive() {
  local tool="$1"
  local context="${ROOT_DIR}/containers/${tool}"
  local archive="${ARCHIVE_DIR}/${tool}.tar"

  echo "==> Building Docker archive ${archive}"
  if [[ "${REUSE_EXISTING_ARCHIVES}" == "1" && -s "${archive}" ]]; then
    echo "Archive already exists; reusing ${archive}"
    return
  fi

  rm -f "${archive}"
  mkdir -p "$(dirname "${archive}")"
  ensure_builder
  docker buildx build \
    --builder "${BUILDX_BUILDER}" \
    --progress=plain \
    --no-cache \
    --platform "${PLATFORM}" \
    --output "type=docker,dest=${archive}" \
    "${context}"
}

build_sif() {
  local tool="$1"
  local archive="${ARCHIVE_DIR}/${tool}.tar"
  local sif="${SIF_DIR}/${tool}.sif"
  local workspace_sif="/workspace/singularity_images/${tool}.sif"
  local workspace_archive="/workspace/images/${tool}.tar"
  local workspace_cache="/workspace/tmp/apptainer-cache/${tool}"
  local workspace_tmp="/tmp"

  echo "==> Building Singularity/Apptainer image ${sif}"
  rm -f "${sif}"
  mkdir -p "$(dirname "${sif}")" "${APPTAINER_CACHE_ROOT}/${tool}" "${APPTAINER_TMP_ROOT}/${tool}"
  docker run --rm --privileged --platform "${PLATFORM}" \
    --tmpfs "/tmp:exec,size=${APPTAINER_TMPFS_SIZE}" \
    -e APPTAINER_CACHEDIR="${workspace_cache}" \
    -e APPTAINER_TMPDIR="${workspace_tmp}" \
    -e SINGULARITY_CACHEDIR="${workspace_cache}" \
    -e SINGULARITY_TMPDIR="${workspace_tmp}" \
    -e TMPDIR="${workspace_tmp}" \
    -v "${DATA_ROOT}:/workspace" \
    "${APPTAINER_IMAGE}" \
    /bin/sh -lc "mkdir -p '${workspace_cache}' '${workspace_tmp}' && apptainer build '${workspace_sif}' 'docker-archive://${workspace_archive}'"
}

validate_sif() {
  local tool="$1"
  local workspace_sif="/workspace/singularity_images/${tool}.sif"
  local workspace_cache="/workspace/tmp/apptainer-cache/${tool}"
  local workspace_tmp="/tmp"

  echo "==> Validating Singularity/Apptainer image ${SIF_DIR}/${tool}.sif"
  docker run --rm --privileged --platform "${PLATFORM}" \
    --tmpfs "/tmp:exec,size=${APPTAINER_TMPFS_SIZE}" \
    -e APPTAINER_CACHEDIR="${workspace_cache}" \
    -e APPTAINER_TMPDIR="${workspace_tmp}" \
    -e SINGULARITY_CACHEDIR="${workspace_cache}" \
    -e SINGULARITY_TMPDIR="${workspace_tmp}" \
    -e TMPDIR="${workspace_tmp}" \
    -v "${DATA_ROOT}:/workspace" \
    "${APPTAINER_IMAGE}" \
    /bin/sh -lc "mkdir -p '${workspace_cache}' '${workspace_tmp}' && apptainer exec '${workspace_sif}' '/usr/local/bin/validate-${tool}'"
}

cleanup_tool() {
  local tool="$1"

  echo "==> Cleaning external temporary files for ${tool}"
  rm -rf \
    "${ARCHIVE_DIR}/${tool}.tar" \
    "${CACHE_ROOT:?}/${tool}" \
    "${APPTAINER_CACHE_ROOT:?}/${tool}" \
    "${APPTAINER_TMP_ROOT:?}/${tool}" \
    "${HOST_TMP_ROOT:?}/${tool}"
  if docker buildx inspect "${BUILDX_BUILDER}" >/dev/null 2>&1; then
    docker buildx prune --builder "${BUILDX_BUILDER}" -af >/dev/null || true
  fi
  docker builder prune -f >/dev/null || true
}

trap cleanup_builder EXIT
print_storage_state
for tool in ${TOOLS}; do
  build_archive "${tool}"
  build_sif "${tool}"
  validate_sif "${tool}"
  cleanup_tool "${tool}"
  print_storage_state
done

echo "All requested containers validated successfully."
