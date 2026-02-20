#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="/data/data/com.termux/files/home"
PACKAGE_NAME="Shadow_VPN"
ZIP_NAME="${PACKAGE_NAME}.zip"
ZIP_DOWNLOAD_PATH="${HOME_DIR}/${ZIP_NAME}"
INSTALL_DIR="${HOME_DIR}/${PACKAGE_NAME}"
REPO_RAW_BASE="${SHADOW_VPN_RAW_BASE:-https://raw.githubusercontent.com/Pr3da7ol/ShadowVPN/main}"
ZIP_URL="${SHADOW_VPN_ZIP_URL:-${REPO_RAW_BASE}/${ZIP_NAME}}"
FORCE_UPDATE="${SHADOW_VPN_FORCE_UPDATE:-0}"
FOLLOW_LOGS="${SHADOW_VPN_FOLLOW_LOGS:-1}"

COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_GREEN='\033[0;32m'
COLOR_DIM='\033[2m'
COLOR_RESET='\033[0m'

print_header() {
  echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo -e "${COLOR_CYAN}  Shadow VPN${COLOR_RESET} ${COLOR_DIM}v1.1${COLOR_RESET}"
  echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
}

print_status() {
  echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

print_info() {
  echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $1"
}

download_package() {
  print_info "Descargando paquete..."

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fL "$ZIP_URL" -o "$ZIP_DOWNLOAD_PATH" 2>/dev/null; then
      echo -e "${COLOR_DIM}Error: No se pudo descargar el paquete${COLOR_RESET}"
      exit 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q -O "$ZIP_DOWNLOAD_PATH" "$ZIP_URL"; then
      echo -e "${COLOR_DIM}Error: No se pudo descargar el paquete${COLOR_RESET}"
      exit 1
    fi
  else
    echo -e "${COLOR_DIM}Error: No hay curl ni wget disponible${COLOR_RESET}"
    exit 1
  fi
  print_status "Paquete descargado"
}

install_package() {
  print_info "Instalando..."
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  unzip -qq "$ZIP_DOWNLOAD_PATH" -d "$INSTALL_DIR"

  # Soporta zip plano o zip con carpeta raíz Shadow_VPN/
  if [[ ! -f "$INSTALL_DIR/start_vpn.bash" && -d "$INSTALL_DIR/Shadow_VPN" ]]; then
    find "$INSTALL_DIR/Shadow_VPN" -mindepth 1 -maxdepth 1 -exec mv -f {} "$INSTALL_DIR/" \;
    rm -rf "$INSTALL_DIR/Shadow_VPN"
  fi

  if [[ ! -f "$INSTALL_DIR/start_vpn.bash" ]]; then
    echo -e "${COLOR_DIM}Error: Paquete inválido${COLOR_RESET}"
    exit 1
  fi

  chmod +x "$INSTALL_DIR/start_vpn.bash" "$INSTALL_DIR/shadow_vpn_ctl.sh" "$INSTALL_DIR/run_shadow_secure.py" 2>/dev/null
  print_status "Instalación completa"
}

show_endpoints() {
  echo ""
  echo -e "${COLOR_DIM}Web Interface:${COLOR_RESET} http://localhost:8080"
  echo -e "${COLOR_DIM}System Status:${COLOR_RESET} http://localhost:8080/status"
  echo -e "${COLOR_DIM}Cookies:${COLOR_RESET}      http://localhost:8080/cookies/status"
  echo ""
}

filter_logs() {
  local skip_traceback=0
  tail -f "$INSTALL_DIR/shadow_vpn.log" 2>/dev/null | while IFS= read -r line; do
    # Detectar inicio de traceback
    if [[ "$line" == *"Traceback"* ]]; then
      skip_traceback=1
      continue
    fi
    
    # Detectar fin de traceback (línea que empieza con palabra sin espacios)
    if [[ $skip_traceback -eq 1 ]]; then
      if [[ "$line" =~ ^[A-Z] ]] || [[ "$line" == *"["*"]"* ]]; then
        skip_traceback=0
      else
        continue
      fi
    fi
    
    # Filtrar líneas de ruido
    case "$line" in
      *"OSError"*|*"File \""*|*"in <module>"*|*"in main"*|*"self."*|*"socketserver"*|*"Address already in use"*)
        continue 
        ;;
      *"[ERROR]"*)
        # Solo mostrar errores importantes, no los técnicos
        [[ "$line" != *"salió con rc=1"* ]] && echo -e "${COLOR_DIM}⚠ ${line#*] }${COLOR_RESET}"
        ;;
      *"[OK]"*)
        echo -e "${COLOR_GREEN}✓${COLOR_RESET} ${line#*] }"
        ;;
      *"[START]"*)
        # Mostrar solo el componente, no toda la ruta
        local component="${line#*] }"
        component="${component%%:*}"
        echo -e "${COLOR_DIM}→ ${component}${COLOR_RESET}"
        ;;
      *"[STOP]"*|*"[BOOT]"*|*"profiles"*|*"refreshed"*|*"[INFO] cookies source"*|*"[INFO] Presiona Ctrl+C"*)
        continue
        ;;
      *"[INFO]"*)
        echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} ${line#*] }"
        ;;
      *)
        # Ocultar otras líneas técnicas
        ;;
    esac
  done
}

main() {
  print_header
  echo ""

  # Si ya existe una instalación activa, mantenerla sin reinstalar.
  if [[ "$FORCE_UPDATE" != "1" && -x "$INSTALL_DIR/shadow_vpn_ctl.sh" ]]; then
    if "$INSTALL_DIR/shadow_vpn_ctl.sh" status >/dev/null 2>&1; then
      print_status "Servicio activo"
      show_endpoints
      
      if [[ "$FOLLOW_LOGS" == "1" ]]; then
        echo -e "${COLOR_DIM}Presiona Ctrl+C para salir${COLOR_RESET}"
        echo ""
        filter_logs
      fi
      exit 0
    fi
  fi

  # Si está instalada pero detenida, arrancar sin redescargar.
  if [[ "$FORCE_UPDATE" != "1" && -x "$INSTALL_DIR/shadow_vpn_ctl.sh" ]]; then
    print_info "Iniciando servicio..."
    "$INSTALL_DIR/shadow_vpn_ctl.sh" start >/dev/null 2>&1
    print_status "Servicio iniciado"
    show_endpoints
    
    if [[ "$FOLLOW_LOGS" == "1" ]]; then
      echo -e "${COLOR_DIM}Presiona Ctrl+C para salir${COLOR_RESET}"
      echo ""
      filter_logs
    fi
    exit 0
  fi

  download_package
  install_package
  print_info "Iniciando servicio..."
  "$INSTALL_DIR/shadow_vpn_ctl.sh" start >/dev/null 2>&1
  print_status "Servicio iniciado"
  show_endpoints
  
  if [[ "$FOLLOW_LOGS" == "1" ]]; then
    echo -e "${COLOR_DIM}Presiona Ctrl+C para salir${COLOR_RESET}"
    echo ""
    filter_logs
  fi
}

main "$@"
