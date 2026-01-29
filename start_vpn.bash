#!/bin/bash

# ==========================================
# SHADOW OPERATOR LAUNCHER | VPN SDC SERVER
# ==========================================

SCRIPT_TARGET="vpn_local_server_sdc.py"
PORT=8080
IP_RANGE_MIN=20
IP_RANGE_MAX=90
SCRIPT_VERSION="3.8"
UPDATE_URL="https://raw.githubusercontent.com/Pr3da7ol/ShadowVPN/main/start_vpn.bash"
export DEBIAN_FRONTEND=noninteractive

# Colores
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_msg() { echo -e "${2}[${1}] ${3}${NC}"; }

# --- AUTO-UPDATE ---
get_self_path() {
    local p="$0"
    local resolved=""
    if command -v readlink &> /dev/null; then
        resolved="$(readlink -f "$p" 2>/dev/null)"
    fi
    if [ -z "$resolved" ] && command -v realpath &> /dev/null; then
        resolved="$(realpath "$p" 2>/dev/null)"
    fi
    [ -n "$resolved" ] && echo "$resolved" || echo "$p"
}

fetch_remote_script() {
    local url="$1"
    local out="$2"
    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$out"
    elif command -v wget &> /dev/null; then
        wget -qO "$out" "$url"
    else
        return 1
    fi
}

extract_version() {
    local file="$1"
    local v=""
    v="$(grep -m1 '^SCRIPT_VERSION=' "$file" 2>/dev/null | cut -d'"' -f2)"
    if [ -z "$v" ]; then
        v="$(grep -m1 -E 'REPARACIÓN DE EMERGENCIA \(V[0-9.]+\)' "$file" 2>/dev/null | sed -E 's/.*\(V([0-9.]+)\).*/\1/')"
    fi
    echo "$v"
}

auto_update() {
    local self_path tmp_file remote_version
    self_path="$(get_self_path)"
    tmp_file="/tmp/start_vpn.bash.$$"

    if ! fetch_remote_script "$UPDATE_URL" "$tmp_file"; then
        echo -e "${AMARILLO}[!] Auto-update no disponible (curl/wget o red).${NC}"
        return 0
    fi

    remote_version="$(extract_version "$tmp_file")"
    if [ -z "$remote_version" ]; then
        echo -e "${AMARILLO}[!] No se pudo leer version remota. Omitiendo update.${NC}"
        rm -f "$tmp_file"
        return 0
    fi

    if [ "$remote_version" != "$SCRIPT_VERSION" ]; then
        echo -e "${CYAN}[*] Update detectado: v${SCRIPT_VERSION} -> v${remote_version}${NC}"
        if cp "$tmp_file" "$self_path" 2>/dev/null; then
            chmod +x "$self_path" 2>/dev/null
            echo -e "${VERDE}[OK] Script actualizado. Re-lanzando...${NC}"
            rm -f "$tmp_file"
            exec "$self_path" "$@"
        else
            echo -e "${ROJO}[X] No se pudo escribir en: $self_path${NC}"
            rm -f "$tmp_file"
            return 0
        fi
    else
        echo -e "${VERDE}[OK] Script en ultima version (v${SCRIPT_VERSION}).${NC}"
        rm -f "$tmp_file"
        return 0
    fi
}

# --- VERIFICACIÓN DE RANGO IP (IFCONFIG) ---
get_ifconfig_ips() {
    ifconfig 2>/dev/null \
        | grep -Eo 'inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}' \
        | awk '{print $2}' \
        | sed 's/^addr://g' \
        | sort -u
}

get_rmnet0_ip() {
    local ip=""
    ip="$(ifconfig rmnet0 2>/dev/null \
        | grep -Eo 'inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}' \
        | awk '{print $2}' \
        | sed 's/^addr://g' \
        | head -n1)"
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    ifconfig 2>/dev/null | awk '
        $1 ~ /^rmnet0/ {show=1; next}
        show && $1 ~ /^$/ {exit}
        show && $1=="inet" {print $2; exit}
    ' | sed 's/^addr://g'
}

ip_in_recommended_range() {
    local ip="$1"
    local o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    [ "$o1" = "10" ] || return 1
    case "$o2" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$o2" -ge "$IP_RANGE_MIN" ] && [ "$o2" -le "$IP_RANGE_MAX" ]
}

check_ip_range_ifconfig() {
    if ! command -v ifconfig &> /dev/null; then
        echo -e "${AMARILLO}[!] ifconfig no disponible. Omitiendo verificacion de rango.${NC}"
        return 0
    fi

    local rmnet_ip current_ip ok match_ip
    rmnet_ip="$(get_rmnet0_ip)"
    ok=1

    if [ -n "$rmnet_ip" ]; then
        current_ip="$rmnet_ip"
        if ip_in_recommended_range "$rmnet_ip"; then
            ok=0
            match_ip="$rmnet_ip"
        fi
    else
        local ips primary_ip
        ips="$(get_ifconfig_ips)"
        if [ -z "$ips" ]; then
            echo -e "${AMARILLO}[!] No se detectaron IPs con ifconfig. Omitiendo verificacion.${NC}"
            return 0
        fi
        primary_ip=""
        for ip in $ips; do
            if [ "$ip" != "127.0.0.1" ]; then
                primary_ip="$ip"
                break
            fi
        done
        if [ -z "$primary_ip" ]; then
            primary_ip="$(echo "$ips" | head -n1)"
        fi
        current_ip="$primary_ip"
        if [ -n "$primary_ip" ] && ip_in_recommended_range "$primary_ip"; then
            ok=0
            match_ip="$primary_ip"
        fi
    fi

    if [ "$ok" -eq 0 ]; then
        echo -e "${VERDE}[OK] IP EN RANGO SUGERIDO: ${NC}$match_ip"
        echo -e "${CYAN}Rango sugerido: 10.${IP_RANGE_MIN} - 10.${IP_RANGE_MAX}${NC}"
        return 0
    fi

    if [ -z "$current_ip" ]; then
        current_ip="N/A"
    fi
    echo -e "${ROJO}[X] IP FUERA DE RANGO SUGERIDO: ${NC}$current_ip"
    echo -e "${CYAN}Rango sugerido: 10.${IP_RANGE_MIN} - 10.${IP_RANGE_MAX}${NC}"
    echo -e "${CYAN}[*] PROTOCOLO DE RECUPERACION DE RANGO:${NC}"
    echo -e "${CYAN}    1) PON EL TELEFONO EN MODO AVION (10-15s).${NC}"
    echo -e "${CYAN}    2) DESACTIVA MODO AVION Y ESPERA NUEVA IP.${NC}"
    echo -e "${CYAN}    3) VERIFICA CON ifconfig Y REINTENTA.${NC}"
    echo -e "${AMARILLO}[!] Continuar podria afectar rendimiento o consumo de datos.${NC}"
    read -r -p ">> Forzar ejecucion? (s/N): " confirm
    if [ "$confirm" != "s" ]; then
        echo -e "${ROJO}[!] Operacion abortada por verificacion de rango.${NC}"
        exit 0
    fi
    echo -e "${AMARILLO}[!] MODO FORZADO ACTIVADO.${NC}"
}

# --- CONTROL DE PUERTO ---
port_in_use() {
    if command -v ss &> /dev/null; then
        ss -ltn "sport = :$PORT" 2>/dev/null | grep -q ":$PORT"
    elif command -v lsof &> /dev/null; then
        lsof -iTCP:"$PORT" -sTCP:LISTEN -t &> /dev/null
    elif command -v fuser &> /dev/null; then
        fuser -n tcp "$PORT" &> /dev/null
    else
        return 1
    fi
}

kill_port() {
    local pids=""
    if command -v ss &> /dev/null; then
        pids=$(ss -ltnp "sport = :$PORT" 2>/dev/null | awk -F'pid=' 'NR>1{split($2,a,","); print a[1]}' | sort -u)
    elif command -v lsof &> /dev/null; then
        pids=$(lsof -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | sort -u)
    elif command -v fuser &> /dev/null; then
        pids=$(fuser -n tcp "$PORT" 2>/dev/null)
    fi
    if [ -n "$pids" ]; then
        log_msg "WARN" "$AMARILLO" "Puerto $PORT en uso. Cerrando PID(s): $pids"
        kill $pids 2>/dev/null
        sleep 1
        if port_in_use; then
            log_msg "WARN" "$ROJO" "Forzando cierre en puerto $PORT"
            kill -9 $pids 2>/dev/null
        fi
    fi
}

# --- 1. GENERACIÓN DEL PAYLOAD (Self-Extracting) ---
generate_payload() {
    log_msg "SYSTEM" "$CYAN" "Verificando integridad del núcleo..."
    if [ -f "$SCRIPT_TARGET" ]; then
        log_msg "CHECK" "$VERDE" "Núcleo $SCRIPT_TARGET detectado localmente."
    else
        log_msg "GEN" "$AMARILLO" "Núcleo no detectado. Materializando $SCRIPT_TARGET (ULTRA SECURE)..."
        
        # INICIO DEL BLOQUE PYTHON PROTEGIDO V2
        cat << 'EOF' > "$SCRIPT_TARGET"
# SHADOW PROTECTED | DO NOT MODIFY
import zlib as QIEOxD, base64 as tqCWBm, marshal as jlxVcV
QUibXv = 113
ZndLVw = tqCWBm.b64decode('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')
ePNGgS = bytes([b ^ ((QUibXv + i) % 255) for i, b in enumerate(ZndLVw)])
exec(jlxVcV.loads(QIEOxD.decompress(ePNGgS)))
EOF
        # FIN DEL BLOQUE PYTHON PROTEGIDO V2
        
        log_msg "SUCCESS" "$VERDE" "Núcleo materializado con cifrado SHADOW V2."
    fi
}

# --- 2. VERIFICACIÓN DE ENTORNO ---
check_env() {
    log_msg "SETUP" "$AMARILLO" "Verificando entorno de ejecución..."
    
    # Python
    if ! command -v python3 &> /dev/null; then
        log_msg "INSTALL" "$AMARILLO" "Instalando Python3..."
        pkg install python3 -y
    fi

    # Cryptography
    if ! python3 -c "import cryptography" &> /dev/null; then
        log_msg "INSTALL" "$CYAN" "Instalando librería 'cryptography'..."
        if ! pkg install python-cryptography -y; then
             log_msg "WARN" "$AMARILLO" "Fallo nativo. Intentando compilación..."
             pkg install build-essential openssl libffi rust binutils -y
             pip install cryptography
        fi
    fi
}

# --- 3. EJECUCIÓN ---
auto_update "$@"
clear
echo -e "${CYAN}   ___  ___  _  __   ___  ___  ___ ${NC}"
echo -e "${CYAN}  / _ \/ _ \/ |/ /  / _ \/ _ \/ _ |${NC}"
echo -e "${CYAN} / // / ___/    /  / // / ___/ __ |${NC}"
echo -e "${CYAN}/____/_/   /_/|_/  /____/_/   /_/ |_|${NC}"
echo -e "${CYAN}       SHADOW INFRASTRUCTURE       ${NC}"
echo ""

generate_payload
check_env
check_ip_range_ifconfig
log_msg "LAUNCH" "$VERDE" "Iniciando Servidor VPN SDC (Shadow V2)..."
echo -e "${CYAN}====================================================${NC}"
if port_in_use; then
    kill_port
fi
python3 "$SCRIPT_TARGET" --port "$PORT"
