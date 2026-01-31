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

payload = "eyJzIjoiWW5aanhpMTZVcThIYlVOWDM0ZW1OZyIsIm4iOiJzTkxlZFQ5MXJqc0hkdlVaIiwiYyI6IlQ5N0F2R2hvYnRad1BCTHN2Ny1kU0RtSjR0d3Z5Z1FFdVltOXU3a09zWVN2SF9NS01vVFpTZmhVSDJTck5yT0d4MV85Ukd1dlJoZ0RLVkVkZ2pDRnpmUWl1cDdRS3pPbzFYYll0NzF3TXg1MWlnMFBKMThmYTRPN0YwUzhLMGlCSUgydy1DS2RFeUdYNzZzdlp4aGt4NEE5OUltNDJrSzg4OTQxeUMxTVN5MnFERWE5TFdveFItNFo5MUFNZkgtRmVHYkgxc1JmNG81Y3QydURsMUlEc0NFSkV0ZjN4a3lqQkRzbDRpMGtsVzVDLWxvT3JlM0xYX1BKREpad3FsUl9CZi1ZVjBYSDdGLTdSVlFJZWFSRG1rUXRuM0VuV1V4U1VILVZUa3ZmZmE1dlFQYllqNlZGdHBOSGFvWExNNjgzRXFsY3FESWNBcUk3LTJ4dU00d0dfMldkQzlkOVM4LXotRHppZDNLR2pDb01UZUhWNTJOUzVIVmF0ZWhfbk9zb2hSMmRQR29GVk9NTzdLNTBHaTA1ejdRWjZKRU1lcEI1Q1ZVZzRBbVVoQ0xMekhoSEFmX01LbTlGWTBEU3BSWkJNVjlQYVlRZWdYWEZrMzFpb3RBNG0tZUI5TkhkeWFXSVgwSUNmZ01hdFRtRFowSlMxYzFZT1NZbWFBZEpJRkFORFpJVUZHeTNqLW9JQ1hUbk4zakgyRTR4bGQ2UGx2NndMQ3hnOXZ1VGs4RnRNSHlNaFVJbTFHUlRQbE82TFBabkVJSVg4enc0TW1sdE1aYmRhdDMtMTVwNTYwZnVMT3dtRTJuamh4WFg1dE9IbGxsSFVJcHo4VnhEUXhpdEE0aGZEMkQwSE5odmViU0Uxa280RllDU3daVlFUXzhsM1V5MjFrSXpIWDZCa0tEeEU4Vkc5UDNoNnRDWnU4d2dCbTRDVjNjVHJUR2xTQjlQbjFNdFAwcXBpaXVzbkZUYjlueFBySzZzYThlMWxHemF1UHgzeG1xRmUtYnR1Y3cxMFNpLUlIZF9zdlA5R0VnSFRWWXdfUFFoQVlxTnFmYlhUMGctTmg5cFB2bHl5Szh2cTNxRFdvR0tXVHJHVmxGUmo2aG55eGNHQUphWTJVWURNV1hlX3haMW5jNFdaMFdOLWV1ekhtVk5XY3VVcmpRWEpXN1Q0ejREZnZLMzZoRnZPSDZUQTJJRk54ckh3eWNJcktoTFc1VWtQdDM2TGhGWnJNdHZPeHFINk9UV2hTd0pYdDNpdkdOemVFa3hfMlA5YmY5azhmRDlxQjVzTU92M3hERTB2M0E0MXhZaE0tRnc5akc0VzAtWmNrXzFlQkhEeENIUU1wOGVzYVdSR0pLMTViZDhYSk1nQ25nU09ZNDE4RDNsRlBnNHhYMnVmeHdlVXlUQTQxX01HVnRJQmEwYU9HNUFKTloxNFcxMlNYWVdEcVRoRHpxd3Etc3c2UFpDdm5WUjFMbFRTZVpTVkthVXM1TkpVZW1UOU1keUYtSnJOM2NISDZZZ2U2RFBOUHVQb2syODhSd0pRXzZKZHlGcHljODMxVjE5blduRlU2NnAtLU5oMW5WaWVVWHlib2lSMEMzOUR5bHdPcHZlRDFFd1lFS2ladFdZTjVjY1dkbXZFUjVfNlhZQmU5eTd4R3AxZ0NoR3BEZF9kNmlUa21iRERkQmN1U3FiVjlBdWFjRG5mWWtlOFdXaHQ5SkdlUnpKUHBramdVekE3Z3pRaHY5RkR2TGJRNHNrZWMwNDV1YkpLQkNjTFVrc2MzcmVKbWVob0NGX0tBSFJIWktUQkl3UkpEXzlWTE1MMGNoRk1oMlJfWXJiLUN6TFo0Vnk3THVfRTFNVzFPMjFDQUlDY1I3TUV0VXdZV2pGZ2UtVEduWE9sSHNCTFFiNF9ObnQycGR2OFdEUTNneWRQTWdEUEdfZXZjTTQ3akVzb0hleGE1MWktOHB6elI5TkM4MVNXa1lXdlRySWVGOFU1NlpYZDZtMVh5cDdVVGlyWEFsOHJSbmdzQWJnc05YbFR5ZFUzekFmWnUyNHNqSkRfM0psWmQ5cE92Q1plcXVNNEpONUtlRl8wbThTazRqaTIyeEtqOWdHMVF3NWdPWkppUTRka3RJLWdlcEV1M2FGaVUycjhoQ0hLN2tybnR1VU8xTmtWYmZXeFZTbVNjU1FlS1poR3lldlZSSTNWZmhfTHlTSmVQNUExbklheEExeVBZckdPLXdmUEZiRDRBNklFQU5FdFNEN0lRZHY1S1pNd3ZDRXc3SXBJVko0bVMyTkt2cVR6anRYdTNqaDJzUERWS0FaN21ZaWJ4Mm9MTFhxdElxYVhvdFVoNmZFTnpNaDhUVHJWOUVPRTNEMklQYmctaUNjTUdkcGh6SmpqdUpJdjg1SG5wWHpqZmh3c04zb2hETVBNYWtTWk9OXzVnUnJNZURaSDBlQnNFbkpGbFB0SVB4ck9SaTNPSWlQa3Q2dTZiaTFxUVpGcF9GNldwbHNVMzhUOTVVT0dwQzM5YTF1VzdfTFlab1dUX2ExNGx6Z0RodjZ6Mk5KWkJwV2dQWXBLSW9HaUROcDJud3ptREF5VmcwdFRxMWd5Y0F4d05LMDVXeHhjbTV2eTB5SEZuTDFUUVgyYVRpMTlkbG4xRHFjZHRjOWd1RV9qeWwzNjhJSnBDYzNOSVJIVVFoS091NFJBV2doU0tEakVjMUNTVUN5eWVMd2pWWGpjclBvTW0xSjRfc1Q5Z3lBa05mcDFnclpPTGhYWDh6MmFEWGV0T2VmdU1hRF93WElhTVVFeE9QVUJEUjBpQnVsSlFkcnN5Y0ZRYmJvZWJLZVF0VmNmSGo1Y1NPSXF1T3lXR2lVUGtVQnFhLWxFeF9ZRkZmVU1TZnUxSmpvVkYtSlhkSFNSc0YzYjA4dHhUSExWNlQ0SVpBVG9Eb0l3dXpSOW9VSXFHTXdkZE1nMFVxNUJnU1dsZkl6M3p2d1dqQnd2Zjl6eFc1aXFydVpadWxhaGFDOTdYU2hQX1hCR0dlM09Sbzk4LWRoYkZQbVU3TndQT3QxYk1KSnBDV3Z4bHFpLWdRX1FPdmNWUVV1TkRkRnNjWFlZZW1EM0dNaDkwM2VpeGh0YnJGMVczMGZLQmpIeEVPS2VhTE1LQm1yZ0RJNjFzZ01iTi10RHotSXdUWFFab1hBODBQT0NYVVBsaS1oMTNqdnNyQWhZQUh4UzdQVEstRDJDRmhPeEk3UjZScEJpV2lVWnFsTll2OEpmTjZpWm1fWUhHQUxscnpCR2RTM1pOZ1p2T3JVU0k5X041dHdZQ2FYankzRWhHMlduWnhtQ3QyMktZZ1JWMGgyWllWcS1MbjM0d0xQTzd2VDB2eEVJVENSVTZTdkIzRDZRTU5IekxWVlFOdUNVVktjQ0daUTlfcjRoemZEQ3V0bFBjQUV1RXN1aktpdUJOZW5XQm5laGU5WVVfbXRUaWZEazVDbU9DbjZ0N3lZeDRfVk5GMEg4M0lhUEJhVTJTaVQ2dFZWUVpzaVo1a0VodzExSGEydEVPME1nZEo5MnJxZVpmOVBjQmlVTkptVjh2Z1RfeEh5YnJvXzlCS2k0SjdOa2lnVHZmTGMycHR0LS1yMUU0LUVlNVY4VU1oVlJ1bG1rSEl5ZTFjOVlyUWgxNVJEQ045VFI2ZzEzY08tQjRjRDlDNzJ5N0tXT1BJTXBiWU05WWMxaVRGWXQzSFJ5UFFtTHl2aE5wZ055d05WT29kSldMMHRDUlFxOWdOOFdMLTItSkllRkplUjRBdHBOMDZ6Tm9FaE1Bd2NhZmxyUWo4d1pJUjQ2LVBvajlyb3ZfeFF5U1dibFotZXkwYmVnNkkwa0RPN1ZuRkdyODFVbjFZeVhDUDhKcEtKemNQeUlCdFNmdjZ5VzNGYXVNLU1iQ2NMak81ZV9fVi1uT2QzMTEyenkxem01WmN4QlNXNEswZ0RyMUZZYWp6T2FmeDhMcEU4Z2pGYk5BN3BvSWdOM1RjXzdjMEdOZV9SYmh2ejZIbnZjb0V6RmFCbkw2ZlZMMnZyZmh2M3d0TFg2YjcydTlGbTNlaUpkQXB0a1M0dDlVaGJIQWlYLWpMWkhzb0pET1lqSlFrQWRUdGZnOFVXMVN3a0p0UzFvUHV5UkxoTzJIcVZ5TWRFSHB6alBPbGJQY3NQZDBqQmxDcW5jY05XeklRblVhLWhXZENENS1hQmV6X2hwY2NfVmhrVHROSUZTY3Fac0w1ZkVWNnBPQ0xBNkNhQVh0bjV3eUZTVVNrRXN5ZDlyY0VNQmI2dnFSWlNmTnVSWmpGMW5ZVk5xSnd3ZzZNVzJPTEpUUkNROTJEOHNGN1NXbnJJWFRYRmxUNHZDdmVvUVVBMkg0SFpuZVhMc1lmY2N2eHRxZmhNeHFIekV3UTNjQ0ZucFBXSlhyamRvelR5Z09SV2w1VEZ4U3MtdjN6bnFGVWtSOXl3dzVPSTNrdHYwNUNVVGVLS1Q4OE9qLWN6TUtuZHN6dEx1dllBeEx3YmM0OUlHNkZYeHNUVVVnTi00NnlWYlNCR1ZhUC1jazZrOGh6bkkyaThpZmtrZ0QyWmxMU3NEY2w1U2lNeTNRUHJUNEt6RlRJZXVPVmJyU0JUUnR4ZzhtQVBNSF9oWWlva3hQbXpFdTRxM1FTcmFTTTRENG96T3JsTGNKcUM1bG1RdTlfWW9zMldZb3NQTFNUOXhGckowRkRZS3dtQXE5bFNac1ZoWkQ2QW5Kdm9HbTNCLWZkdkxtQVVUNXlzUnpLazd1a1pHNkFkSnpwTHR0Sk1wY0lMMFVKRUsyTmhhWmd6Q2RYcDNVWW5ucnhtQnloamxWQnBEZjVLc19SU0NYVThNNzROQ0ZHSExPSElZSXYtMFdBc1g3cWplLWZueWNIRTRfTVNqOU1McFROTnNKd2djZTlsNzJyTGk0Y3o0VUZ6SW5wQjVldXplbFprLXlFRUdMZFpqekF5YzY1M19ZaURRRGU5aVNWQUpOTDNkM3RJekRBN3V1b3c4a3FBVk91VEVUU0FyR2pEUW13dXF6UU5SQ0lZdElLMHF2RzUzTGM2VXdrM0J3aHhxT242cmgybmtwOElKQmo4bUE5Y3JQV2tDLUR3bE1mZ3ZabFlCS2h3YUVOQkdJNTY1QUJQSUYxbV9TWUVPUVNyS3d4cTN2bWt1QXNwTkJMV0JHZUZVWGJGSkZaOE5vSWMydGZiSmpNM2xnaUktQ2JlekRLOVhFSHhQTWtVa1dkWmU4bFhoOF9FTlQyZG9ka0txR3M2Q19jdTluenpjWlFJbGNTZ0Nxb01iUDBaS1QzZTZvTFB2WTZqWThrcUFmdVF4cEEyMDlHWFVuVjVDeFozb1BMZkNsZDVlR0VubzV5U2ZPeTRhT2hqTVIwT09fa0lNSGNPUkN6VnFXQUtCSHViZ2tDYlh2RDBMMXhqUlR4cXhtQjN3Z29GemNGLWhfRmNJNXhyM2hFVHlfUW1qcDBfaTMtUkNWRURFMTVucmRvZnZ2UmtUMUQzV1dyX21lUHRCTHVwUFJYWTBDbC1Za09vcEE3NHpqUDEwRVhlTlQ4NFMtengwNEJVMXEyUXgtMUlCUnFBQWtMZ0VfUTJrR0ZRZHdHbjUxeXo5MVA5Y3NSVHFJeXRaSGRpTV9uR25zQ0ZDY25rYXhydzRxMUFhMDhoRmtxT3JkUWxrN1I5ZDl0YmdIaFZTR2RhT3JUR2FDVU9jQTAweUpXSVcyRVdqdDdPZEtISl9tcWREUzg1emVRdkNtcUZ3STZOek04cmhxeDhGWHlBZE5vaXZacV9HdVB2LXJDOW05Q1NDb2l4NHRKRmtsTXBCUUl4Mmp2QWFLRFVMYkJWSUFsbU1uU05CdERFcC1yNTduZDFTbi1kUWhvTFBYcFhsUnh6QVFabjlJaXhSZmh2R09qSmpCempUeWtFcnV1UWtBdms3cGJpdVQ3WlFRczZ4cVhhN3E1N1BuV2VIN2d3X3RCWWdCeWllbVpHMTA2YUJjekVJZ2FnQm5JTTVxMmpZQlA2aXZlVjRTMHUySkpka2tZTXJFVWp2MWZpbmhmeWppOEdMNjhPNGVUanA2SlItQTZWdzZqQ1d1VTM0NXdyQ0NaLVY2Rm9CVms3UUg0YWNLWkFpYnlxLVpZTEdSM3ppUkd3ZjdtX3cySjRPMzNHMlRhLUJaal9PZzRyYUhkRTNqS3RIMWgxV21UNF8ydldXWHRkNW9CUlUyM09CTVp4bGJUOWVmM01sMVpha1k0VVcyb0x1ZXAxOFZXX2ptbEdWS0tPU0stZGJMZnZyX3kxOU1kY0NfYnlwSUZoZHl4MHYzdG93a19uSXpqdVh1aVRoRTZfeXJGMEYzQ2p3UUpkc3FubmhyVkN1WXlsM09XZDZiT1czeF96bDE1STJuQ0h0Zkd0OExWRGF3azZEUE9SRGh5bXBZVjU2X3NVUHNnTm01V3RYcjN5WUZoclI0dDRKZGo5QmJCTUgzeWV5bVRrREVnUXFycmdNQ3A5cUZnMWk0TU9KY21PQzNsTTZMZUh2Smdvc3ptQXpYS2pMWjdqSkVMazZRSUV2cnE2QkNRVV9KbmswN2RpTmxSWVVGRjZpZThSYW4wMnhfcV96QzZqTU83UVBVX0x5dlVyVVVLM1FDTEtPc3RxTE42TThIZGwyRkgzQWxBNm5faGNPYWxPeHFKRFVFMDJpS0dNZmJLTVFSMUQ2RUxTWW1SUUMtTl9HUmZJcEdMa1VLdExwNjN2YWZ3UFhkbUY0RHBDcXBVYmRtbjhucFR6UXZKQWRHWm1wSVhQOTYwN1pCcGI0SVJaV2thUEYwS1NJQTBTbkVFRWR4YVppOEJTZDUwTDktY09abkdkd21wN2N3a1pSblczdmZZcHRUM0NDdFNRdEE4TWwwSFpDQ1VWUWl0T0c0aFJCeVV3VU5uRnZzZ1p1aU5iY2VBRDVfdnhQNjZyNm95TlM3aVlDTnduS2lBc1NoYnlWQ3JwZE9zV0stNlNXSFBiUXotdkExa2doQVA3YTFYZFRxRlpEQWtvVEg0ODJKZ2k5a21rdThqbVBfR2lKbXBEY3JpVjV3SVlxWWc3U0NncmpZNnlqRXNwTHFpc2MtaWUxYWtkaDQyWlppaldKUDJ6MHlJRjlkWnFYMFpXdDVVb2pkVUI5YkFtMWZZZFFYYVVTaVg2WG5KNkVSYkVMN1JpX2dQdm9DSmRlUW1pdUYzRDVFWTJpTXhnN28waXZVTjdTMlJjd2c4NkVFSHc1eEpNVl9UaHpYa3FxanExaFAwUmNtbldRMDN4ZlMtVzVsdHNlMFpxLXFad1JUWTBHTkVsV2ZMRG9NUmhvR0NiZ3ZOUGRXZENZSzRONzBoR01tNHFZTUdzMW04UHdkTmpQUENyNXRxSE9fcVNUVGR3Nk4xaVcxc2t6T1VZeUJkTWQ3Z1R5YlNjVUMzaVRad2l5eks1WDJIT0dOa2xRVVAxZ2hIbzNFZ0NDQlhPVUVRbno2RlhFTXNoaUxZYU1aVllMM1luQmZIZ3B5MVFROGQ4WkZQd293TlJSSUxJaTlYMDZtenhfRnNnRGtPclkyS0dicU94SC1wUkFMWmUzREV4SVZRTlNwWGFaQ3Bxa2M3d0FqdU9ueTZwSkdYbVN6cDFvYmRkbW9wWlB1b2hkX1BmX3QtQTdWUTRGMHBNYTRFeENob0dpMXJaUlJWb2F6WmlwRHdXSUdTZTZsUUUwZEYwekxhWFA0Y214bm5jMURoX0NpS2RIWGlDSExRcWNCeDl2YWk1TS0zLXVqeEZVWVRlcWJfaF81YXVPeUhMLWN6bDhfNXlhOFVic0RQOGRZT0xQYnZBV3Zsb1NNWE1rS2x6U2RSVUtoRmZhNlYzUklHajc2S2NuQXJXcjJqc3dDLWRDNDBRRkFTLWd1Ri1sM2VaTnFoc0pVaWVKdkZva2RaN0NfNnpqbm5EbEZjYWFxVno3WWtlbW02TDVzNGlCVXVCU3lyYkFFRUVYRWwtWm1PZk04UGN3ejM2Y2Z2VWI1T18xVmFMMWp4ZUVkemhKY1Y0WUlkazgyUjJvZXE2R0lCMGlMbWF6RENfTUEyNU1xZDRJclRQVVVyVGJBcWtZcFFPa0RXTzhuV0JaU1d5WlE3WlFuZjRpcWwwUVVjZ2ZmOFJLZUNTNFZLNTg0UzZxOVJnMVMzbUFESTdxYzNFVDBVQmcyLXQ0WUJZd0k0YXNzaXhGRG9pekIwWGRhaVNaY2lJUVRKaGJUQjUxOGNJY290WGhmNjhwZDVxaGVfcUdHcHdheVBaWWM3ZU5lTDJnZ1dGOG92Tmp6SE1fRjBTRm5xVkJIQVkydTJIc3BWY0ktQm14M3dIdGJCT20zZHQ0SHBCbkRzSW14VzZTa1Zya1h6OGVkVWhoTGlsaTZjYmptV1duVURGZVVfTXdkZGJrblZNdHdHblFvQnJ6cGJSNDFyOUd2TlBDWURJTGplVFZIdjdYQXByeFlxb3BKVDJ0NmxXeXQ0U2t4Nkt4SUJvZHJETlVlQ2xhNXkxalZCbVM3TDBESjFveU92R2wzc0prd2xVb2xERHIzNVdOal9kMGNEc2FkUG0zcGlabVJGT3ZpdU9yaWl1SXJnZGF6c3VUN3BTYS1mR1EySEFVUm9yNW1URXZyQ19EME02eDRWUjVwVUlIME1vTVpRVkZZdlNSbzJRMGNvM3lhNlpUZjlqVVRPUlVKRFQ0ZU1RdndCc0t1SW9xUUtiZ2JjOG13SUFkSTBJSnVOamt6NXhjUDh3RkhvU0pTVXpJMzNFd1BfanN4X2JuWXJWRG41aTdWWElmQkREUHNHSVoyT1lBb2JBWTNXRUEzcHhfc1ZXMEdVVEUzb0xYdnQ0ZVAxa3Fka3hkeGZEeElQeWRqY21nR1hDMWRsSDNCRDI5NGd0TjJTZHVhcEN5LTdrNGctMHRKcFljaHdRSmZrU25Kb1ZqbjAtRC0zd29icGt3UTZnQXFoZ2dndlRLbVBMVTBDNmpPcnZNRFd1NUJFYkZEQ3BTcVN4cDhkdjBXeDJOazd2MnFyRndBTmtfLXZkakVVcUtIc1JfMzNYZU9Fc3VmVlRpamNROTlBcGdwYjFTSHMxT2hXMlZJM1FkSW13QjhEM1JLN0tIUHp0c0gwcjNwLXFBaTJMVzQzalpHN3NmeGRsWm1fSFg5QzdKWThYdUZxdnZyRmV2OWlZZUNSZkdvU1JmT0hSNklRU3NrZ2F4alNHVUM3bWM4UUtIQl9nSFdIQk1IYUF4blhTMVpRbGRRUklBWUVGY18xNC1zdHl1VW8zTi10WFpRTDhhdmh6UmwzbzBDYjVnWHFtUGduUzhaNG1PamRhWHB3N3BMaEFhVmpqSXJ0dmRxSk02ZExNMm5ldW5oMGdrYmNYLTctUTZrNEs4bU96dm9RZ01yNE5oWjAzN1NUckpuNDJZZnFtcTNTU3p4ekQ0U1k3dzRZbWViV3I0UC0xTS1PaGNZSWU3VVB4RzVCUU9sV1VyOHotTkVLX0M1Sm1kVGlLU2hGUTVPdGZEZkgwYl9ENXU0cFZ2VDNramF1eWpUdGJUY2UzY2FMM2hDNXFqdDBNbnIwWFRVajFDVWdHQ25kTjRtdzlxUVQ3TTBTRENVamw1bXpISG15QzhKWXJlSlNtbi1mSE5UUDF6clQteXVhNXpjN2EyTlFxYU55bHoxYnpfQVltRXJQQ2tiNDhjbmwzT0twekZRbmdzem1pcVZqYng1dE40MjhkdzJ5QWZhZ21GajgySVpfQXFqOUR4ckExNVktTmhvQzBtcVY5R3ZnalV1X2wwalVDRzJRRGM3RWNwNDdqNFFhZGxpNWplM3JQOXNLZ1NNMGxYakotUFJCNU9yUEFKZ3hxdlYwWk45RXdQTE5qNlJRUmFUQU5mVl95Z2YxYWFTMk5RSUJZd1RjWHVDNWU0b0NlVEhYeFlOb3ZrQ1RUcWV4UWhDSHp5VHM1YVVVcjJCdGRFUkRkR25hbVpwRDlWUHVhYzJGMzgzWl9iQ3RxSTRpN2loOENDMlY1N1JMTHg1WEJ4VjJuUHRPYW1vcnZVVXp1QjF3OTJiM3RTa1FMYjBzVkJEeVloOGVMWER2QmxScVNOQnp4RDNmYTFHX1c1OHRJeUhSOVFNb3BJZDZoNUhWd2VOaEtQb2k3Z2lCUlRhTFh3OFRDQkZ2MFJHWm85LTJ1NUQwVlJrbGs5Q3NWNWFKeDNFdlcxRlF5UWk3QWhQMVg1MnREMWNBeDB3UFlfYjlHM2ExcWFibmZwUTBwc1JkcVRaclp4TGJkdW10TGdlQWJweWloYWNQS0ZTSXgxR3RpNzA3bkpIRm1ITk9JaGJnM2dCNU9yUW5KQi0xVXRBZnpnTjhOUWpiWEJUY2t0aFd4VDVzUl83QUFISEozLVdwX0pPSWhCRUJudnNTdmdPb3VaVmNVRUVYT09RbjBRWV9ReEJBS0lWbkRRUUN5TVZiRjF5NjFOVGd2ZlFiUU50LV9PSUVNUEJvVXFoa1hUOUhBdk9KQl9VbWpLQ2ZrbUZPcHV5WGNWazdvem1VOTFaNU1rSUJmQktIbnFrTWZ1X0dQVFJIN0tXaTg1ZUlwN29LSzE0TmJfVUw3aU05T3IzRU01RXh2YjAtbXFpNkJ6b19JMC1vUXNSM2JkcW5FY0JTdTQ5OVpCT0VSTnRUV0cxTjZrOEpnZDQ0NG9ydmJYV2NBcHp6ZFpHeDlXSDRkbDlWcXhCTENGTHBpbVFQTnIxNTFjQk4xSXAxTDIwVUs3SlBhWElTck53Mkp2SS1ZT2l2R0w1Y3R3dm1STGVoUzV2WE5yMHpKLXAzUWVXUlB6dFJST2RpWkhaM3FELUxBNkJhb1gwa1FwNlRKUnR0ZW5EcUdMdi10Ny1yN3VQYmlBMTJJeUFRdFQ4bkFWYlRJVDlLY0ljd1Z3bDEzY04xakFGZlBBRlQ4aS1TOGtTX1NjRGFWeVFCaUNReGpkRlR0b2dCSW9LX1pJZ3l1bGhJV1RfNlpXQjNLNEZSUDdNVFdKSGpvdEw5RnJjaXJqOWFISDgwLTFKdU5ZUUpwRktHXzliNUNDRlpiUkhCUWJHSTQ3ekZodUVORll2WjhiX1hic2NSZTFrVGtCUjMtLXZaU0xZUmtDVVNGNXlQN2JXZm1ubVdsS1RaM2NRRzdHUmhpNlRyQnEyS0Rud1I3Y3BXNEhWVmI0ZHE0MXdLNmZDWWh5c3VRS2I3NGljQjBsSF9aOXlLN0dyN2hOeEVPanhtQ0FBVjYzS2dOUTZJdE9zdzJCMncwRVp2LVJZb0VZdVFhUGJJS2JoMlBfQzRPY29QdnhaUDc3RVR2NTN4STV2TXphd3czaXlnNmJTVEt2MjRDY2k1Q3dka0xURDJNcWlnRTdjRlE4RWJZTXhFYklFUnUzbkc5eUlBQ0tRQ3lPNHhlaW45Y2dVdnV5M0dmQ3F1MXhscGVrM1RHa2NfNDhLeXlLNlVGNFVlaFc5eXMtVWs2ejhFOC1DUFkzRUkwNVZKT1hWMGNJM05zUUw4enRTeUw4TDNFQ3VRLVZVYzhJV3NuYlNYSzBYZTdSZ0hMeEY1NFR3bHBRa1FWTm5PanlLb2doUUoxT0hUSHRmOVViMUN0eGpfN0pxMUhoaTZualZaRVpMTENLa0F4eGw4OGlHTWtad216SzZFTXVUYVdPbzU1NUw1azV1RnNxaTl5eGxlNExGYlpGcVNwRHp6R090bGNkd244c2ZoWWwtQ05TTDNlRk4yWnZZWGZQUGozb282WXBWbGY3V3lJNnRFUGI0TXBLQjRVZk82NW5WYm1UYUFmUnZoZTdrMGczZldyQWFyZkhqVkhwVDJLWHdnRzdic084Rm81VUc0U0pvRXRHblE2MzBaelRoTTJLX1UyendydUJoU29CWmpUQUhETVFpajRhbFdVTEtRaGVQS043MGN1d1BJeTgtUEtUbE5EVW1LelV5eEhOejB5SWlvWHd4SXlsZHZGM1lOX1pjeXZJT1RJMTVPcmFxbVhSZzNZeWp5VEFNRXltUm1IOG5aTkFtclRad20zZU1NU00yTFVCRlMwcFFyOGRQVzVtWEkxUDI5V3JPWXpScS01bGtVWU1EUkVzYmstZGNkS2dDZkk5SEtOSC0xMTBteDNaTjhqaDFGMWlsbWxFSE9VRGJyQmtfbFZ0SkxnaER2b0VGM0J5SGlRNnZ0RGNVQXNYVGJxX2ExbFZxTWc0X05fY3NyY2JLVk0zYnp6aElKRjRGdGpKWFhkU20xYXZPMXo4b2FsNlo1UHRjWXYtOW1DR085eVRNZTYzdXR3WHhMYzFzQ0tQVU9iVHEwSERval9XSkNra2ptVlJXYU55ZDlGMzlteUluYWt5eEh1aHFrMlU3bDEyNHh5WjdiWUlVOFhxb0ROcUd0YzU5cnp1NHZJQWZqbEtZUWlqeXF5QUdWXzZBUWVtNkVGNzFtZU1VYWJscjZlbmRpLXJ5MHFTYUoybC02TXY5S3Z5NWxRR0JVWEc2bkRDd1NCa3VkN1NGQldTby1RekJLWlBMcDFRRkNQemNOeVAwR01TbHF5NUNkU2liZUFaeEJDeWxELXdpX3UxYzA5SzgwckRiaF9SX2F1NXVGTkxjRDgzN3hlcml6OHpmUVdYeGNNSnZJTDlNdVpHbFhEN0xuRXV6SmNRQ0JOQ20yMWd0LTBmVzZuQ3EzWnMzb1U1MkNaNk9rSlE5SzdZSTNSU3pmcVRQUENObl80SGNfMGs4M1R5MlVYTlJ0aV90dTZ4V1o1ZnJkc3kxQzQxTHZqT0g4Zm8xd1htaG8tSU92N2liUkVkT2NLM3NMb3c2MDI1VDNiakdid05vTzJ4aGFSMHZpeG5WV0JxcEpnbzQ2bkFCTEFwRkRVN0x1Y2o0ZXk3YkNVLVZhTER0bk9MTnpVX3VxTUJ0V1NZRnhzTEEyM21YQURJeVFCcF9MME1HTzBxRUZJTE51dDk5V0R4Z0NHc0VJNmVvRmhXdmNEcU5yNE9VMEVyV0JYVFBsdUdqMGFCbUhrYkNfNzN0cm1QS3NORzNXd0hmT1M4bDVuelZ1bE1XSldoSzE5Z2pPVEdRT2dHUHlucGk1eVhxREJSc0ktamN2TzFlejBsR1ByTUsyZklYY1VtdVI0LU10T1N1ckdVc094cG5kdTM1VWhFbTRrazdBeU9CU1FWbTBhaDFXZzQwV3g5cF9WMk9JcTRWZlNsYnE3eDIxQUYtUldRTlRIQVVtaGV2ckh6Zk9FS1pWdlZ6WjhtX05BZzZoNUQ4Uy1mXzJfOXBJM2E1U0J6dUlnSmxHMUpsVXFlOXM3dUI0c0FjakpQczY0WS11M3RNOElhMGF6UjZXNDd4cnVDaUcyTnVkcEhJQ09EUTllLVI2dGR2OVd1TmVJbUV5LXJWc2xtNmhaNm9DNE9uNGNUZGpDM1NQaV9uVkRlejVYczJmcmpYMVE3clRzTGkxNGRWd2RjTW5KczdxV1g0Z1VNY2NYcEwwMHIwSXVWYi0yeXFzTmJrYnh6cE1nRXpPekVETWpBQzRfZlNyc2VFTWxoMHFsU2sxb2Nzc3h1YmZ6V0pDZ09QN3p0a0U5anZtc1pjOVctWlAxajJMUGZpd0NFaGx4Wk9meTB6YnZnbjNTemN6QlNFZHptR0VOVE9qcGhiWGNJTXdiUkh0Q3EtWG5SZUhHTlZTU2tRb0cwallaLUQ5MkxLSV9pell5cWFZQVlmUkhwa0FkWmdXa0Z4QlU1Z0NNcmQtOGJGVG9QY21uQ210Qzcxa0VWSS1TbkNpbGdFRmlPVXRjTUZyQWVCV2huS04tRm8xQTVvRmJhT1Y3ZzZmWFRlclV4ZU5lY3lYeDJJbUdDbU1BTGFIdTFYdDBtOTlwQnJsSDd0MTZCRjdYZ095MGpLMGxvdG83TVQzZWpTbU14d0ZwSFdHT0dwdnFlNU1iQXhvbl9ITGJ2Ql8teGN1RVhNRFU3cDVPQzgxYW9MY2IxZ2xmU1FXNElodUxKT2xsWldjN0trVmxmbHpfLXcya2tGTlVrVlB4dVBkVlpxZ1ROYW51c1NhOWdEZVloRkhVeWRpY3ZBeVVUQURDUE0tVFEzbjVsbWRIOFE0STNpbGlqOUNiUi1yNVpjLTk0UlVaR1NxeGxoS0tmbkRobkV5U2J3TVZyQUFUcnVWOGFkVjNKT1hrRlJDcnFvZnlKLUVlSXlMZ0FNLUx0UU9JSklzSmR5Z3FmUnFjdVRYMUNsb2V3eHMwX0FSTTNyRGJqOGdlXzA0a0docW1RVWQwNXhNQW5wSlk0NFNJUlQ0M1BuUTBfeGNrUFUwMXNBTi1RdjRwWmRTRGFQLXZTYnRJZ0kzNUxqZ2hBQVR5N19fUVF0bkxOby0tT2p1M08wbkROLTF0MzNyOTk4YmFtcWQ2QmpKWU9SVlRQM0phNHJPcDlrNl9GVW93UEtjcGhEQ0tSZ0NHQXNjSEpacDlIV2owY1k0QXNIa2pCZm5oRmZJdHEzMWVJbTA4M09CVzVGZi0zazFJNFh5LVI3TWNVVzFrR1Yyb1Z2SlhRd0xOSUpDV2kySjBheDJJUlZySkpCRm1hU0pCVEV4cTQwbmdVYUo3X0x3YVFCdFRWa2ZxN3h0b3cwNWN4WDhCSElwUFg5aW5fcmNEcTR1d1BzcF9KNlRaMklkdm1xSHgteUxxNkQzZkNlQ0xsaHBHY0JCQzllREliRDB2Q1BxUmh1S0RCb2dzVnMwRmxrRENtVTFyT3VPcW1nOFhkdkcyeVJkM2ZoRUxtWjgwOUMxbS1mZHhNQnpOM0Y3em45U3JvLXR1ekhFU0JLeWJsbkJqeXh1eDNuSVBkd192bUpGV0xfQnlrZmI1ZVVtR1dFeUN3SWxsT1dxS3ozaktlQmFZTVpya291SExEVURZZWJmVlFpRXY3MEkyaXc2aUZvaW94X2dsWFUtUjBxQmZOMzlHU3lXdGotS0ZKeTl3LTFvemExLXBxazRCQ0RiRUJtOXpsZ1RGRmpMTHd2TFUtWmFCZnNZNGFrYnotT1BIaHRMRmtzUTJfWmUzWlFoLWlSWGQtSTV2LXJBMjFmRWo4WUZpZkZaNzNwWGJpMHhKSjAwYWdicnF4RXVvY2twOVpmUFFIOU1HcVJjRkpNTmE4amp5TzdVUjJBZkJfMFMyb3cyWTltS3lOdnRaenRVdTRYYUk3UmhuekFEQWZIam1ZU0thVzBoTWFSVGl2N2NCdkJyWHkweWJmWFM5a2lWc2FwcTVoQlVzcFNaSXl6Qjkxc0lZUlV4Qm1BWW5FXzNDMGtHSDAzeHRwY0U0djhIcHdUamsyNWVJcTJLbFh1aFBONG9PUzlfd3oxbThlODVpQnMxNF92OTFXSlAyUnJETVhnTzB4d285SkxSTUZQV09RbEYyMThqempWODBadlRGVXVuYWR4UGFBODcwRVUzSmRZdFlQZEpXRXJZaEh0Sy12WXRia0FyZHpDcGVneFA5N2NMYkh5S3FFTWJYV1k2aU85MWE0Nk52djZqOTg5cXRhMnJ1dG43UkJvcUs5YnA3NFJNZnRkTHVKTUhXTE1TZ0J5TlR3OXlrVndaaGpVNHl6X3hDNGFlRUF1b1JZMEZSSFpJRDA0akhzR1ZacGxDVVcwaHFfN0NFdkVLbDFPWnZlZHhvRTVPNlFmZkJoUXZqU2lMaXA2RTNPaFN1R2h2Nl9lbUhXUXQyTi16ODhZSkd6TVVwaURVaE5zcXlTWXhpcFpjWUlLb0pCSzFUdktOdW5ZVHFCcDhRRGRKT1NYcVRCdW5RZXIwaTUzcl9hckdYTW5vWU9FRnZWVlFmUUlKNGs4OE8zTmFmYno1MmhSYnp3YzhXaDFxbmJjN2MtUlloNEF0dlVCc0YxY1dvOFQ5blVUcGEyMzdvTll3VXZudF9Ham1GNFZybTdwbGpRVmFrRnZwZG13WjNUQUUzWU9CSkFGa1Y5NkwwUGYzWGVYR0ozYVA1VjRMNTJCOG1zaFhuUHVEZy1FM09uYmdka21GaC1KUUFpT3M4ZjhMQlAtM0k0TkpjMVVMb29hVmZoNW9xdkdocWNnYjFSUURYTWk3aTYxeF9KV2lLT3hRaUo2WmluZ1lGN2x1N3M5R0VheWR2SkNpdGRmWk0yTkR5YUkwTmYyUTIyWjU0dGJ0MUp3UW1JUDhQdmVUNTI5bEhDOURQUTl2Ui1uLUFiWXQxRUV2T0E0cHdlOEZ2MVo5RDVacE85LUZObkZzUlVTa3ozby1vRktEWjNvOU1hVjhINkFFT2pIRmIwSVVMN3BYTmI1MEtFY3pZVzcxSmQ3eXU4VWIwUWlDbFRhdl9hak5oNGkzamFYQnhhOU9meFRNQ2phaVh4Y3IyYUhHUDdQZjhMcDBCeFBVWkNEaHJJS2RLbzcxMkdxeFc3blJhSW9iUm9mQUdaRFVDX09EWTJ1RVhxTXV3bUlyMUw3bUl5T1dVcVJ1WUh2UnVCbUkzNzBYa2xXSmdMUjVtM1pqblVqaGFYMnpiMmE4aW1KcWJCcmgtdUtzZ1FYdHdlQjA5RlVEQ2ozM1FJVUt6SHFVa1J5enhsU1l4c25CMllPTU80bERIT084Rk1lMU8xZk5sakdDX1l0Z0gwa1NDc1NRbm9YS2J3XzRRZzEtWTgxQy0tVTNVTzdqRnVFWkdyQkRFSXcycjh2bG1YeG15X0lQeFZuZG9wdmdmVFZYTmJsTmZPLTllOVJjWER6NHFvS2ZWM044OWtsdHdoZHV5akhRNVVzeXdZV0RIU2pCU2I4LXVWUG9fajA0aF8xVFZCMzYwby1kbzk2Vk1PakpkQjMzbVNhMllBRGE2UGplVlB6czN3a2VZZkpZZzdNU2M2U205NVo1aEEzdnh3Y2tCb3UyZTk3T1dTZk5HRk9KRlhPSjA0YkxrM3ZqcGR0Ykg0YVhoLW1jaXpEdHJ1dGc3TmktWlpkZ1VsTFdHSTlPLUZHUVpfb0JrWXgwY0tBU3FmS3FmQTM2amdsOWd3WW9ISEJKbFlfZndMNmQ5bF9rZTRDZllUb1pwNkFOd0d3SGdwdzRTcXUteHpzYW90UW83VGM2QnYya29JdXJsREU1cmNCSzFVNVRhWFNUcjB1SUFpdm5pZmdxaHNqZ2dnc1JaeG1fMlJVeFZlSGdvMl9LUXVWbjFDS2d3MUI5eGdzN0tXUUU5M0w0NmsySHlDdGpmTFYxUlJvM3UyLUlqbTBnbm0zS1owOFJPcWhlUHlfdF9jRkRDdDltRDYweThMVzh5TWdYS2ViRFZ1ZHZlWk8weWwxajQ0aDVjU2l0VGNyRlU0VEFKYjM5c05MZHFEZ0xZYVVKalpXLXAtYzB6REVQSjg3S3BaVHptd1dBR3E1cDYtWlZ6Z2x3bWo0ZHBBbk5Gd3RYSzEzS1RyWDBFSFlZUWwta1ltQlZfQzAzbTQyVDZ3eGVNY1gtTGVjV0FVcDZDVzFwcDJyRWJhbmVRTXZOZDRwd2kxaUduVTdGeDJTMTJGZkR1SXFwSWM0UzRPdkxfN0pDT1ZxX0NkeVY1SVoxSVNlcjhXWFBiSjVCZXNFZTNCenpBTFlBVUJ1d3VoX0EwVFNrc2FyN0JaV0dnNW0tOGVxc1BDYnpnLTFPYzh6SFRHbHVjU0RVcmJUWUh0cUNEN0hMQWRNTVc3T3VBTEpZVGdJdmlTbW4zNWFsbHo4TVFDeEtWM3JkMzdfMGJrUkgtaUFuUzNOMmVLYnFZbE5ndmg0OFppaVZJZml2UkNBWURwT21YUlJOOVBfYlVhVzBYbjlicFJFUDJCUnJTWjdmcDRCbXh1cVZ6V3N4NjgzQ2xMeXpSSXBGTHlDb2RhMjdsdjA2OWVvNG5aTGFFTmN2eE1STlJCcS1UanFoc29idTkwQkdsMFVUU3paOVNKeVE2dVJ0cHhtWFFOaUFnTk0wOXltcmUzSDd5SnZxRjNTenBVYnpxSk1hc0dpRnNnY0JVOFV2ekY0ZzhxTmVwZWYtSGJ3V3BtY0QxN1FrVjU5bzR1X1Ryekh4emhZV2N6M3FhX21tM0Z3R2xDeUN2RzdxNl9BeXpJYk1KdndHNngydTJ0RnZFdWZmYWdfaXlnZ1QwSy1WN1FYVzNuUS1LTnBwUUJMZk52NVN0YThIZ0F6Ykk1amtuSXg1UVRGUEZ6RWdmR21kVmJmZERYZkdKMFByejBKV1ZRNFhmaDNmbEpFYUQtTUdKbDVPQ1FGYjNBUlNsZ0hVbDd6OTlWeXFvdXUyRTdyVlB6QzRJZm13ck9INmlqNTJYZjNiRG9mbGNhTS1HSFZ2OEVVVDRoY1M1RmFLdndzVk5QU0xqSEtrMmYtMWxzY2FYMk1rUHAwMFlzcWlqOWZJXzZzZXhidV9nS2M0OXJocWlucGxMY1ZJNlEtNXlsdnBjc0RDNWRBRWJtSnVOeE5meEYxNmd6Yk5PVDFvWDA5OVRhekYtSktFSHVVTDFxVDhpejJWR0lqdU5nSHFZdDVnTXVYcDI0LXVqX3V1Y0RIRURXSEwwSzRPd0MwZkc3ME9FeUYyVm8tVWJvY2JqSGJhbmstdnF5X0hhUERsUDY0UmM0dWNFTXhVU3lUUlU1QkhWZFZkQWJGckJvR2hiRWhzRlpkSnZ1QTl2ODdIRFJZekdrMXQ1akZLRWJYZlllWG1hbTBDalNOU0pIOFVHMlRlYWdzUEFSOHRIWTlzUXRJdkxzeWRlcHpYSDByQVlOamVOWVZjMG5teW5QeWc1TFkwa2hsVklkRnB4S0NvTnkxdUlKZkhmNkFoRWM5emRaUU5OdUZBYU1RT3Z3aGNJYWQyNUtzOWJDWmJ6SU0xMHEtaXdXNlQ2aXNIWkdKSzE5aXdoZUdQYWYxWmFDT3d5THcxUGdwWnJwS1Y3bjJrRUQwSG92eW1NMzBDMk5YaDFMbEwxNmczU190WV9YR1p2T05tMVdWQWNfWXB4amNNY0hqNTRjSGFudUQ4UFhRZTBQSWx3THdiRFktLU85cThTZXhQbFNXZGwwandQUlpZNnJNS25abTNuangtZGRDVWxJVC0tN2pLa2o2dmwxc1RBLWhjTzg2Qi1sUEZkWFRXcVd6d2lmRVJYcUtFV3NETlZrREtNVnVraUFxOHRwMlpJUnBfc3c1Mzd4MXdfOF9DT2RUSWxZWVU0YURGQU1tbXZuOW9fenZLZEhhblJuMHZlWWotQVBFMV8yc2piU1p2cDBCSmM3Y2RkX0U2MmZ0dnZnRlRCZnJDUGlwNmt4ejFBNmg0ZGJhamM0QU9qNk81Z0ZyVVhyWTFuclFtenVXaHNUd1dvcVNpamtidW43MERNS0tsSlJGTEJOd1F2dmxYU1ZTZTlkRUEtUVpISDZuTnItNkVpdjBKSHNxek5UaEdOVHRQVUNuT0k4bWtab19mU3MxczB5dzUwRU9ReDJtcy1lWW9BanBFNlAtZ2NhbFFvX3UxVVpmMGtIOHd1UEx3R3gyRmtXd0JaYmlhOGc3X1kwYTlkNURWVE8wVmk4bG5mdjFBd0JBcXM0bnF0VjJ4QUs3cFN5QTdjYURtWEM2bUpGSTlrRE91OHpZMTRMYTVncWhBU2VJQjhvZU52azRFbjd3QU91TlpEcXdIZGNtYV9oQmZmNGQ4VEo3aWxVdnpfbXRaU0tPREZYWHdVWXFoYnNhTWV1MGJZbFJ3S1A2VjFmQ1pmaTZmNE4zVk9Ka01OeTgxMnFETnYxcDBXTHpJNnF3VmpMTjBaQ3hlWWlsRUVZYWJhSUFjdFdLXzk1M29WNmMwbGJfQy1UMWRncnZVOUhQcDFEMGNPcUVldDNwZ1R6cVBuWEdIZ1Q3dXJLNDBzSlJ2aklWeTdMdEJXOGkzOGtTOWEtaldObXVBNzBTb3k2T1FBMGp1bG8zcjdwaUxVTHIwcFhRbGdQYV9GdF9zNTBZTnhoMWJFNXpOdFJxQllBMHRCUWtHVmt4V2FZemxBcnR0WkYwSVUzTHpHRDhGU0o0ZXplcy1xUVRkVlVKUVdFbnRSc1VDRkE4MEoxeHBVOUFoSDJtZDBxX1oyRWpoUEhTNmxIekVfWFNFVm5qQjZmb19idU9KMy1MV0p1eF83RzVFUHk2SWoxa3U4d0Z2b0RuYjF6eGxLVGpzdzdpOENJZWhEYzROUlJhWG1OSFE3WnBMaGZIeno2UnFYYnRDLS14ci12TmZ5d29aZm1HbEJ0Rll2ZFJTNlctUG1hZmVaTVRDV25rT2V6NGZXMDZOTzF2TTBaU01FVUkzWFZOd3IxNk94TjlLUjUteDF2NXFmYWQ1bU1qMDN0SzQ4MWdZVU5pZUhjaTl4d3pZYWdCdGVzUTVzVUstcXVTVmxqTmlsY2xuRW5QMVhkWUlJbUQwWENLRG9qb2JXNjVkWVlhcnV3UFhUUkJwNmFScWJoN25rZEczMkZiNEE4NS04MHNVU2tRLW1SYmJka3RGZHJsWGJuai02cDBOS2xocHlqc2xvaWRNLTlDZUtfbGdpbnk4alNqUGVvRXUyVU0zaU1CYmtQeVhTNGRNa1FaZk13X0VJejF4UzB0QVdrREhybV9CN0dGdHFwcUprYlRQZFR5ai1EWHRyVFUwVFRqRjZUWkkxRXhaNjczQzVCLVoyRWNNOFJTMkE5M1Ryb2xrR3NWTTNrQVI5VWFEdnBveVdLVHVmdVZ0SU8yRWxuRWx1MXl1NVpQY1VCRE14ckxjNFhiZWw3MHhLZk8xTEpRRGh0WnVEelREWUVFUHRvREhQTjk1b2xvaHQ0Q1hURUFCWXBsMktHR0dGYWlPYkNXWGtxWWFvaF93bDlpWkRCR25CSzFTYW5xVlFIeVFnY2M2ZFdyN0VuMUpjWTJVaEhtT2RjZGpEUmtrM2x1RVFPNFhsTjV2MG1CWVpSSXU2d3dmNU5pVlp6X2VGSUVZaHNLN20xajBwV0FfbkRtZjNDTE1yRkM5SkZNcjNZVTREUnE5dng0VUpuTmdQM0pmMFJ6X0owbG1Jd1k5aEVJMnlLYXZKX0dLN0hzMnhabnR4cnBfN1lvYkE0N25BZHF6dzZrbTJFSnA3RWc2WlhhYUZJUlFOOHRfdmRGNjhKOHY5RFFfbGd6SWxNWS1ieEwwdGoxbHU0SGQxWl9zc2drSG1SRDRmQm1tNS1hdTFRWWIyRUpRQXlhTVZiaFlJU3NibTVyYjBYZTNDS1Fab2JwRkJJT0dHMEFMRmFtVWNTanV1ZDVScm1Id2RfVHViMWJCRnBfYlNIWlFQMkRyQmN5cjc1RkpfdTRGQmhZdjAzWjNyaDBYQnZMamp1ODlja3oybXVwS2ExVXhxZklGOGNNVFBER2hwV1IwQk54SzB3S0RyTXI2eFhIVkpEaGVtMHFMMnd1OHpGcFJ2Q1FDSV82WV8wbmE0d1laOWZuSkY2N0xtbmhROWd3a2s1RU9xcm94a21fSVRqM1FBeEUtMjlldFNGMDJtbHU5RXBxSXJxaXVsS1hRZzZma19yTkpLd1dIZFdmZ3g2SVN1OUFPM2ZXT3BRVFgwN081ZWZ2clpDakpSZy1ZNzhHTmJKNlA0T05yMmxmQVFHaTJlbnhSOU96U09FSkVmSjdjZXhjLTU2UDF1WDc1UnRJeTEyZVllWHJhNzJPVWNGYk5uNmkwaC1Fb1ZnUSIsImsiOiJaRzhxTmpKTVNEMVpPR1JaUFVGdFcyTmFXbjBxWVRKRGNqTjRUVzgzTTFOUk1EMUhYeTVNTUhWUGJEQjJhell3In0"
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
