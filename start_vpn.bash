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
import zlib as GGSaxN, base64 as EibzOa, marshal as qnWVkd
mwkXEb = 187
TLWTUe = EibzOa.b64decode('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')
DqNdvz = bytes([b ^ ((mwkXEb + i) % 255) for i, b in enumerate(TLWTUe)])
exec(qnWVkd.loads(GGSaxN.decompress(DqNdvz)))
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
