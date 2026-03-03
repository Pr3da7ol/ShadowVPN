#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZIP_URL="${ZIP_URL:-https://raw.githubusercontent.com/Pr3da7ol/ShadowVPN/main/vpn-shadow.zip}"
ZIP_FILE="${ZIP_FILE:-$SCRIPT_DIR/vpn-shadow.zip}"
VPN_DIR="${VPN_DIR:-$SCRIPT_DIR/vpn-shadow}"
MAIN_FILE="${MAIN_FILE:-$VPN_DIR/main.py}"

KILL_OCCUPIED_PORT="${KILL_OCCUPIED_PORT:-1}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VPN_PID=""
SIGNAL_HANDLED=0

log() {
  local level="$1"
  local color="$2"
  local msg="$3"
  echo -e "${color}[${level}] ${msg}${NC}"
}

resolve_python() {
  if [[ -n "${PYTHON_BIN:-}" ]]; then
    echo "$PYTHON_BIN"
    return
  fi
  if [[ -x "/data/data/com.termux/files/usr/bin/python3" ]]; then
    echo "/data/data/com.termux/files/usr/bin/python3"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi
  if command -v pkg >/dev/null 2>&1; then
    log "SETUP" "$CYAN" "Instalando python3..."
    pkg install -y python3 || true
  fi
  command -v python3
}

download_zip() {
  local require_remote="${1:-0}"
  local tmp_zip="${ZIP_FILE}.download.$$"
  local ok=0
  log "SYNC" "$CYAN" "Descargando ZIP de la VPN..."
  if command -v curl >/dev/null 2>&1; then
    if curl -fL "$ZIP_URL" -o "$tmp_zip"; then
      ok=1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -O "$tmp_zip" "$ZIP_URL"; then
      ok=1
    fi
  fi

  if [[ "$ok" == "1" ]]; then
    mv "$tmp_zip" "$ZIP_FILE"
    log "OK" "$GREEN" "ZIP descargado: $ZIP_FILE"
    return 0
  fi

  if [[ -s "$tmp_zip" ]]; then
    rm -f "$tmp_zip" >/dev/null 2>&1 || true
  fi

  if [[ "$require_remote" == "1" ]]; then
    log "ERROR" "$RED" "No se pudo descargar $ZIP_URL (modo instalación limpia)."
    return 1
  fi

  if [[ -s "$ZIP_FILE" ]]; then
    log "WARN" "$YELLOW" "No se pudo descargar $ZIP_URL. Se usará ZIP local existente: $ZIP_FILE"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    log "ERROR" "$RED" "No hay curl ni wget para descargar $ZIP_URL"
  else
    log "ERROR" "$RED" "No se pudo descargar ZIP y no existe copia local: $ZIP_FILE"
  fi
  return 1
}

extract_zip() {
  local py="$1"
  log "SYNC" "$CYAN" "Descomprimiendo ZIP de la VPN..."
  "$py" - "$ZIP_FILE" "$SCRIPT_DIR" "$VPN_DIR" << 'PY'
import os
import shutil
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1])
script_dir = Path(sys.argv[2])
vpn_dir = Path(sys.argv[3])

if not zip_path.is_file():
    raise SystemExit(f"ZIP no encontrado: {zip_path}")

if vpn_dir.exists():
    shutil.rmtree(vpn_dir, ignore_errors=True)

with zipfile.ZipFile(zip_path, "r") as zf:
    zf.extractall(script_dir)

main_file = vpn_dir / "main.py"
if not main_file.is_file():
    raise SystemExit(f"No se encontró main.py tras extraer ZIP: {main_file}")
PY
  log "OK" "$GREEN" "ZIP descomprimido en: $VPN_DIR"
}

handle_signal() {
  local sig="$1"
  if [[ "$SIGNAL_HANDLED" == "1" ]]; then
    case "$sig" in
      INT) exit 130 ;;
      QUIT) exit 131 ;;
      TERM) exit 143 ;;
      *) exit 1 ;;
    esac
  fi
  SIGNAL_HANDLED=1
  log "WARN" "$YELLOW" "Señal $sig recibida. Deteniendo VPN..."

  if [[ -n "$VPN_PID" ]] && kill -0 "$VPN_PID" >/dev/null 2>&1; then
    kill -TERM "$VPN_PID" >/dev/null 2>&1 || true
    for _ in 1 2 3; do
      if ! kill -0 "$VPN_PID" >/dev/null 2>&1; then
        break
      fi
      sleep 0.4
    done
    if kill -0 "$VPN_PID" >/dev/null 2>&1; then
      kill -KILL "$VPN_PID" >/dev/null 2>&1 || true
    fi
    wait "$VPN_PID" >/dev/null 2>&1 || true
  fi

  case "$sig" in
    INT) exit 130 ;;
    QUIT) exit 131 ;;
    TERM) exit 143 ;;
    *) exit 1 ;;
  esac
}

setup_signal_traps() {
  trap 'handle_signal INT' INT
  trap 'handle_signal QUIT' QUIT
  trap 'handle_signal TERM' TERM
}

ensure_deps() {
  local py="$1"
  local missing_pkgs
  missing_pkgs="$($py - << 'PY'
checks = [
    ("requests", "requests"),
    ("bs4", "beautifulsoup4"),
    ("cryptography", "cryptography"),
    ("cffi", "cffi"),
]
missing = []
for module_name, pkg_name in checks:
    try:
        __import__(module_name)
    except Exception:
        missing.append(pkg_name)

has_crypto = False
for crypto_mod in ("Crypto", "Cryptodome"):
    try:
        __import__(crypto_mod)
        has_crypto = True
        break
    except Exception:
        pass
if not has_crypto:
    missing.append("pycryptodome")

seen = set()
ordered = []
for pkg in missing:
    if pkg not in seen:
        seen.add(pkg)
        ordered.append(pkg)
print(" ".join(ordered))
PY
)"
  if [[ -z "$missing_pkgs" ]]; then
    return 0
  fi

  if ! "$py" -m pip --version >/dev/null 2>&1; then
    if command -v pkg >/dev/null 2>&1; then
      log "SETUP" "$CYAN" "pip no disponible. Intentando instalar python-pip..."
      pkg install -y python-pip >/dev/null 2>&1 || true
    fi
  fi

  if "$py" -m pip --version >/dev/null 2>&1; then
    log "SETUP" "$CYAN" "Instalando dependencias faltantes: $missing_pkgs"
    "$py" -m pip install --no-cache-dir $missing_pkgs || true
  else
    log "WARN" "$YELLOW" "pip no disponible en $py. Instala manualmente: $missing_pkgs"
  fi
}

install_system_dependencies() {
  if ! command -v pkg >/dev/null 2>&1; then
    log "WARN" "$YELLOW" "No se detectó pkg (Termux). Se omite instalación de paquetes del sistema."
    return 0
  fi

  if command -v python3 >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && (command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1); then
    log "SETUP" "$CYAN" "Dependencias base del sistema ya instaladas. Omitiendo pkg install."
    return 0
  fi

  if [[ "${TERMUX_REFRESH_REPOS:-0}" == "1" ]]; then
    log "SETUP" "$CYAN" "Actualizando repositorios de Termux..."
    pkg update -y || true
  fi

  log "SETUP" "$CYAN" "Instalando dependencias del sistema..."
  pkg install -y python python-pip curl unzip python-cryptography lsof procps || true
}

setup_storage_permission() {
  if [[ "${TERMUX_SETUP_STORAGE:-0}" != "1" ]]; then
    return 0
  fi
  if command -v termux-setup-storage >/dev/null 2>&1; then
    log "SETUP" "$CYAN" "Solicitando permisos de almacenamiento..."
    termux-setup-storage || true
    echo "Acepta el permiso en Android y presiona ENTER para continuar."
    read -r
  fi
}

repair_termux_repos_and_libs() {
  if ! command -v apt >/dev/null 2>&1; then
    log "WARN" "$YELLOW" "apt no disponible en este entorno."
    return 0
  fi

  if command -v termux-change-repo >/dev/null 2>&1; then
    log "SETUP" "$CYAN" "Abriendo termux-change-repo (elige mirror y confirma)..."
    termux-change-repo || true
  else
    log "WARN" "$YELLOW" "termux-change-repo no está disponible."
  fi

  log "SETUP" "$CYAN" "Ejecutando apt update..."
  apt update || true
  log "SETUP" "$CYAN" "Ejecutando apt full-upgrade..."
  apt full-upgrade -y || true

  log "OK" "$GREEN" "Reparación de repositorios/librerías completada."
}

resolve_launch_port() {
  local launch_port="$PORT"
  local prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--port" && -n "$arg" ]]; then
      launch_port="$arg"
      break
    fi
    case "$arg" in
      --port=*)
        launch_port="${arg#--port=}"
        break
        ;;
    esac
    prev="$arg"
  done
  printf '%s\n' "$launch_port"
}

resolve_launch_host() {
  local launch_host="$HOST"
  local prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--host" && -n "$arg" ]]; then
      launch_host="$arg"
      break
    fi
    case "$arg" in
      --host=*)
        launch_host="${arg#--host=}"
        break
        ;;
    esac
    prev="$arg"
  done
  printf '%s\n' "$launch_host"
}

has_help_flag() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
      return 0
    fi
  done
  return 1
}

find_pids_on_port() {
  local port="$1"
  local pids=""

  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' | xargs echo 2>/dev/null || true)"
  fi

  if [[ -z "$pids" ]] && command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "$port" 2>/dev/null | tr '\n' ' ' | xargs echo 2>/dev/null || true)"
  fi

  if [[ -z "$pids" ]] && command -v ss >/dev/null 2>&1; then
    pids="$(ss -ltnp "sport = :$port" 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ' | xargs echo 2>/dev/null || true)"
  fi

  printf '%s\n' "$pids"
}

port_is_busy() {
  local py="$1"
  local port="$2"
  "$py" - "$port" << 'PY'
import socket
import sys

port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("0.0.0.0", port))
except OSError:
    raise SystemExit(0)
finally:
    s.close()
raise SystemExit(1)
PY
}

find_fallback_pids_for_port() {
  local port="$1"
  local pids=""
  if command -v pgrep >/dev/null 2>&1; then
    pids+=" $(pgrep -f '/vpn-shadow/main.py' 2>/dev/null || true)"
    pids+=" $(pgrep -f 'shadow_vpn.py' 2>/dev/null || true)"
    pids+=" $(pgrep -f "python.*--port[= ]$port" 2>/dev/null || true)"
    pids+=" $(pgrep -f "http.server $port" 2>/dev/null || true)"
  fi
  printf '%s\n' "$pids"
}

is_protected_pid() {
  local target="$1"
  [[ "$target" =~ ^[0-9]+$ ]] || return 1

  local cur="$$"
  while [[ -n "$cur" && "$cur" =~ ^[0-9]+$ ]]; do
    if [[ "$target" == "$cur" ]]; then
      return 0
    fi
    cur="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -z "$cur" || "$cur" == "0" || "$cur" == "1" ]]; then
      break
    fi
  done
  return 1
}

kill_processes_on_port() {
  local py="$1"
  local port="$2"
  [[ "$KILL_OCCUPIED_PORT" == "1" ]] || return 0

  local pids fallback_pids
  pids="$(find_pids_on_port "$port")"

  if [[ -z "$pids" ]] && port_is_busy "$py" "$port"; then
    fallback_pids="$(find_fallback_pids_for_port "$port")"
    pids="$fallback_pids"
  fi

  if [[ -z "$pids" ]]; then
    if port_is_busy "$py" "$port"; then
      log "WARN" "$YELLOW" "Puerto $port ocupado, pero no se pudo resolver PID automáticamente."
    fi
    return 0
  fi

  log "WARN" "$YELLOW" "Puerto $port ocupado. Matando PID(s): $pids"
  local pid
  for pid in $pids; do
    if [[ "$pid" =~ ^[0-9]+$ ]] && ! is_protected_pid "$pid"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
  sleep 1
}

has_local_install() {
  [[ -f "$MAIN_FILE" ]]
}

clean_install_target() {
  log "SYNC" "$CYAN" "Limpiando instalación local previa..."
  if [[ -d "$VPN_DIR" ]]; then
    rm -rf "$VPN_DIR"
    log "OK" "$GREEN" "Carpeta eliminada: $VPN_DIR"
  else
    log "INFO" "$CYAN" "Carpeta no existe, se omite: $VPN_DIR"
  fi

  if [[ -f "$ZIP_FILE" ]]; then
    rm -f "$ZIP_FILE"
    log "OK" "$GREEN" "ZIP eliminado: $ZIP_FILE"
  else
    log "INFO" "$CYAN" "ZIP no existe, se omite: $ZIP_FILE"
  fi
}

install_from_termux() {
  local py="$1"
  shift || true
  install_system_dependencies
  setup_storage_permission
  py="$(resolve_python)"
  clean_install_target
  download_zip 1
  extract_zip "$py"
  ensure_deps "$py"
  log "OK" "$GREEN" "Instalación local actualizada en: $VPN_DIR"
  log "LAUNCH" "$GREEN" "Iniciando VPN tras instalación..."
  launch_vpn "$py" "$@"
}

launch_vpn() {
  local py="$1"
  shift || true

  if [[ ! -f "$MAIN_FILE" ]]; then
    log "ERROR" "$RED" "No existe: $MAIN_FILE"
    return 1
  fi

  local launch_host launch_port
  launch_host="$(resolve_launch_host "$@")"
  launch_port="$(resolve_launch_port "$@")"
  if ! has_help_flag "$@"; then
    kill_processes_on_port "$py" "$launch_port"
  fi

  log "LAUNCH" "$GREEN" "Iniciando Shadow VPN desde: $MAIN_FILE"
  log "INFO" "$CYAN" "Panel: http://$launch_host:$launch_port/panel"
  log "INFO" "$CYAN" "Descargas: http://$launch_host:$launch_port/download"

  local status=0
  if [[ $# -eq 0 ]]; then
    "$py" "$MAIN_FILE" --host "$HOST" --port "$PORT" &
  else
    "$py" "$MAIN_FILE" "$@" &
  fi

  VPN_PID="$!"
  if ! wait "$VPN_PID"; then
    status="$?"
  fi
  VPN_PID=""
  return "$status"
}

show_menu() {
  echo
  echo "==================== SHADOW VPN ===================="
  echo "1) Instalar desde Termux (descarga ZIP e inicia VPN)"
  echo "2) Ejecutar desde local (sin descargar)"
  echo "3) Reparar librerías de Termux (repo + update/upgrade)"
  echo "0) Salir"
  echo "===================================================="
}

menu_loop() {
  local py="$1"
  while true; do
    show_menu
    read -r -p "Selecciona una opción [1-3,0]: " option
    case "$option" in
      1)
        local app_status=0
        install_from_termux "$py" || app_status="$?"
        if [[ "$app_status" -ne 0 ]]; then
          log "WARN" "$YELLOW" "La VPN finalizó con código: $app_status"
        fi
        ;;
      2)
        if ! has_local_install; then
          log "ERROR" "$RED" "No existe instalación local. Usa la opción 1 primero."
          continue
        fi
        ensure_deps "$py"
        local app_status=0
        launch_vpn "$py" || app_status="$?"
        if [[ "$app_status" -ne 0 ]]; then
          log "WARN" "$YELLOW" "La VPN finalizó con código: $app_status"
        fi
        ;;
      3)
        repair_termux_repos_and_libs
        ;;
      0|q|Q|salir|SALIR)
        log "INFO" "$CYAN" "Saliendo."
        return 0
        ;;
      *)
        log "WARN" "$YELLOW" "Opción inválida. Usa 1, 2, 3 o 0."
        ;;
    esac
  done
}

main() {
  local py
  setup_signal_traps
  py="$(resolve_python)"
  if [[ -z "$py" ]]; then
    log "ERROR" "$RED" "python3 no disponible"
    exit 1
  fi

  if [[ $# -gt 0 ]]; then
    case "$1" in
      --install)
        shift || true
        install_from_termux "$py" "$@"
        return $?
        ;;
      --repair)
        repair_termux_repos_and_libs
        return 0
        ;;
      --local)
        shift || true
        ;;
    esac

    if ! has_local_install; then
      log "ERROR" "$RED" "No existe instalación local en: $VPN_DIR"
      log "INFO" "$CYAN" "Ejecuta sin argumentos y usa la opción 1 para instalar."
      return 1
    fi

    ensure_deps "$py"
    local app_status=0
    launch_vpn "$py" "$@" || app_status="$?"
    return "$app_status"
  fi

  menu_loop "$py"
}

main "$@"
