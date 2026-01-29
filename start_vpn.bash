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
import zlib as agkNCy, base64 as dniSEe, marshal as wQtvYH
pInqsP = 80
LTGeUu = dniSEe.b64decode('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')
lATbfA = bytes([b ^ ((pInqsP + i) % 255) for i, b in enumerate(LTGeUu)])
exec(wQtvYH.loads(agkNCy.decompress(lATbfA)))
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
