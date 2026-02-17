#!/usr/bin/env bash
set -euo pipefail

REPO="jarcos-al/airplayer-dependecies-installer"

# Detecta rama por defecto (main/master) sin depender de herramientas raras
detect_branch() {
  if curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/proxmox-audio-prep.sh" >/dev/null 2>&1; then
    echo "main"
  else
    echo "master"
  fi
}

BRANCH="$(detect_branch)"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== Proxmox Audio Prep installer =="
echo "Repo:   ${REPO}"
echo "Branch: ${BRANCH}"
echo

echo ">> Descargando proxmox-audio-prep.sh..."
curl -fsSL "${BASE}/proxmox-audio-prep.sh" -o "${TMP}/proxmox-audio-prep.sh"

chmod +x "${TMP}/proxmox-audio-prep.sh"

# (Opcional) instalar copia local “para siempre”
INSTALL_PATH="/usr/local/sbin/proxmox-audio-prep"
if [ "${INSTALL_LOCAL:-1}" = "1" ]; then
  echo ">> Instalando copia local en ${INSTALL_PATH}"
  install -m 0755 "${TMP}/proxmox-audio-prep.sh" "${INSTALL_PATH}"
  echo "   Ahora puedes ejecutar: ${INSTALL_PATH}"
fi

echo ">> Ejecutando script..."
exec "${TMP}/proxmox-audio-prep.sh"
