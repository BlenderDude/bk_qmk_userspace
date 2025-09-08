#!/usr/bin/env bash
set -euo pipefail

REPO="BlenderDude/bk_qmk_userspace"
ARTIFACT_NAME="Firmware"
UF2_NAME="bastardkb_charybdis_4x6_daniel.uf2"
TIMEOUT_SECONDS=30

# Create a temporary directory for the artifact
TMPDIR="$(mktemp -d)"
echo "[1/5] Created temporary directory: ${TMPDIR}"

cleanup() {
  echo "[CLEANUP] Removing temporary directory..."
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

echo "[2/5] Checking latest workflow run for ${REPO}..."
RUN_ID="$(gh run list --limit 1 --repo "${REPO}" --json databaseId --jq '.[0].databaseId')"
RUN_STATUS="$(gh run view "${RUN_ID}" --repo "${REPO}" --json status --jq '.status')"
RUN_CONCLUSION="$(gh run view "${RUN_ID}" --repo "${REPO}" --json conclusion --jq '.conclusion')"

echo "Latest run ID: ${RUN_ID} (status=${RUN_STATUS}, conclusion=${RUN_CONCLUSION})"

# Wait for completion if still running
if [[ "${RUN_STATUS}" != "completed" ]]; then
  echo "[WAIT] Run is still in progress. Waiting for it to complete..."
  gh run watch "${RUN_ID}" --repo "${REPO}" --exit-status || {
    echo "ERROR: Workflow failed or was cancelled."
    exit 1
  }
  echo "[WAIT] Run finished successfully."
fi

echo "[3/5] Downloading artifact '${ARTIFACT_NAME}'..."
gh run download "${RUN_ID}" \
  --repo "${REPO}" \
  --name "${ARTIFACT_NAME}" \
  --dir "${TMPDIR}"

echo "[4/5] Locating UF2 file '${UF2_NAME}'..."
FILE_PATH="$(find "${TMPDIR}" -type f -name "${UF2_NAME}" -print -quit || true)"
if [[ -z "${FILE_PATH}" ]]; then
  echo "ERROR: UF2 file '${UF2_NAME}' not found in artifact."
  exit 1
fi
echo "Found: ${FILE_PATH}"

echo "[5/5] Waiting for 'RPI-RP2' drive (timeout: ${TIMEOUT_SECONDS}s)..."
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
