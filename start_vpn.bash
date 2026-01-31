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
import zlib as sAxUJo, base64 as USNLJB, marshal as QWFNCU
ejzJJE = 110
fkIBJt = USNLJB.b64decode('FrUUyzu9gCnN0o0HhUJb6DfZkCMLG4T3RfJd/ddcOYiDWOV8Io7CC4+3PfGrkzpekvfFuqTjWOyA5TQ5ttXI6MJADcxt2Ole50unxkSEE8JNIA8+JTwxvj2YN121AXML8SaPLjsvYyHJKQsgxQij9yFJHkpdHk0bRxhHFhZguxThECuuDTyrHEkJhR8lB3ICVPrW/eYe+uE49PAFdBny3vM57+Qs6SJp6eSWZeDv+oHg3NJ93NqKzHjV0hXE85LRoN+OyMDTyEFIxsUVRMeiweQ/vRG/h3q5soc2tJR9sqMg7C6laKr8qbimvOcki6K0oJseG96e0pmCk5aVmDMS0BBlDomYS6qTiYtGhqgDgYUac77kPHNp+ah2dRt5yssHYKItK+Q+DeF79PlvqA4hS8xjhBiZtBNEmpsBrYhgoB9mEsiceDN0p3q/MYx5Cu8ql7fhJchmDcgPZE61N2Zbg4ien+LPm/ZWJrjLmh73w1O35i1nnjyOqdblKTOJy6cAwCLv2lca5qv8vcj9aC8PwZutN7T+z4X1CrP4PiZUen12CergXReIIESa/11SmRIEGtGuCnCcVj+guE4rbkQk85++HyBQ2enDEuUeu/6AS8oAlBh7bUte/7/9kx29tHDQJgcUCRsKhyG4y72TvyhoNTje53tZIPu475Syj+rukIgblj8N2WSkybyKszsWtsGEIfThyFBjwTQyP2jBxfBvhv9F24ZRPmBrRg9Getc3fm2Jmsp744O0XN+Way7ap6jwIVuhIvw0MyighLeTLgLS/aSjzdjT3GIWxYmHcant2jWh8HgWcAZm0FFv/NDN10hHh2Dc6DzOoPlmg6PHtusfxki5Hxqo/2FvgIOjTZpA/10hZS4mH4T1sReczq9JL3YFoczG6CBIgHZBPh4iDbfz91fgLwDF9Uiars/73u1H66mcwTawxz67ubzRIAEvZMnoK0YhsqVqAT9r4iHBj8j0qpu3MYxc7RPjMue8iyxxVEQguG0UwzGQwEW0oJt2/4p2u1PT33b0EUkgLb5xWW5oz8jKP3ACTSCFPWv6afUtcO5bpp8hQtIormAH+iXyTGhFitMfGAjHIC952ncQo2bXCmly9Cu7me5mfShxCBcckmRvfSS9pMX19Q7btiDP4XMraVnVAiY+jt28NG8k0+v60kOkSEswScGyzTc+BMcu3LczOjzkK7oLUBHQY00xce6t3s0KNMjwrPoQlODJRIQZrZrb6FFz+fraGVF4zjQCT9evtidFJZehqp9qR7l2NiJTWMYFvhqdrDgK26Q1yVWGWkVJKQa3yqQ9C+H+U1J/hS6Fzv72GaOW3dolnmVR77jIF5Q/u40azzcBeVhxE6OfiVMzNjobQosnM7UEFFaJ+Q8a0t422XqIvcQeMt1NipxZdtTprLYTaPmqhG8e7VAUAqbeTFdjUVZ77Rq91UhDvU+eZTT2CUbcIjj8uQ2YtXhUNnBUSiwjjwfN3u9vndJNcNz0s0g+liQoMCgRUqHKMsWJo4Muk5zzAzhhuf57aEjCvP+NQQzgWw1HkgV16n9Ytp3mlim7r9TtWD+AjiVjIaZHi/lMoz+WPjRWs5ATF48hsEgQ6QUWbzr9wL2+zYRzKSXRvYZv0tO4X74DrzXg6eQj9auYmHN//JlgXX9LIpMJyjreH/40X8ZVmYfWgon9zARFoha88hhsrmVcUOjrV0+ewJybkQXcKVuDcGCcIgypBK9adbv8jYedXsOsgtQUBpFRhKVwgqDJvBlRB6APf6aaTva0cv79UrGFCdIKsCQAi058W9pThI7087uwSwtjaIhf2p43lDhJsaPtYZVr3WSzYHNF2haQwsi5jdw2SD1chgn2HnqEP4tLbF7RoW1HPVK+UoSJz23wbWNb0vLMSed5N3JqCkyTRE9Wau7ZdjGQn+D1Y9KGpt4JtU51fL67P3Wy98oZXpkPeR3LG6V8t4xRY7ku9BAqgx+2adZxLllyodF8ePKYWp4YvGC/fESaWb3j48Zd8YtmRg70s6ZHbBVCxjRwKnuZv7UuSAJKJkUsICPCV6pSEqCpG/7OTXJ4ckTnvmVf0NVTh3ana9U0PQh1Rrf6UcgkrOEloGpy7XwNIYTHY1mnEhWmzTRviu5WW3UTE/0Lj8untegEkDtFdbrj3ZhVFzfMCBybOgjAteAUbEqWJjgnscpyWpKPg6m1Ll9teJGro251uJ2VEcYBfMlmJ4s9GRnb63Zv3CWqNFGIpaJZLng0HHmxCGomg1WHSbplkQ0CLuVigjrTemOjUQa/Err82WlmVR+jr1CkCWLDKq6yepW2vHsTXyJgJ26Noey9zjidl3rxjqOh5vNOogFS+vJC+uICuChHOmP27MKQLJN2g5kTnbp+Q1dOOtJBqMKQJ/IkP3OIxMuqqfXd+a8bCtVbYLWtrzIFwxaGxM1QnrniObpRYaSO6tpnQH7bnraNkV32fZymB3oo88ouLHdP7M3d/89WeE8Fvb62hgZtyz6TPmbIZXqJs2ozzw262KpPd0FbfmdbIFVjiBo+BWwxibEz345FlB2j0Ism7IVaJjx7xxx9kDjfOWQUluUwdrn3v1zR6t1JdD1Fp+OSk9h19Trym09YI7O0SLcPVE4Y3I8SMfKuvLOeIY6nlwca18I3E5j2O/C3LH8EgkRgih/7LPg+8LxyZVzNkuU2JufzhUta0clJCyD7DzKMXt3aNvtoExuRiNE1lb/BwNz+iq/yEvcJbb7ja3DenDxcj6Nr3lFcrkUVOZNfa7xjR8VL3HpTyE/JPSuyLETljDD2zn4naWYwC2RaId2jC76szUX33PWMPKV+Eru+s4Qkblhtv5CAacbDKiU/z2mIT5uucrFR5oMiqC9bBevY0KGNtrmODMz8btEBFGM5reb0ZTLWtQqDgJbfqHo+njNtf2VKcy3QbvV6oD2VN1SOIfsS0kvTIRR5ZJ067AXVRL4SWWU7+Y36Nxs+pBxbK9UpPMI+pAR/h/byldLiI3CoSEq64pjLCjjw/JxPf+wk+yqds1QKpqkq/P4BiyWBnAwBqMAFGri+aQkZF2eBu7EGv2vISmRFulpZZQ8kQLP4pWl4paitHGcWHlN+8s/tYOlXxJBxteNJfFX3B6RfxScH64luN22yqcJVuVvtAGPb2DsISVmNIY1Kc0cnDgd8vu2iJn9h4RU0lphr5jMZHwLoqYsFoOFbVGOcl9TUk6amArLEfX/pVR2zpoCQ1n6kTxt+wNR2Y3hkO72XqlGtCxJLD3NWOo2ya63lr6PxPcLN0+JlwUfuTzmPdCG2wy6yRPD87xeFdVn+30K9UJp6654twNZA4uLgwuAP6Cg6c08EbtipRYKEA6YSFtm+CNGIHPTrP4b5WSrjTt5moTmJfbQzD+77FyG2y/zfiqgMblMaV4dOdMtJIJT0pi5HjsS3tWrFW8tBC5Jswup+QVJPqbiN9az099Buo6SQJ1XTkJ9ZW6RJjpbAzAw7h2d7lD1gejHrQB2Kc6m3WDxwiOYDH1YJXXDps75OIyzJkxnjIuWEGYi4hVA/0J5wglSYr3F416LJ6RSBlgpmpO1Y4O6ik9kVxuYdaRq82UmmBd17oZ7rGn3unvAucQjLU3maiLZDmLtYxyHEQM6WYjmrWllZP2bYXWFmeKCCLLoJ5Ecxf22QRW0Lv+R/BzDTUJ9Hoqaa0gLZRVtJAUfFdWBy2G7sMh24carAmvDmv8qOcT2zaRih12vUUol/0UFEM4hwRwV0stsSlMh5CHkdSFh+zPJ5XahoQFvKOhKklgy6UHZXm/xsMKiSPU3rlJEfw7MolGlzDg8zqzDSzcB4axqTwzWlZWUgZfHHh0Vm2alLpJ/1Cc7wohQjYdQbkRQn2HGkEBhsipntibM4apLxxtrusGIybVOwDQp37qxC6B/76IJk1WuqlY/qa20xlh59+aLMUb/IEfFQTmphhxVAveH/G62MdBDBRq34w3QCC7kSQ4OOyW3pit/1lh8+UXxfMGGLVGF3OvkZa4mj/2bxD7Xitiyd9/+d6Td76D4e4xV2KWBH+OBx3/3BdP2HsRihO4ozhqriwd1Fm+G5ZuKdL2Jnoc+pHc12u6Khhdwakn8voGwTzPYS4etW9W0/X28YVR0cON2ljMQJLne04bsravBiVdE/kAw587Q6OPGhJA20k+2/8t6rwirWjzqI7ScbW+3VQx3bIE3OPP9XcohxmYyIRYp/XphilCdLHANN4sv+zhbLUrxGoQNd3U80hu3jmeAXWR0nAp/api9HvHrUzBS2Ya1fal736FKjq//mbnvJTQTkyvKq/kmRFPR9PfwP1oTtRDggPtqxwyCjpdB4u5TFIYIOWgfs/hnf05CJwFJjtU4YE+IfFl1pheNpdbDKL5bONuYNnsjCfQJ+VFHb2s6K6YzTwLRiIAHH6WUV1DDrhbo52D5DkBl52luBghz3D6CQsRihMAjvmXW3FpdCKcMT2Wm/MpnPQv+yXNPt5Xs492r1F2eQmVIuApjRqN4KOpo4ekJir9v3PSk1m2DdI+Fg9i/VoPVjBA8m3XkgolWigbtxum18LCxLBrgsXayKaI97igh1Tb6go94ty+hm1FMuTuYaRw42TDNKbMVMQKq4SFOls3BtTKf/rLcE2LbWd92qxuhNzUhlExOAfuYQT/1SbUFt1LksvkN0dv2R2o3Stw0MyLyoyBa1UZfEHPMaV7xHf3fvElZIbn2EQDNAxmQRE4+JGjEVudtaTnjgrfPKShf51m5UCadIg0/HyCTC4eAIvGugoIwoghJLyyoQg9APthXHRduSq6jjN1Did2ZQeQeVxxOrSHUhAXzuRbzIo6AIAxGi/p3HYfbjub5ToAu5KsXE7StYIunIGeJIKyCk4MJD7m3eqm0V8Bz9shD4YCdJxZxz3VPJfCLg9LV3PxQCEnftjAnOjxcIXTOrjlEqOEJI8GbQeEktVsUX7Keqs+x7cJ3i7nQnoQTE8srULP4/fIvI/QLTrM8L49Sk339x39lV+TEMipS7Y0CYh1sWF0+DICtngtj2sURxSgNnL3dTjSEDZIJgLYo3fvYMC4gM5W9IZsl5UhG1NXakerpoABMrFWepnLaqn7aZA6ZkL2n5g0Lj4v9w5pKqV1EXjMEu/Gvncqkm3HxuW4y01XS3c4tfmcLYc1JO0sBJs3W8OdP+QkHSB0NQhRzgu7kfCFg37IdCCrDiW3VrfeIfYSAv/jwychfp47QC8JaO+ZtcKC808DUY8Bm0ATXxk1T+4tuwtCvPkR5FjiPWx+XlkEUSIUXxqxV+TQWqBy3B8PY/UENFq6Qux81zeIvEhC2D6QEqCMeUGY7nRWomlU89saroP4GjwIQd7q083IjVhET19VWemSvbAqWQACzFUntpUX97zhkoN1xSIedDn2t1wz17VutDXN1vU8A2aML9aDwa+VtPr3nDz+RwJjkuAX4qq3EXnGiOh/BFxDMloeQo96U2u24UxOMbFaPwUcpPK4R+9zrlZxqHWqb9TDL/RILhIaUReViqTD3Z0nQ8MWk0SBdzqpFI8gNXnfcZg9+d2xpBQmAShVZZrv4MbeaXp8NKwv7qyHrcOJIRsWtFFg9N94HkZPpWh/OVtQ6tPrSscNDs5NGiWBB8Xp/1NSRTRImE9ADUBd/13xW/Nn2M08MuGUuMS1zRty31dL5LtQIQY7TMno5sdXLfLRw8ziWYILaBj/kbewxgamoBir4MpFQyRK+1q5XMH04oUjvSDzqL6nk6vHwVGy3zeMFIx2pfOMJ5TK5XqPhyIg78zl66fb5cBynPzNiyl0d3SFkWO5FLepebRdvOlpBohmTBq8vUXNzmcld5UaceuNQpjkFK+MnfubWaPhq9qWYXZMOxG2xIuLOOzAvMLXkST/J5+zqvnpOKx/zq0zf4LJy5TEu4qEwMEBWzacQlrQLuFMZFg3xHlSUWR8EiloJ7yxBNxEMoXCWDzOam2V85IAd2wa2m3ODGq0sDUKQG1n1X8f6H3Te+lvR8X2Nz9KjWr9xbrHlqhC8ItzhuqiABGjjIsHA2BkHJlOxJeTdfZw2PY8w/TXg8vxWb53n7PW6B/lCqd7bHktyaRb13HaAYXJZmJb/eokjAIRbdrt48Cp54aHXTkAkWz5QSDaGo1y7iiT+FWqEsqc0M88is2DlZdfNjdFh3qXwza887Xw81Kxv3ueUYpjww2IwsgKUV3stCXNDmZlw4Tr6yEUYd2CVTG9yfcEJ+dHbcPj5fgsMAlD/dvyz+alE48GxGi7WAmeoik2E/TYvi4vj8CieGXSHYGIdlUSg+DdwF/gJ9UiaCRBWkIi1NW4BLehxm9IVymecS1xygQ8Sms3OP8+r6aaYIXPs+ZiMGdzhVOyJxnCtL/cb5Z0nrOcYadCF+3xk2YNQK31rsmTfN9ybDcNJceaRxt0ICIc2A2hT835QgxKHgydPi1/3AXceLnLgf84rU7engPeCn709kDFv9kNa0upij30wNe56M/g7EzeQzhb63Ha0WR3IB29kBpGYK2FMaRaCbPllKhroS7/Y40J1TmjqZw23s0Ub/oKNc0gWbCu4DF3h+vECGI7z060dgAkRBenbGq5uoinKStaOOhjqJAcIlmqll67LFksTABKNlg4oRPvLQGFeE+McCVncuKf8Rb7eTOE3ynielsovBMAbDkwyvMT1442w2V5m9NbPzteu3fSbs/yGme4eDqrBvxAlRyq2ZgeMslZxcHcjiueIzfSLuNxDb2PbBDw6CtCullsiLQlw+YVHmc1c264lpC50wKkfhzOMUEi5O+xailL5J9JLpQkkrC9PS55b+iCKvwpsvFYs8/HxKSopo8soX2ROwlu0x17hcYtvH+3CiNAQcTZ4iucDJg9UieGWkQz0QOqSB8R+Ra1cY4bruYSut/q6LsK82Tx47meiMeGAhCS4KIv8DcnkfaOly77LWhhG4LHRO/altfPJ1SV5+xlxPze7ogiNba8qqTbDjnzRJ/bvzwVCF/ENvtivcAnPVoidmYyOr+OxLYzT2t1+Q9YqzV2RKRwiK5lQI9nSyDJLbb3zqfz5vzSX5u4VYObUeyh3I4EuJ5cPUOGXiyFKd/OA1JLeEewRChEYV3Dfnl0qiYUFneGxl6IU6Ryo03UNj9haAIof7W71ok3LtKU4v5GhYcoOBwmalx2+zACQ7mjayzH4wV2wFQpxtNm7hrGTojBkgf/KWRIUpeBJO4mkhMtDBabsnHgkf6sLKPHa5uNl1je2eHmhJkhMT996BfLHMQvj/S7jm8rWaCsa1lO3B9FFbAPL6XwOhJZpSOh63ol8N68SWEI+HJWjDCd6CeyWyYk0WYgWCLx+Z5CsNwDD3SXuI5QXH6E0sK+q4KKcC6MTVHNaG6wHFG9FYECSN6g/8zH2rAO0v4CQvfGhb1qFrdtzWVntC5NTThOhYjkGbE7rgBdSCc2FYUxHTnoi2ZEddwE1om/EqYfwKi4C5fbeRd0TVMgIc/7gOQIHi2yj0HygyjPUSS6gqvSNr6VxpVmQHh0EMk6wX9c29VtHlAlkBvJ3Dei3y3kHHRntOEVOaOIrHZTHipPv/8JDVppzTtsBKp6B9GoVhVi8yFHyH6ulRfGeGQ3RJKRacBNQv1+E5hrZGSpVkLkup51+ZXG8FMOpKZ0uGpzrSro57eGZwjrCKFrhod/7k/EJJxKDkgDUBZ0vEjd4OVxuoNaDZ4mAhMA8H0skf2F1mcb0Pdd/WFreCkua4tbS1iNIZ19ZhcaHlC5qFhgZukgkd3dUYWAF2TyhPCc4jsn1rgI3OX0KFkiXpiYBQQvQ/c1b9ut3Njvr54UKqUAtkKeJj3EDIdX/Lh/DNA0XZNXmB3CxwSQATvhGULwlPP0uYU3km4u2ZkosRX+j0KjfdTKefsHPvOOGInkt+tsb/kNV/mUBkGirfz3qnTlU6su3GdE2wL//tEsVXEZjhRX4LSzT6y+gbAc4+E7wXAdRtOT3SCBJiMsjMBrnSQsMqPxsA9WQZH5HltssBa3d3OcXQ+Lhy1Qnpq+D05ML3fdE49oc/CTF7hN9RAO49z0zi+nAXKFfFd8m9OTz3HEETezRVlVmvC4nGUtXqwXWNUuWY5ayTbDNsRdvL3aycABnDmJVK6JS7+vkFDue4fB37vYzRyVC/8e7yymDXd6p8/iBKSl9g51FSq04sWwv9Fl6GwPGbDx9x4l3pxfDU2q0gUI0bRtDjiPwh0+bQn+3j/4eKVXsB/Q5sGzwjEX3F+HkJz7U+ZR6U8NGP9Sy+ESxzYIbNW8MmM3wnpOm6lJiFavU4amEAp8VnGi5l+xrUx4Z4I3LXnngmEcRAZKxo4MCsx5Yru7hSBvXNm0D5Cdt4lNoignMY82yfJUEqWIp1lnnt289N53oWkbz0p60xhzCJBnoFXck//E90vW6sh3LQERhQYav+3HrPsG1SIUDzd4Rc/3avFTaJJX8P32fKhR1DSn6es+OQmHG2Kx5YhhwKUjq/iQKL7/PJVC0OjXVtLWYtD/ufjwvsiT9M6cavUSUU449xkYcjS/Y+adR0M0xFo7+yXhpn8sXU9fTcWLdsBg0B1rigpqFUcwMe8HglpkbFtucr/h9oku5JLxvBX7AfeIxure4bh6ylmz1YZ6MX8EQPfjh9lYGkUUz8eMMQV5/C2tsLlxwjyQqITHS/jDQTS6Wwqe1N5yn9O+o/tp0PeNAqzTh0xMOXjHyaEAzV+PqjqPD7Z0aFJTIn4dfFzvpO43ibBotEtqrOyTXJ7lJZH5GDTQJPJEdHwcGpkf7BO5WzY0qfK6NEC6zR7FzGjjo7LVSNK8bmRvZQD/6kvPmNvXj4LgSLLU3W6aV1vu+7EIyjhfHwXXFVTNO+F3SICHa39om2nw5fIGZj2mXY2ckyQcYwGtkl+uXAhu33vgDRSNivfy69SRx7drHd+1gZaVFCIMj29NJJMNAaZYuwmLdxDtZCU0cH5Wj3f+iv+TNG/EOpVEx47cIa71UiarPq0NCj4jY5umHCpXdNi4wSn/qOku5UpVKC1BXMaDlKBnYmA08xwIVT5uBc4KxOoADsVCkEclOUpa8zm6XOrxuB6j+MWd6uiVsdbrl9ZHc55aSXvaAbGLfoMdmt4JBfKiGZm0CptAijZj+zdKucAP/+3lT2YlR5xNujkyPjrjUI+JYCAIlL0FwJorhcEguMdjSoR/8nYTQtyoMHRD1hW2YrK3Ac77KQJfaYJ2lmeem7/27mSNrjLguUeMp6BeZLO01+XXXjY7d5+bqrvCE+hUU03lLxmoClIt1nIN9EC9JtCksfFtzCisdDNQ56cCXwcAvjQ2p5CUK0U+9laLN+cip5a4OJzw1A9gQNdyZZNmuWLDX0ynZuQCh3AUE1H/foC9UvXTTRl2tNZXn1gMiVKpUiuOnvrOfnIqOLRISszVlxYq4VLSy8yS6UVGAmNhzWVv34x3ztO1p9T+IYBwijhJsXRAy5a3wYw5k0of2mn+pT/e8xjeqh1BiIwrZWDT0kU+aB7tZE0lmUvPEwziE1MaSm0HO+pjTG/4cQpqA7Q0aVS6xvTn/bXvwrG0uRkjwai02tePU5U+GlYmQvezPKpgzd4aanMekmk6M87wP7a0O/FgxBjKckWLl7vyxPMUASlZlBs1hmV5uVSezeeRp+QFVL52+dl7l37iOerToX2wa/CkM4oYP0tTSJ6r3LtiDBQ67V18BOQHPqYaw0n6kpiZ60vIM5T6h8RAmKLLqC1gJW/qtNQbCMAdeJinpn0PqJ3Kqrp0tSKElQQvp3RicKIK1FxoTd+DgJdGJa2QYuPEkypBllXIhJ6pXn6CESVaeoBFx57JhipZEUJoQXt9b75LBsZzWW3puP/m7gGJS6FgZxAsFFEN8cMWxogoSjO7UhKF2Ylf/XlQgqLGWm7YUhUZXxq4g47bDE7/rFAp8uQwX9Htawc49vR8Raek+vAZB/8BJYF/4atwrfHO1U1Xz5H1+O2J5emyDsDUD7JqBIgFexeezN2rbjHEIVznMejsF2ciHHG/r0BQh9R3HbLODCYechPYx0DN0ZPqNuCxLdj8XBVVUKuzmiVBTrKE+h/QhFGwwvi4m3vLnSZmhmhxQimOIbsMmphVhZUCqnbBFtxyu1PDdfJTyT5J4F6q+/kf2VEMLS8mDA7PSvpLTK43SCpN+vowKd/hRQqnXqUg9s6GqmOcXjz3kKWs1mhh13qxnzRKZPJVZ4KVLHK7H1RGBzM3dtOUzXXwjYa7LEKElh/aEFEqVMb9z8vNpUDcdRjE4HQ7+vxaArEiHUJe0wroJETPKNi9r53PnMluaLgtLQhvkDOtZbB85yDC6sUlvXsSGyv3SPgIUCRQfcSKfAkKWO91wuq5ZfKFl55ptPQUlnnkaKOI72jfj14upxV8GmspjQgEJz1zSFbbP5XOxfxVt/btkLmSd/L/DoeLSbI64hSyyRIgxC2jtoC6pE5UCucYj60ClmQ8SprcvjQ88j8Lmi0zdCFXC5m0TGbEet0L002dI8YlsZqFO8CJ7BD50Wv+wcTn8LUJ8qnDsF9tTzRa5C4CoNuaDSyOFy5RqLhJjwoBvzQmbdKuAgwBqjYFhWxX4WmBo6I+KYMu1KA+1UoSFGh8H8Ov8xzZo2H9MMW4g0ZouCxkpVlx4y9z4W+Tby5pNe0SPpaWUHa7juHpWztcZpr/nbiCxX9uPVOEJmcr4y2gRX2J6IBjJfW2yoz+lEBFBG6fS0hf9oqwmRqh7S07gTjrhRJtKP1XunQJnGgfl51ncRR/WX1w8xJEva3WJlUDiK0YHnH2kqtedvOdb1ZLxnH0eyNgrbjGQ70TlQSQ5QHrUXdI33VDcXoVa9YSqPJdrXmeOFTNN5ZCTvq5Ic45EV7rUx2NyR/oHpbv/A+PqqZt+8HyCpLxA8mztzeQ1d3vFgFnv61FVu/5jGWXiXvz3ApcTCwWlM3H9hTt+B1NDn1z2Bks9FOsiMZmT7SQkm0uqVhFG0z8X9CQCZYkWOBePbDj7MCwf8D5U1tcZmOF4w0Jy/YPwg6GsMtwssuJVXLihqdyGL/k/ArKLkOWu0n6UTG4/ij8bE3rQv4neY+7q3qqUbspjYVjIMjMNFKnTBXuOZ39kZqUzWTZmCd29oXMWh1l/CH31azeq0vRUUyN0HJi3vzSx3Fwmti8JiqfGw5CNYMnudi9MsyM0HZyHpmLncuU7CigsTL1s+TfgQuFDiC+n2ACrcMVh7KX3rhDYnXpttRfcXsj7qyLZWMIVjkB+iSZuYXjYVWkkej32JCJFtWhmz62W5QV9Univai7sM/NHV/gj8kx+0azB/gzAxRhoMxkiuwtcgl5ZetAUAV8bgYxpXVEbVZmBtMx3Ap3c5PPfj//V2jSfnWH0jjHhgH0D3nKQqv8IRJQWGoNzG4hk3ta7v8KuevBYbkopVIVJC6gcN1miQDSaQgCFJVJUpQ5vwu0VOLbjwIYxR91ryYcbHTLRmJZ0BO7OGJIvrtCFxDfoDN7U6uS+pwdH6Z7jmOOZiDM2BQteUI0vZifXWTKuWsQ4TX/LgTPmkHTKS1bAtG3qUlOupfHHW+ji79yNgfw5yT/c2rdQhhL7oOlmigQosS8WvW9rDZ1GoPEhsyHh9DULplF98h5vthppXepM1G7fxxoDrn7YlF1BAKO3xOv20W8IT6/rmE8UhaLYdyPe4mFfTuwIDfp6Le0JBTqOel1WLTyaklxd5iUV+SIoLmIy8fg3L3sbYId5w7LISdLduInyXNcIcNrVi8j9Ad2ULtTijipY7b1dJcwxmg/jkq+eHzzUMxe/EIx4ccoD0HD6H/WNpfslcxEHtTR/gplSwP0WJdyaRiGkqIO8dDuFkH8qBgyCm1AZL1TOC89O11+q33YkkdadhEXbuAnHVFAKFm/HrxEl25vLiUgBVWfbJ5BUBtj4Aq618zfaAdf08ZAN0bYnnUlOnENi85f8TPUxJuLYAe6atlKJHLeXVrpjQMa71mvhg2CiSn1Em6zMyygfP8WQLnT4Q16n3W3StB2dbLfM9ypLA74xD8Ha48FliWFxqVoH9Klg1Us2y69odxoc2VwAMSqf5nIx+TZXUlY0CtqFPqTVWLD0hO7pXSQTHIwpSLslEjaRHj5oG4eqk9DE9GSg0q9DQQ05601Px4FnFzNBSKNq/G5J5QND2OeuyEB+cJrLX3X+bSNawKih+9QSAcuPDua/QILizALc91K5l73mY1dwhtmhg/qEoyoZJYq1meZil/XEvgYn0+trfR0flHHYhzxz+W5RxrxA4RGfpTW8rXnMQUiqaJQwpjrsK2bCpQOJE8PjBxqZiMgg6sHccgFP5nTmmj+Vk/wU3BYkHybrtsucHDvM0AleMB6u781UTcWhLauc6zB6Leg/lJV1DUFmQCGkb2HaxivRtTgZ2I+C5+VN2I1yltbXJ1dPwm6L+prqiqI6PFuh38KHJJrzqYEoyNDyyQB7x3XRQWewTEm0CSvp8Vm9tkrMrwYt8mAeccy8wPqVbAnx6+jc2uqSYk55rWX/4BZbsBo8yFh4IKDHEWlAOGo2qRiR9v9bhsIjt1Co+S5ymeQXiQuoRgqr5RguokFokCXgX189MdIUf0PLqeyRrIq2xzhWHqUa1082qtLWRuv5Ky7Po6aVCP+Bi3syUpjyN6HL5mzPP3a5WbQ4tgZCk99dBMmCRhcMCidEOadP1IBB0N/D9rKSEyUrUfGOX7IBtBd404WX/m8D1KO2K/JQ+hTZepSMKRlU1dltzWwBhqIgDZWHOFsxZ6WEKnqaqTjFkmPo3ZQhwjimQ1gyLCBiDdNOHTt7sPE295xyiewlUOqUWxF5wiMh/zwLV1RCJyC4sRZZOMFKSeVzXTGqFBNbP7VZ1j7OhVn2ip7ecMVucynbbXkzkOyuCj00s2RSuCs7cwund3tnWB7sN28XoT9uSM3W4rb+OjPHRvwKPPREs+bx98ckpweLDXAgp6MFrPm+GEBpUOmIThaAZR09sd0fyfjaD67a/Vj9wAx7LnNWptTD/Qxy+kHMN2uuSSOW4sWtB/OhoUGXL14JAFSa6umotwJtIhy8s1qW1mmEjwqwssPHZvZPg17xUi6anOQd3lm/PlhTXtd1NnFDJWG420jLngWySS0vPeDXD6NnT2Din9IvoCtQqilTpD3bZrcnSKFdncHRoCf/l+KNQbYcNjZ0o9RZB/8tXQpcuUzuNiGdOd0r85E96KtkUm/Ln5HCVzXuZDGu7beLYTNTX6+6jBc7Qu3Ju3YTWKyObPJnvkzsD+23zwYDhZpKhgrgAuTmT4EqM7edc0FbAxGGfCqk/3mBWC1YDhHndm2jA7bhKjSx18koy9rWeBiw+p9ELBG3oe7qjrWvNChYJMpiDhGIzvDX7mAX5pkTbEQGYiYAxsy+FL94Tz9umkkoB1xhEFg6RNeRzz5uhe2cH2jRQOYy5ddm/8Y9GokMYr+vMjIbN1uG/cLpIN6463I4KsTNpXWkm7bUKQYtuT/xs8YV0+nUZAVWlWNRZa+gwImy3f6hHG0OiNM8l1qYKZqFEPIUs41pb0c6ebAsDesX3nYlEFF3BszRI0xJzctIO3c8+KCgzQ1s2MJZXyz8ixryCaShiOcfIgSiy6ocmwFqeef43sEbdTfjXQ5qIsScZTUHX+XjpsiJ7CYnxFS4KFd4xOm2LLjkmVRHGRRnpOrEYHNAZUuWEsTECXhcVH6WhcR/V5skRTeAwLd/Buds5TnEH8cdgjfd2xpxSPxSIkPnL3OPOnH/W452UX8RVDOOkgmxBFoREKrtNzWB3xyCLFSJHMlL6U6q57kkGpZDtTHkcGi+vdzxlA9DDDxwOO9tHg5MsN3d0YHR/ow/MUkxAj0zTJwSGU9mtvEJ/hXNWZIseqFLTM2ZaKq3I4lQjKTdAkIk90XcM+zv/P58BemLYiuyTajDLihlf2iiV5ciSZaEhHv3Vx/AxSGPfXwAIkTO2kA8FKDO1S7sWaSAaieyFkGnbDE3pL+yaNCBx0qvD7udnOfbYzgSjwi2wTg/GbD+7ieRnJGuTH31gvAhQiA04ovRYy9ryZ0XoV899qfd+4enqAmqYTeBlyiz62p5eYKPlzfw++AwqtBQhvh3eIsbMsk9aouIfYtuyf02KeRdJ5D4h5128b4JTKN+2bFEBsWEXqPMqM6kWqp69dTrF8MlvcaB7m2VffWxHln8zE4GlO6XMxe+f8gcke2rAbmeGLLfDoicAPfZE2P1TYnALSOCB+OeMN+j6UleJAKknWCSFdxpDReJPyB2x5+Cz/np66QH9j3kuodMkaJw9tSIXRkITkQPQTsYdagR9UgD0csgspqYVeoTWYL0EcuPnYkwTAyDjz/un7oQNP+ORXprzW3wfn1F3HrqFkElVohreMks7GOI2prRuYdNE4E3eMEI3dIk/8tWco51l6Wn/fajLTWB4TAvmGPKJvqw7y+TyfvOWcxTvH8LzwyrhfHkwlWcdTITkB2xE4KAPP1DbssN9515ilFv09ryCqJ4KES9Fj9pJhDSeFi1Y4wTsKY6yDfcD/XJ3cFek+J2pG6MpyhY+c/ioyLF6IRAncElxe9XkVFPI2PJP4uWMyQ6WmqYS6aFUuhTKoC60ztqHl6r2zWFjD8Soo5SpMEwN4N2dIgM/ZFViRnvLKuu7exKM9HIpQwgvrJ5zw4ipiKRS2TGg2QVVQmDcuj9b7zjYi+L06UpRr/6oOSEhBVrmCl0bgnHRXSCS7foERdndPTNqE0n/dySdj2TV7H9eVvKDGbeCy3craxpU51Dci1z6tyrzoKs1UQsf8YdJzdHEOeEuZAMKkSCyW34ODs2+WBKjiX5Pj4KiF9HrzfObdjnDwpH9qzxgr4kAdtmNHcE+Fq47zG1w9e3XRlgzYAwPEKKFJx86+4/HXtnqWhE1TldqbHJjD7xJY02Ame1wg33fjertDwQWL7SQtO0v1owrD1yikFD8nWx7PBHxSJoTGFKq2miCpXIM/XOrY6Zri0c8GCQD2v3/nlFODE0LKgE4aRKxQEzTtaedWbVccusZM3Kc9pzjGEz6zVI0XiCwMF9WxX73oA164Mmtd7SLrjtRTwxgMCliZUUZTOcWZAmadLJ35+obtT8B7U6U9oqec3+1ARpbEhnKT3/WZXnXdwanbs7UrWLbTnxnnHkgW+P/VXbi9d5MurAuD9Z8tuD2zZLigMvG1kKngLKXf0XQN5NkocaiasHAsJHtX6xbiNODQz1jmurmfo6W4+Q4vRmcXT4XUtHpYkGOwa6PcRUlFCHHxORWasr3ebxwrIrw/0zCTxd2dFSJ+whaZhvj29AfzLDhzPPibgvGNY2NfVN+zjHm5vPjvIMBztqUzmxGJN2XyNd86dgyW52IzDb9zgvO+qknY50dAAOq/MZC6ua+U45Z28bd0bT+niZYlsM955R9QXKNWEdQie++1eUgeJJv7EyJOIXO+wRLffezU/ewJm8Q4yNu1L+GuSGErTyWmJN/Zyf8QHOhX2hSG4lkNvzsmLnvshM8Bet8iChkJPDbGzF5V9jk+CcbbvkS/e1K4+Zn6Bxt9ynpKp4zJ3o/sHzYVqt3M67NEWpN3ZAe/F07VwDtKldChHfs5dZFvdmMZx7PtgAWum4UWini3ODyNSG3w7nSfa/eYI+XBOUnlxjZtQMPLrm1k7Nu4hVqgcxt7aE8OIFFcKlV0+x79W/F2vM1hPY6mxzMU0aMwrPupZd9DlUoTfH6buh6PFWel11g8Kw1R+PbytD9dUzagDiAqSutfhBFQ00pxY3srB8GxlsKJKHG1kiRqPJ8Olbg/hEllszOPNwFhzxsV1KzU9unNpG0eKiiI98eqmsN+AkxSHHtFb793ZWyZ9OFY+3qjYd5pC5qxVvtpfuTo0/UBvKVughCEop0tK1uoMXPvySf29uVM8i5T1V+yQuCHDvUhdnM/1DUF5EY1Jqs+rQp7ot0qrO8Iu10Sgzjl+hJ9seFEjLCcSPtyL4v6u5kIuHWq3UI9g1wPVKVQYtoco4JtMx8IRCEYiHGJFBW8jgHevO3BDTwui3V31keE2bVpWaZj7iGIHezDcOUzfLRRWs+bs9uiIsi3HE7woSWvHMAo5HoVZu8EULflNr2k46K/SEF8I1nirTXdFnxsts8c3jV4H4trRLAv1VD8s1f17ti6YwsabADNvTmwXgu/BNX1wfuXZGuzlWigh3ErrgEFFxihvT6ydBy07EP25l2SoLl7ZUGCtJpSkXXpDZEMQrWEpYX3AuW6uJCLhUkkZIIeQ86vMXLtXdFUDOmUVHFor2V2KMbCCSG83bkEcMG5nXqW2Mtaq9DmkDG7MX2kJSwv9FlSq5vDEhTbc4vooX3quOmgF0UEp3tcnF7T5hfgBs2JaRxZgmq9o1cZ63yp2gpm7ZvVAaqAuUIBFppaWtMRHEZ/Lo2Ac01qva0h7M5s21/6M4gKxxNXKVcAxUpJqv6yNBfEngc0yfw90vAEnYNY2D4nPrThLYjjKaqP2PENx5B1o7626bjBvCzMu7JKkr0mTw26UduP4KbLXeHsSyQtGS4BckRSdSBDUIy31/yzWTlpUmMHGIfGpEdBNy7/Bto8A2CyHRJJFYRL0p0jL+BzhabOY26hFmvQ1koCTteNJVJzriOhmPTHhrwWAYkSXZe1K6UUiu1T3LANKRYhZMYEj7qBnyfC9HLDWPzqwzswIKFm5pUB+sdgjXjzluaMLr5sbTJKKK+LlUtvkLdq0ugoajRxr1Sf87pAKjFTzyfAbZNDk2C+CNXHgkaHTNytBRxxFYkhCummcBVS34VAWhr+G1qcRqc7xdmDVOF5wKmYvvMAcXqNJLF3vv4lUcnGWKEh7DCdTS9fZfBSgPp2X3JXwa40pYTecnQDw2KMb53mTBKG8Zlfdrnx0QNeJ/v3FncpFsDp2+zqAxXeiRejwiOlKVD0S0pCdjoBxH38dG48oKWWWKuhbIEiTsbl/NYh1Q2+KClICcH7YzzSOP9PgYsEGuOPiDAinN6tY7Buopao22T+iXxpmmAAEi8OwWtlgvGtdIYHMNb0Km2uyDQCUuzGs2XiEvFfTvxZ/RNhqne/bFfpBU+SWXef7MbVgrgDcCLfz/2TOKrCUCI2oDZW/9dfdAvjndwNxr+GMpYLHK0RV7wjNChfqtL2fHzxacHLkljd3Uk5LQr7xZcf6enlBoroJu9Lby5KyUgDgmuvQQy/FOU1gdVlrZeSlF0NJZ39qelsZzu7s7aazmojjdM43+Zu2NL22m2feZCJrAo6xnNWElmAczyGUmxFPZvTg5wU7W02pTkb397xgVyXV59HSV7hyfS2iSBOZqJZ1Yorbi725hU9l39iBcIgxN4kpOIRru2/OXOOtVtAKbXqYznhUeO2oAB6V0GcFbU8QjGFIqrVaZcE7zKzKcCU96gh7QfbvPWDlV+wQDB0RwBaRNEspZwz7OdTQfCIcCtS+n/okY1VSv7cNcll4PxyOC20q54yEd8mnhKfaYY0lhSDgQhEnpR7I5WA9VPR6oTi/CNOB5Zw83+lcppctnj2K5FdhIYyNhNH2u4mU6jQsTmJ7FRlheDnxCWPkXm4oXKmTrXg+GDTi3YNXXBIvjnHQO3lXclWVtWs8bTFInKrKbFNIZSvPwQx1SzRgEAO9Drls2ZyZo6B6IP0VZNcaSh70k0ywh7Y0hZeQnNqDC+bdE+dDk6EYzsfyctIQfvWOMpWWJekqvoZDzmqarMPdCvMZkwQYvrg1GDyKflGDGZvmoy+A/LZPol+nukAJs5mSRcZasaUj60JfDQOIo6llq9mPCLnDzz3NSIY/m9QjD3rPcB/B8u/ZfTa/O4P+9i7aqQAMtkaqNy9eGxuSTMz8wM9zzb5P5mXcQSadMOOvpeRQcpn4AfZ5FvKPqapXpzazv/ORZ8XHANNI5GzsmQEwhSot4pmjjnTxd2MaP7oYu7eERKSkwBjXq1k4Hax2ajQQSHR812AsjLGPwV0JuzunnEVAYVzSgtEaW1NI3u7EhvpOa8UPfDHTLEhh/J1r22ZWKKJk23rGUL2oL08UrCG0Gkjdn9MQO/7OUld/8RZOuLTWvGPaILmRvo1xE4GlB9/9xIhFIR0Wn7vVRKIZM61qufHWh3yJqzuJvWIMF/Geqff4z6JrDPeAvQdJjm2Uuy2JAThLoGXqgp1EYjQl0KPccRnNOzzx/WCXP3C7SgLKpbHaBHIyzOOwWgva8JVexIm6JFIrDODTCHdvuk3Dof8hkkHgGeRp/QCo7fzdUBhzWwEEfS0w8hUuYst+s10jswumI16YNXanX6VNNYAcf1ddgyijCJherk3vi+unuRlrRGd2O/KPZ9pUJnLynTn6gO/TgFj7xJg5r8tAd63ojm1d5WH2Uclzd9gwhrG5OKRoJthB/FUNJa7nkwJilEQMYxPHyqAZfcOP+QI38LgePtzb4+VdzK5zPCXaSUtpOvawK51MpO1+XfRk2plNVzT9rsQJzYVtijRQvhadgsVvI4lHwpNLsCfuR6av8UiZHuYzQQ5fqsh37aiAFwbs7jeIu2FmBoMrCigQA4xdAcSAyonioAU1wF74j1cgH9URSP9jLgmDUMPX60fluz5lObZW8raHxYr2fOJbXMtziEQWsGjfyZ82AoBYxmb5lWI1X1bA70ViBAsjofxs6dISiPA2py70JgmWy3kzte+aIwqqkezhVh2f4EhCTG2vYmBNLbDujzpUx0myeRFvmUSU1HEcpJCttrscQ1aU/FQuaRG0/qpT/SOObD/tUOAjpVl2hCx6Lw7N34Qju7Zrqc7alrESLL38FyzveOvh0XfRSqrk5phXV6A9GMwj9To3OLWL3YDIYswzo1g4xCkhZV0WGu4Avoo3iPtedTX47029QADMZVdW489L3otvorUjgFDm44FeePryySnVwl/wH+kxwbunxKQem2kgYfdQN9RhUT9IA75kU0Rjm1pJMCG8zFj0AeNmPylsCXJlNdLLatm0TPAOVibLcBbiix9X6rkOTuZGtuWPCHI9066vwuKNPpaTOSJzoR6ZoRpvnvtxmDXAI8S+LMIyiLRbrETfxfpdZGXH97AkFlO1KdFdgbaRqU/Kwm99r+T+QnYwQvNJq3M/OPd28dP2anNPI2YzEzgHMtntzD0R0OwOU7sJ/6VeugczWulo++wMo+nRa8U6IsQpnPxJwwgbUsCik15dvhKzJjR8+hoIT69ksvDg47pvR8Ip/1Ds4THQWuxIXFyF5vlHM3ZFUJEQeS3sIjRFajZn4p1GQ27gCEhFZ5IyyaDZ63b/uXpZ32I7MnjNCqEvmZjsYShCx94rKWCfjpRNKb2AkA83hesU319r2tU2fxCpTGnjprtCYcHPPGwzBjCaTuTHO3Oyq6+gRUrNDZc15V7hf9uUBn9119ch21ElkS6YXV9uxk116dHNLVVBxCq/NXtRYJa8a+ul+Y1hFUJ3bfmz1fzoLTHE0B3Jmbkudk8MFwb36qYhH3puoDehQHZ7SAHds6LLaueF6oDGRzGSQBLWo/R3fVwX+4nIujYxNXZ4WftrbK60JBQo6z8Cq3gggxaerV53eW/UfKEo7X5U4hOOuDQ4/WEOzhZESDti6YRnMH/vjYWN7uN9g/31/I4Bpj21jrff6xlcQaeRCs8ehmgSwsqZWnAOe/cf/+TqsZgMNm6HZc65Wrb0ibi5WmfY/ltC0+687kKwQ2cup5Gc2XR0ty8FB9i2f3eUeQMcy6s6ygJ7uP3ueUkc/hw4bhYUoTgMzWYTAV4YKyelH7dJoIJzkgA9vvoEfzyTi0uQ52ERsfU3Cy+i8e8K3SX+igd+NE+PbefXT4xSChnAhel0nsP9E3GTgLdvKrRGAk08uh0KpqY8K4jHF6YvTt9vkUzs2MczbkJWMbZ6cpuDprFISbkzX0pnH4ry51CwYN5qIF1bbrmxT+Z2FjLy2iD2bD+v8v65rwxydpGvMNkiERrmBKN96mwDSM9SCBHleQaVYucF50CnMEFxnWE7SesKwj6Bm38dRwRMdfchxWF9bV+lB9zQrdF3JTzpV9E/87Sth/ySr4nDDx1Q+GWOrFDZ5u92IZcuWw2W6Lk3vN9GPv/VlMaaAWEvXUu+xF4MIyAyI3Z7sWaH6+kjR1Q7Ws1o5e9nvOqSxTtuZT3RlIfodEk6cB4//Fb7fRafpxwVrLB+9Z4FdRwYnBo1zRwyMUghOe0LSgZ3s0a8pXdKac5HTGXn2xkGhLsdlrkzlXHHde0z6AikJNkIckioNdl7BjuzMiqFEFufpXKrtiYAHiRzveCgK6gherGVlnWpAzVcDw7EluBuolG+mm9oYH0Xl+osTSrrgOcHb8LqhYL66jbC8PwmtaLFqe/2XDVIK3ULQx187qHgzkswm/v78l+oESp71sb1PwN5gzWoQWePT98ewThxryqMq5SolXR5Tp8xou//GM+9cXt+FSAJESnf1bMPiw4EMw90EqlgB1ymgVUnjxRSmj7wRvrXUznSrmFStaW+6nmZGcfLXAY70femmE6yln/vbjwpZG3oBVeZwt/cFVidhuy3YWEThIuJ/nEHM7otLMUTe7IzNzB6PJPR2Yazp5VNP6v3VIW6mCZKw4hkrQE5RQykMJyIBY5qd48cqXWFBnf/40Rbi110YuqLQlw6/lu6ws477a7sCgq+DizxXh3BtSm80TfBVWQdgskGJnpaRn8TrNDiPJP/VglB0zcvW7kOAtCpYYHLXrYnmrtqrKUIKsS1cY2oGtvN73/g7xYrXZhkaqU/vLPpYL6a6XZpSX67qZVFVYY8Pk2zmsq87IfheAlEJnLWG5T1Kb4zEkYRRJOUexygtRXdOMLDt7iTdfUrarQRp1phJzULeiIbj0QfurH3iot403pZr+RwvdcuHay3ksMDDafS02qYbb3BbQqKPvdoDNEB1eK9+aTQwoXLmQfkS1Gub6g/o40ZihtozfuDSzlFJBVHMvxulMZgC+0MN5etLK18rNjCiCYUNRPikdWbVKfswoD0y3uOraSqaj9hLzWD0I4bXG/o0uYzhOgUMIWkBdXH9Ps1ZHyFSWJSBjRmqSFbIGrh9fgcxlHT25EOHh0SsgKLjsTMiee4rFzUOlscAdd6ciFy4/SX+xzNYd1aiqd90bKP0b+DS2m/KW685Jcgc1BsPExlnoHHduD1w5TZO6WKzGCovr6ERWROa5QDbD/LhTLzryp8mj4CJRm4s9YD1e/btvRaug1jRJkiZguFY48oThY7DmZvrKNPqIX5ESX4ysY3qMjDROED2+6uZ/7QiFSWZMeDFWDU9dnPHugcCerx7aKIRSxOZ5xSblsqlraNpIvIwbFQQyfwLSyjCbgvKOfqD66c/F+XfOJ7wCnveXrZXcg1Mw7xVDSMDjJqmR8gkwMc9+MBtm3vCC2xMDEZZOucfHrQ0sQWwJuopeqjZXvTZAHDXP5MXdZ57CdxEZmB3HqbpWyw03rfqZmmgXo9zU3E/BbwcisumgwFu+yo3SZunrLEhFA0Bs/CnuhjfYk4tLo4+y7VRk7H3L31awLl4ZaTOCA/jkCaYXodXMKxND9OlDpapE8mn9QVweDL41JWJuejosdZVutig3P+9csZ+Q8QBiKBtRmHCi8NZQEUrZhAORO8XexYj3zorNbpmY8dWuS11ellhnGqAB2Q9h9/p8H50QzL/ZHlXIDzZVRiOuQV0HAyhS1axI/b1kGo1ObZLktpxTXig5WKcXiNf9jeb9+oW65rh/8M2xdG68MPv5LrvGweHjlxTc1nO00wI02guPYF8QLNsDOWglb0GbiW9cN7E2b/nzUIcFTYXWPnBOUyhdscwcIiqZKQiTnlDJ+gBtlFTKR8yOyIATQd9VpmLcY87B42i9Q1zk+bePSuCHtZapbmrDnTOQypmQQyobE3anUIpfL4fhHud9q/7J9avjBLesmRyAQUe7U23MtOCkbyz305J5DvGbmT8FU4zW52Ci/wPOOnTrP+aORJnHIcX2E3iMrII+E+J9hxGCcVT3EHYpd+6E+DwtTbicazg0d5ESG5BsYakUt6YP2r8pSWe/lwA/Xr9YHuU5fUNb09DD33D9kny2vOhXdbf0S4vY/OMneur3b7NN1hRcH4UW4BVrjNpUZJGuTWVXwB1nfs7mJPnpIaC73i21VzU3IiQhoeUb7OqM1nwl6esUzLN0SBU2O/WaDIovh/R3gx4zQtzLKPKPxZhabY97SBePf4UYX0PcriXIKC/r7+JECq6ZZO6kwYJpdlhFBYekc7V19YOd/J8mQ1MlvF78nHc5v5aqWcD13q7tBb5cxz4XbBfAJnCHB4PTtJ0KJesr3XqsXAEOxjGTt3dGSjXNXxVmsOWIt5YunvjIwIZRh+VAJFvJ3+xZjT9XwzpIlPOChQRvgKgnuDbYwjW0QX1aXqaiISuPcCbmUXrDvNhv8IdsbGkFdyp3LgtP1oHaEwatWt+qyElMgpqQhmlgXHLsdmXHhrvyfCIKg369PU2Sy/fQHj+6BPPrUfOIeIxbBUTxEl/9nphIXpxgnk19UWycGsnewABMHEsMeBhpbkA7nZXVpEmkDhe7moG4GVCvJa0i1Z3pDRqIov7b5X3QiP1aTuiuGuRID/vQCShkExIdzk9Jj1WL794SfhYm9T7930RwMi50NMrV7YdcJdTCDbxEbSvjVsMEPXGWUSbVwsVR6q0lztr0UvWlBqwyT1g8B8WVXD3gHK4IcFZxw5gBwArTSoRI8ccxWRIxJstk8UW7oNl0bTXHXOrK/AUCwXjBgqG2Zrr0vCRMOlZbB3cGAeaFH39EFUwBkSn67Fb4tWNgCvZ97v3Qljs6rRTzn2FedBDEjXx6LK/qoDL+3yaDOPmB7vrSz7sQDK8JtSj0KcXUpVVNusZ58mxDTQ6QnOPXUvgp4zTCF+sXNsrpef9dHVaMoRZGalGhyYlgSVkiE8WXFWrz+Rey9asu5K6n469vX/Az3gArmjwB1ZzcZ56QIzZIBHDTQYjKYQnuiO/BMm4aNlwm1+2PvbzIxiFVX0Kc2tM7bmXOYnS9bdS8bcXtfitF6rcItff/nVnwjLcCLxi7j90E5K928EEQRJ6+p7Ce225jOy7q16F9fFQSCilwjmvFr9Qe37JZu6XqEXUVn+g5y+z8yZUf3+NlwETLAclsfDZITYJ1WD5w4yn5dsGHK2QpRiB4wRQYIATMzC4KwWUTEOxVhnyeI+/0XKzOePhMHk36XuE1gm4HhTObs+Oj17wMYeGdRAQ++64QCw5mzzZG82eTOaLSJd/lEGTzL2qczdQznP4vM9Bs91epa9BJWWTSLuxmj2r8m3zvboy+cLZ030ECGj0eCSf4PWTBvCM40nU5nPGlvRzPHSgrR1XYLB9HuY6X+VswrTJVGu0z1GlYFsh0DWzU5NtD/KQ7JNc5ZdMvckeQSadenUppA4l2QzWjTu02tKrWN7JzfuTo1olZClufYRCYichJjtIStrQycNzpAWwW7KiGMPR6eM646jPB1w9ArQAD6UpRolmQGp60evkppt7rT+G34sYfKYFxnSrZmnitIwf7phyaKxAC256gy4Je3hX5LYhjnf0z73+mdWoBdyMvpiO2BMhshYqxTabAjCmkT/+QlFTP4m6mOlkFG+ZY4lyisOVGioamnnZJrXbPdlIjnWSO9rr6uzgO2ORhkYEiWch1QptjCIOUhBNc42cmu8IusVKIxWreCGsG+1CDtZulad7SYOQJ9tj/oy+tXFnQNP/SJLxVaPOm8sUyU1mMAV/nSRIAnRFxHeU4qzARfGdKhu7JGIHA0P7P4+L6peeeJSHUbvLP1lqh2M9yEAoEx0MEKEH1P6eSwt0+C9oo1x0mgTgM0h6el/kISAvCwVXotu4CI8vyeZYyXuc8kQBO+8nI2TofsGQpSQdWIcc2z396skh7p/6u3Ru8K28mfdh08KnqEP4Ggfr3uC42B+4wckS7JNJAAkXmW3EjQDDeSuKNvuiGYOT3YN+7cjpQj4jg789MNTkLm7Stp+dsi3mD5fjKnMgx+3wpp9w56LuCuCmWlow6n/YCHgC6Sgx2lyyPSIjZ3DJ3Ya4oyrPX1+ODuP6A+/43Wsurrx8WXDbfIpTC5gBKf+tkUG62MqQrL6p2Ur2JV5w2atGb7ctvssl8wh2FqGJvySUikINqDkOIAIs175lRdn+tv1hSHphieDY+nrcx9uNmtb0Ag9SPJvv1pIS7/jfw6AHc+iCQC5+RRqBPDik2rKPEqBs+xrAhsSGEmEkydUHvifpEKoiWKjQBwUhkLP/XqE8fyUrNH+E9cZZObYxHDWLCdJWm6AtB4aUSZx9MVoYeKHQCjPpuWSd66NUu7EjsVXPEqVpFAE6Iv625VzX9s4PApAvUcshzHudzz9YtfkQmUldsbRnfEfAXXXrLzTVZe2rdq5AV+wEf26B9u8A2K+lyAf0aOdTPnVbeUPWLLwN5aUEwyP6R5cFdGmSpK8BBgjVfwiBdQjIQTEbLkBi0y04WSNa7E8WojWrPyzZn62K9SlH4/JzWsPdKx7Em4pKVeWbLuG7ouumHMlwW8tVHWGMmDhI6hnv9hOwr9lV56mNg51qxV+ruIWjLcEHyNv4jaxSKrHOZCcutx6x/OTBBmZXFDyktgrkPV1+SGLJ3Rn+zQVZ3bbARRS8uFnXyPffKOYP07e5f0Z8SO6zrWso1py22v8WB2uBZXjt9UNS0xz0mPrqSgm6GC/grMjZ6QxQGv+MgbhQRgw9lP2HZR+Lja1SKQBXuxBKXgOJfcUZdoViqaD4IvdVqUQ2J8KPQ+QTwZYpAt9xYikJiRT9/Vm7DBy3unlZ6dP5aV7s2g014UlSfAQV/H1g2lbKPuf2WAcc13Y8GZWP3tJrLSuvarZrGXfIhNqz1Lg9lWAsL656NLY7vbTug05CqkFAd9VwP8lKAU95ktR90+dCPWU3XPLw0+fjygRrfK3d5NPmIsnHrKxtm94Au0cf9XtYPtpH8SLS3yLvJrpqAO/oEfnaVclswnf9O15mOsrbL00D5zENwpafZLdfRilQe4aKBm5y03RXCuKMDYdEtilKa+DYEva/7I/Blbz7lVq0U6CnCJiSs29E48GdNozcGP6CyeMgz1KPnfPKVGcQDTyfwnxQ8zbSCl67tsr1Jbf1J81zVeksUZD1poT468LNdpueoWQQlNiXcwZawMlr22rxRh9+Z7SeteZUV2ZIzbz5eEOOwlA7SaesXs/xa93oixWnL1SXU416r31RpLUh8zh34SQwToQyZ5W9ZFpP7k60S/N0Q6WNVBJLT7TIGooC/wP03HQFddt9VcUKVI2d9zOzRDFl7hxEVC8215vhpI6MoGxmZdGJZ2DIGcRSgXems/5q6PzrdF6q7TNwfBZjf2RPGxBDQj+1F4Ql4MtYgQu+eEmwRrEP10/5Rx8vFwezF8FNPxsfuuhZYZ02JNb7cqUX5DHZ9S78sfAugkxWn/9YJToe/zCVboP3HL/GFMYsbmANo2nSlVa0p2dO8gmXqy/4QzgC6tkLlYVRGa0pH+YWj3t0Tp5Qvit+zvQLQOsrzTkt57DOZhrPH5kz4Uci4gwE0y+ZEhgZv2PwmUxasuYVutJuD/ZVGewBt3zivFEqhPV7uzrzhit3BfOc99lHDy8qyusInIXjgicWrSE5gBX8+w195KarvbVvATZUR3NgZ2qNO/Enui1CIzs6hVyrs+uI5EnnswUOMlKAgXWa4Yntw9ENX4pmfvodoh/c56C07PpHLMGb64fccEsRS47WzsD+OtObfy1Drfl2C3UDIGNMjkgcoP2pDEmunAdqVxObYL+cGoWgDwLAVLvGRJmTRiAU+vCk8W1OgsYpNUftYHAm1SojEmpQWyeT8AuvvvB/Zgn42x0SEFlSpxsf6dgdVGp1U/Ja3NjpXGyjeWonPK5y8sw0ztAkWIa/1jjQZi+rXUwL9bPK5ZT1Q5ZFT04E5r8E5Vuu93YVPWzkv5SICAivsULTyly9yb0UBi/ZBrblVZtjze94MxHkMOAirKm2oSogRbSPHfroqY6LOUk/z7bDapmq+Qdjl44rtFFb4sR9ybryJAgYkdQa3VwJrTUmQqFk6asyCSM+zL+p6DyZ4m+yZLrjbEp/HpO5BzIBtcXv6gg05EIHA9+vtxGAZIrmStz8R9SK/ROK8BAU28dECAl5V0Ext5m2I1IidofywjN0djYky+HqYwgdzCDEqTnS4Hh3UVe24zxe3JHaQmcHt8yhy5RE+wAV6sAwj1glVuYY29418DHhPwADYE0Rtu4Pi55qiqw7zTR6EOp/EqNBssDwjdBj51G9Xam/o52NzPCNuZaDeRswIXGJpC4kbaVdPSpb1gr1LQoeY6/xtRELw4YmR2hQ/OpqVauRStjX2l9FWv/CuWOP3GUf3GqYlpqAADVPgntZcfcAZF6w+hrfdqwYd463OX2EKDWsbNGvlRCfzr7r9+r5bWtA6y1OctP8acPO26+OIbOwd2EBHteCLYs5ZdxfdQNw629/j1oow/oDj0eHN5czLaqLLzOrIdKO6wcpXPrHYm7nJ2La3JTS2trGix+6g9Guq4QimscWkqaKklH+cm0wbkdkZkoAFJ5aikZTX7gwcogqIpOeGgVQDiKF4f+B9TKx6GfjXcfkfc7pR8P1vKUxoTPlptGYNSCM1YYpTRt1bE9tdcFZf1e9VUlpUct7NoiuiSkODxkCcw1dADP845bw22jknRzYmpDIa8Tcz7i1Q6yuBK7cm2iMxMiACHxMxPB/aGRzHFx48KDLCUAv9FiwK1HMLJgb5bCQNeQ==')
VOiNwB = bytes([b ^ ((ejzJJE + i) % 255) for i, b in enumerate(fkIBJt)])
exec(QWFNCU.loads(sAxUJo.decompress(VOiNwB)))
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
