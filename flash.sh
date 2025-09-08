#!/usr/bin/env bash
set -euo pipefail

REPO="BlenderDude/bk_qmk_userspace"
ARTIFACT_NAME="Firmware"
UF2_NAME="bastardkb_charybdis_4x6_daniel.uf2"
TIMEOUT_SECONDS=30

# Create a temporary directory for the artifact
TMPDIR="$(mktemp -d)"
echo "[1/4] Created temporary directory: ${TMPDIR}"

cleanup() {
  echo "[CLEANUP] Removing temporary directory..."
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

echo "[2/4] Downloading latest artifact '${ARTIFACT_NAME}' from ${REPO}..."
gh run download \
  "$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId' --repo "${REPO}")" \
  --repo "${REPO}" \
  --name "${ARTIFACT_NAME}" \
  --dir "${TMPDIR}"

echo "[3/4] Locating UF2 file '${UF2_NAME}'..."
FILE_PATH="$(find "${TMPDIR}" -type f -name "${UF2_NAME}" -print -quit || true)"
if [[ -z "${FILE_PATH}" ]]; then
  echo "ERROR: UF2 file '${UF2_NAME}' not found in artifact."
  exit 1
fi
echo "Found: ${FILE_PATH}"

echo "[4/4] Waiting for 'RPI-RP2' drive (timeout: ${TIMEOUT_SECONDS}s)..."
OS="$(uname -s || true)"

declare -a CANDIDATES=()
if [[ "${OS}" == "Darwin" ]]; then
  CANDIDATES+=( "/Volumes/RPI-RP2" )
else
  CANDIDATES+=( "/media/${USER}/RPI-RP2" "/run/media/${USER}/RPI-RP2" "/mnt/RPI-RP2" )
fi

DEST=""
start_ts="$(date +%s)"
while :; do
  for p in "${CANDIDATES[@]}"; do
    if [[ -d "${p}" && -w "${p}" ]]; then
      DEST="${p}"
      break
    fi
  done

  if [[ -n "${DEST}" ]]; then
    echo "Detected drive at: ${DEST}"
    break
  fi

  now_ts="$(date +%s)"
  elapsed=$(( now_ts - start_ts ))
  if (( elapsed >= TIMEOUT_SECONDS )); then
    echo "ERROR: 'RPI-RP2' drive not detected within ${TIMEOUT_SECONDS} seconds."
    exit 1
  fi
  sleep 1
done

echo "Copying UF2 to ${DEST}..."
cp -f "${FILE_PATH}" "${DEST}/"
sync || true
echo "Done. Safely eject the drive after the copy completes."
