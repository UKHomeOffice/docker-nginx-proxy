#!/usr/bin/env bash
# Scan top-level directories (including root) for expr-eval / expr-eval-fork usage.
# Usage: ./scan-expr-eval.sh [root-dir]
# Default root-dir is current directory.
# It will:
#   - For each directory at depth 0..1 with a package.json: run npm ls expr-eval and npm ls expr-eval-fork
#   - For each directory with a yarn.lock: grep both tokens (case-insensitive)
# Notes:
#   - npm ls may exit non-zero if the dependency is missing; we ignore failures.
#   - Ensure node_modules are installed beforehand for accurate npm ls results.

set -euo pipefail
ROOT_DIR="${1:-.}"

if [ ! -d "${ROOT_DIR}" ]; then
  echo "Root directory not found: ${ROOT_DIR}" >&2
  exit 1
fi

# Collect top-level directories including the root itself.
mapfile -t DIRS < <(find "${ROOT_DIR}" -maxdepth 1 -type d | sort)

for dir in "${DIRS[@]}"; do
  echo "============================================================"
  echo "Directory: ${dir}"
  echo "------------------------------------------------------------"

  if [ -f "${dir}/package.json" ]; then
    echo "[npm] Checking expr-eval in ${dir}";
    (cd "${dir}" && echo "$ npm ls expr-eval" && npm ls expr-eval || echo "expr-eval NOT present or npm ls failed")
    echo "[npm] Checking expr-eval-fork in ${dir}";
    (cd "${dir}" && echo "$ npm ls expr-eval-fork" && npm ls expr-eval-fork || echo "expr-eval-fork NOT present or npm ls failed")
  else
    echo "No package.json present. Skipping npm ls checks."
  fi

  if [ -f "${dir}/yarn.lock" ]; then
    echo "[yarn.lock] Searching for expr-eval-fork";
    if ! grep -i 'expr-eval-fork' "${dir}/yarn.lock"; then
      echo "expr-eval-fork NOT found in yarn.lock"
    fi
    echo "[yarn.lock] Searching for expr-eval";
    if ! grep -i 'expr-eval' "${dir}/yarn.lock"; then
      echo "expr-eval NOT found in yarn.lock"
    fi
  else
    echo "No yarn.lock present. Skipping yarn greps."
  fi
  echo
done

echo "Scan complete."
