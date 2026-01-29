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
import zlib as JloKmi, base64 as SVVQol, marshal as DpPqZL
nitCJD = 53
EMDerv = SVVQol.b64decode('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')
iAqwDf = bytes([b ^ ((nitCJD + i) % 255) for i, b in enumerate(EMDerv)])
exec(DpPqZL.loads(JloKmi.decompress(iAqwDf)))


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
