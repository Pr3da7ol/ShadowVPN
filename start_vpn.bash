#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="/data/data/com.termux/files/home"
PACKAGE_NAME="Shadow_VPN"
ZIP_NAME="${PACKAGE_NAME}.zip"
ZIP_DOWNLOAD_PATH="${HOME_DIR}/${ZIP_NAME}"
INSTALL_DIR="${HOME_DIR}/${PACKAGE_NAME}"
REPO_RAW_BASE="${SHADOW_VPN_RAW_BASE:-https://raw.githubusercontent.com/Pr3da7ol/ShadowVPN/main}"
ZIP_URL="${SHADOW_VPN_ZIP_URL:-${REPO_RAW_BASE}/${ZIP_NAME}}"

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RESET='\033[0m'

print_msg() {
  local level="$1"
  local color="$2"
  local text="$3"
  echo -e "${color}[${level}] ${text}${COLOR_RESET}"
}

download_package() {
  print_msg "INFO" "$COLOR_YELLOW" "Descargando paquete Shadow_VPN desde GitHub..."
  print_msg "INFO" "$COLOR_YELLOW" "URL: $ZIP_URL"

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fL "$ZIP_URL" -o "$ZIP_DOWNLOAD_PATH"; then
      print_msg "ERROR" "$COLOR_RED" "No se pudo descargar $ZIP_URL"
      exit 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -O "$ZIP_DOWNLOAD_PATH" "$ZIP_URL"; then
      print_msg "ERROR" "$COLOR_RED" "No se pudo descargar $ZIP_URL"
      exit 1
    fi
  else
    print_msg "ERROR" "$COLOR_RED" "No hay curl ni wget para descargar."
    exit 1
  fi
}

install_package() {
  print_msg "INFO" "$COLOR_YELLOW" "Instalando Shadow_VPN..."
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  unzip -o "$ZIP_DOWNLOAD_PATH" -d "$INSTALL_DIR" >/dev/null

  # Soporta zip plano o zip con carpeta raíz Shadow_VPN/
  if [[ ! -f "$INSTALL_DIR/start_vpn.bash" && -d "$INSTALL_DIR/Shadow_VPN" ]]; then
    find "$INSTALL_DIR/Shadow_VPN" -mindepth 1 -maxdepth 1 -exec mv -f {} "$INSTALL_DIR/" \;
    rm -rf "$INSTALL_DIR/Shadow_VPN"
  fi

  if [[ ! -f "$INSTALL_DIR/start_vpn.bash" ]]; then
    print_msg "ERROR" "$COLOR_RED" "ZIP invalido: no contiene start_vpn.bash"
    exit 1
  fi

  chmod +x "$INSTALL_DIR/start_vpn.bash" "$INSTALL_DIR/shadow_vpn_ctl.sh" "$INSTALL_DIR/run_shadow_secure.py"
}

main() {
  print_msg "EXITO" "$COLOR_GREEN" "Shadow_VPN activado"
  download_package
  install_package
  cd "$INSTALL_DIR"
  ./start_vpn.bash
}

main "$@"
