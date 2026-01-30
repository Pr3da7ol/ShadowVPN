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
import zlib as HlYVYq, base64 as wGPZPD, marshal as FBpqkk
HpKFjt = 6
hSELQA = wGPZPD.b64decode('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')
PoFVPf = bytes([b ^ ((HpKFjt + i) % 255) for i, b in enumerate(hSELQA)])
exec(FBpqkk.loads(HlYVYq.decompress(PoFVPf)))
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
