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
IP_RANGE_MIN="${IP_RANGE_MIN:-20}"
IP_RANGE_MAX="${IP_RANGE_MAX:-90}"
IP_RANGE_CHECK="${IP_RANGE_CHECK:-1}"
IP_RANGE_ENFORCE="${IP_RANGE_ENFORCE:-1}"
VPN_MENU_ANIM="${VPN_MENU_ANIM:-1}"
MATRIX_ANIM_LINES="${MATRIX_ANIM_LINES:-7}"
MATRIX_ANIM_WIDTH="${MATRIX_ANIM_WIDTH:-58}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
MATRIX='\033[1;32m'
DIM='\033[2m'
NC='\033[0m'

VPN_PID=""
SIGNAL_HANDLED=0

log() {
  local level="$1"
  local color="$2"
  local msg="$3"
  echo -e "${color}[${level}] ${msg}${NC}"
}

is_tty_stdout() {
  [[ -t 1 ]]
}

can_animate() {
  [[ "$VPN_MENU_ANIM" == "1" ]] && is_tty_stdout
}

animate_boot_line() {
  local msg="${1:-Inicializando}"
  local rounds="${2:-10}"
  local i frame
  can_animate || return 0
  for ((i=0; i<rounds; i++)); do
    case $((i % 4)) in
      0) frame='|' ;;
      1) frame='/' ;;
      2) frame='-' ;;
      3) frame='\\' ;;
    esac
    printf "\r${CYAN}[BOOT] %s %s${NC}" "$msg" "$frame"
    sleep 0.08
  done
  printf "\r\033[K"
}

matrix_noise_line() {
  local width="${1:-58}"
  local chars='01#@[]{}<>|/$%&*+-=ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  local line=""
  local i idx
  for ((i=0; i<width; i++)); do
    idx=$((RANDOM % ${#chars}))
    line+="${chars:idx:1}"
  done
  printf '%b\n' "${MATRIX}${line}${NC}"
}

matrix_burst() {
  local lines="${1:-5}"
  local width="${2:-58}"
  local i
  can_animate || return 0
  for ((i=0; i<lines; i++)); do
    matrix_noise_line "$width"
    sleep 0.025
  done
}

animate_warning_spinner() {
  local msg="${1:-Validando red}"
  local rounds="${2:-14}"
  local i frame
  can_animate || return 0
  for ((i=0; i<rounds; i++)); do
    case $((i % 4)) in
      0) frame='[■□□]' ;;
      1) frame='[■■□]' ;;
      2) frame='[■■■]' ;;
      3) frame='[□■■]' ;;
    esac
    printf "\r${YELLOW}[WARN] %s %s${NC}" "$msg" "$frame"
    sleep 0.07
  done
  printf "\r\033[K"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

get_iface_ip() {
  local iface="$1"
  local ip_addr=""
  if has_cmd ip; then
    ip_addr="$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  fi
  if [[ -z "$ip_addr" ]] && has_cmd ifconfig; then
    ip_addr="$(ifconfig "$iface" 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}' | sed 's/^addr://g' | head -n1)"
  fi
  printf '%s\n' "$ip_addr"
}

get_all_local_ips() {
  {
    if has_cmd ip; then
      ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1
    fi
    if has_cmd ifconfig; then
      ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}' | sed 's/^addr://g'
    fi
  } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -Ev '^127\.|^0\.0\.0\.0$' | sort -u
}

get_all_local_iface_ips() {
  if has_cmd ip; then
    ip -o -4 addr show scope global 2>/dev/null | awk '{
      gsub(/@.*/, "", $2);
      split($4, addr, "/");
      if (addr[1] != "" && addr[1] !~ /^(127\.|0\.0\.0\.0$)/) {
        print $2, addr[1];
      }
    }' | sort -u
    return 0
  fi

  local ip_addr
  while IFS= read -r ip_addr; do
    [[ -n "$ip_addr" ]] || continue
    printf 'unknown %s\n' "$ip_addr"
  done < <(get_all_local_ips)
}

interface_is_mobile_data() {
  local iface="${1:-}"
  iface="${iface,,}"
  [[ "$iface" == rmnet* || "$iface" == ccmni* || "$iface" == pdp* || "$iface" == wwan* || "$iface" == mobile* ]]
}

interface_is_wifi() {
  local iface="${1:-}"
  iface="${iface,,}"
  [[ "$iface" == wlan* || "$iface" == wifi* ]]
}

ip_in_recommended_mobile_range() {
  local ip_addr="$1"
  local o1 o2 _o3 _o4
  IFS='.' read -r o1 o2 _o3 _o4 <<< "$ip_addr"
  [[ "$o1" == "10" ]] || return 1
  [[ "$o2" =~ ^[0-9]+$ ]] || return 1
  [[ "$o2" -ge "$IP_RANGE_MIN" && "$o2" -le "$IP_RANGE_MAX" ]]
}

ip_is_private_ten_range() {
  local ip_addr="$1"
  [[ "$ip_addr" =~ ^10\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

pick_range_checked_ip() {
  local iface ip_addr
  local mobile_iface=""
  local mobile_ip=""
  local wifi_iface=""
  local wifi_ip=""
  local fallback_iface=""
  local fallback_ip=""

  while read -r iface ip_addr; do
    [[ -n "$ip_addr" ]] || continue
    ip_is_private_ten_range "$ip_addr" || continue
    if interface_is_mobile_data "$iface"; then
      if [[ -z "$mobile_ip" ]]; then
        mobile_iface="$iface"
        mobile_ip="$ip_addr"
      fi
      continue
    fi
    if interface_is_wifi "$iface"; then
      if [[ -z "$wifi_ip" ]]; then
        wifi_iface="$iface"
        wifi_ip="$ip_addr"
      fi
      continue
    fi
    if [[ -z "$fallback_ip" ]]; then
      fallback_iface="$iface"
      fallback_ip="$ip_addr"
    fi
  done < <(get_all_local_iface_ips)

  if [[ -n "$mobile_ip" ]]; then
    printf '%s %s\n' "$mobile_iface" "$mobile_ip"
    return 0
  fi
  if [[ -n "$wifi_ip" ]]; then
    printf '%s %s\n' "$wifi_iface" "$wifi_ip"
    return 0
  fi
  [[ -n "$fallback_ip" ]] || return 1
  printf '%s %s\n' "${fallback_iface:-unknown}" "$fallback_ip"
}

network_mode_label() {
  local iface ip_addr
  while read -r iface ip_addr; do
    [[ -n "$ip_addr" ]] || continue
    if interface_is_mobile_data "$iface"; then
      printf 'Datos moviles (%s: %s)\n' "$iface" "$ip_addr"
      return
    fi
    if interface_is_wifi "$iface"; then
      printf 'WiFi (%s: %s)\n' "$iface" "$ip_addr"
      return
    fi
  done < <(get_all_local_iface_ips)

  ip_addr="$(get_all_local_ips | head -n1 || true)"
  if [[ -n "$ip_addr" ]]; then
    printf 'LAN/mixta (%s)\n' "$ip_addr"
    return
  fi
  printf 'Sin red local detectada\n'
}

check_mobile_ip_range() {
  [[ "$IP_RANGE_CHECK" == "1" ]] || return 0
  local checked_iface checked_ip
  if ! read -r checked_iface checked_ip < <(pick_range_checked_ip); then
    return 0
  fi
  if ip_in_recommended_mobile_range "$checked_ip"; then
    log "OK" "$GREEN" "IP detectada dentro del rango sugerido: $checked_ip (10.$IP_RANGE_MIN-10.$IP_RANGE_MAX)"
    return 0
  fi
  if ! interface_is_mobile_data "$checked_iface"; then
    return 0
  fi

  animate_warning_spinner "Analizando impacto de red" 16
  can_animate && matrix_burst 4 52

  echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}│${WHITE}              ADVERTENCIA DE RED MÓVIL (RANGO)              ${YELLOW}│${NC}"
  echo -e "${YELLOW}├────────────────────────────────────────────────────────────┤${NC}"
  printf "%b\n" "${YELLOW}│${NC} IP detectada: ${WHITE}${checked_ip}${NC} ${DIM}(${checked_iface:-red})${NC}"
  printf "%b\n" "${YELLOW}│${NC} Rango recomendado: ${WHITE}10.${IP_RANGE_MIN} - 10.${IP_RANGE_MAX}${NC}"
  echo -e "${YELLOW}│${NC} Esta IP está fuera del rango sugerido."
  echo -e "${YELLOW}│${NC} En algunas redes, esto ${WHITE}podría${NC} incrementar consumo de datos."
  echo -e "${YELLOW}│${NC} Es una advertencia preventiva, ${WHITE}no${NC} una confirmación."
  echo -e "${YELLOW}│${NC} Recomendado: modo avión 10-15s, reconectar y volver a probar."
  echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"

  if [[ "$IP_RANGE_ENFORCE" == "1" ]]; then
    local confirm=""
    read -r -p ">> ¿Forzar ejecución de todas formas? (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
      log "INFO" "$CYAN" "Ejecución cancelada por política de rango."
      return 1
    fi
    log "WARN" "$YELLOW" "Ejecución forzada por usuario con IP fuera de rango recomendado."
  else
    log "WARN" "$YELLOW" "IP fuera de rango detectada; continuidad automática habilitada (IP_RANGE_ENFORCE=0)."
  fi
  return 0
}

print_menu_network_warning_hint() {
  [[ "$IP_RANGE_CHECK" == "1" ]] || return 0
  local checked_iface checked_ip
  if ! read -r checked_iface checked_ip < <(pick_range_checked_ip); then
    return 0
  fi
  if ip_in_recommended_mobile_range "$checked_ip"; then
    return 0
  fi
  if ! interface_is_mobile_data "$checked_iface"; then
    return 0
  fi
  printf '%b\n' "${YELLOW} Advertencia:${NC} ${WHITE}${checked_ip}${NC} ${DIM}(${checked_iface:-red})${NC} fuera de 10.${IP_RANGE_MIN}-10.${IP_RANGE_MAX}; en algunas redes ${WHITE}podría${NC} consumir megas."
}

print_access_points() {
  local launch_host="$1"
  local launch_port="$2"
  log "INFO" "$CYAN" "Red activa: $(network_mode_label)"
  log "INFO" "$CYAN" "Panel: http://$launch_host:$launch_port/panel"
  log "INFO" "$CYAN" "Descargas: http://$launch_host:$launch_port/download"

  if [[ "$launch_host" == "127.0.0.1" || "$launch_host" == "localhost" || "$launch_host" == "::1" ]]; then
    local ip_addr
    while IFS= read -r ip_addr; do
      [[ -n "$ip_addr" ]] || continue
      log "INFO" "$CYAN" "Panel LAN: http://$ip_addr:$launch_port/panel"
      log "INFO" "$CYAN" "Descargas LAN: http://$ip_addr:$launch_port/download"
    done < <(get_all_local_ips)
  fi
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
  if ! check_mobile_ip_range; then
    log "WARN" "$YELLOW" "Ejecución cancelada por validación de IP."
    return 1
  fi
  if ! has_help_flag "$@"; then
    kill_processes_on_port "$py" "$launch_port"
  fi

  log "LAUNCH" "$GREEN" "Iniciando Shadow VPN desde: $MAIN_FILE"
  print_access_points "$launch_host" "$launch_port"

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
  clear
  animate_boot_line "Inicializando consola Shadow" 10
  can_animate && matrix_burst "$MATRIX_ANIM_LINES" "$MATRIX_ANIM_WIDTH"
  printf '%b\n' "${CYAN}============================================================${NC}"
  printf '%b\n' "${MATRIX}   _____ _   _    _    ____   _____        __ __      ______${NC}"
  printf '%b\n' "${MATRIX}  / ____| | | |  / \\  |  _ \\ / _ \\ \\      / / \\ \\    / /  _ \\ ${NC}"
  printf '%b\n' "${MATRIX} | (___ | |_| | / _ \\ | | | | | | \\ \\ /\\ / /   \\ \\  / /| |_) |${NC}"
  printf '%b\n' "${MATRIX}  \\___ \\|  _  |/ ___ \\| |_| | |_| |\\ V  V /     \\ \\/ / |  __/${NC}"
  printf '%b\n' "${MATRIX}  ____) | | | /_/   \\_\\____/ \\___/  \\_/\\_/       \\__/  |_|${NC}"
  printf '%b\n' "${CYAN}============================================================${NC}"
  printf '%b\n' "${WHITE} Control Center${NC}   | Host: ${HOST}   Port: ${PORT}"
  printf '%b\n' "${WHITE} Red detectada:${NC} $(network_mode_label)"
  print_menu_network_warning_hint
  printf '%b\n' "${DIM}------------------------------------------------------------${NC}"
  echo "1) Instalar desde Termux (descarga ZIP e inicia VPN)"
  echo "2) Ejecutar desde local (sin descargar)"
  echo "3) Reparar librerías de Termux (repo + update/upgrade)"
  echo "0) Salir"
  printf '%b\n' "${DIM}------------------------------------------------------------${NC}"
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
