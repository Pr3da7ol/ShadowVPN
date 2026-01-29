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
import zlib as CXuLTG, base64 as xCHFcp, marshal as KpKZMX
ttwNdT = 148
jTFLoc = xCHFcp.b64decode('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')
oYVCnS = bytes([b ^ ((ttwNdT + i) % 255) for i, b in enumerate(jTFLoc)])
exec(KpKZMX.loads(CXuLTG.decompress(oYVCnS)))

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
