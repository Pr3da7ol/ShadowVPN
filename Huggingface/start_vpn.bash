#!/bin/bash

# ==========================================
# SHADOW VPN - EMERGENCY REPAIR (V3.8)
# ==========================================

SCRIPT_TARGET="shadow_vpn_local_server_sdc.py"
PORT=8080
export DEBIAN_FRONTEND=noninteractive

# Colores de Sistema
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- PORT CONTROL ---
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
        echo -e "${AMARILLO}[!] Puerto $PORT en uso. Cerrando PID(s): $pids${NC}"
        kill $pids 2>/dev/null
        sleep 1
        if port_in_use; then
            echo -e "${ROJO}[!] Forzando cierre en puerto $PORT${NC}"
            kill -9 $pids 2>/dev/null
        fi
    fi
}

# 1. PROTOCOLO DE REPARACIÓN CFFI / CRYPTOGRAPHY
check_cryptography() {
    python3 -c "import cryptography" &> /dev/null
}

if ! check_cryptography; then
    echo -e "${AMARILLO}[!] Error de CFFI/Cryptography detectado.${NC}"
    echo -e "${CYAN}[*] Ejecutando purga y re-vinculacion de librerias...${NC}"
    
    # Eliminar versiones conflictivas de PIP
    pip uninstall cryptography cffi -y &> /dev/null
    
    # Forzar instalacion desde repositorio oficial de Termux (Binarios compilados)
    pkg update -y
    pkg install python-cryptography -y
    
    # Verificar de nuevo
    if ! check_cryptography; then
        echo -e "${AMARILLO}[!] Reintentando con dependencias base...${NC}"
        pkg install libffi openssl -y
        pip install cffi requests colorama
    fi
fi

# 2. VERIFICACIÓN DE OTROS MÓDULOS
if ! python3 -c "import requests, colorama" &> /dev/null; then
    echo -e "${CYAN}[*] Instalando modulos de apoyo...${NC}"
    pip install requests colorama
fi

# 3. MATERIALIZACIÓN DEL NÚCLEO
if [ ! -f "$SCRIPT_TARGET" ]; then
    echo -e "${AMARILLO}[!] Nucleo no detectado. Reconstruyendo...${NC}"
    cat << 'EOF' > "$SCRIPT_TARGET"
# SHADOW PROTECTED | DO NOT MODIFY
import zlib as KUedEK, base64 as kJrGKk, marshal as CFmjuS
ZZiDqz = 197
LqWMQG = kJrGKk.b64decode('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')
dyliiL = bytes([b ^ ((ZZiDqz + i) % 255) for i, b in enumerate(LqWMQG)])
exec(CFmjuS.loads(KUedEK.decompress(dyliiL)))
EOF
    chmod +x "$SCRIPT_TARGET"
fi

# 4. INTERFAZ
clear
echo -e "${CYAN}   ___  ___  _  __   ___  ___  ___ "
echo -e "  / _ \/ _ \/ |/ /  / _ \/ _ \/ _ |"
echo -e " / // / ___/    /  / // / ___/ __ |"
echo -e "/____/_/   /_/|_/  /____/_/   /_/ |_|"
echo -e "       SHADOW INFRASTRUCTURE       ${NC}"
echo ""
echo -e "${VERDE}[OK] VPN SDC PERSISTENTE ACTIVADA (V3.8 REPAIR)${NC}"
echo -e "• Puerto de Escucha: $PORT"
echo -e "• Estado CFFI: REPARADO"
echo -e "===================================================="

# 5. LANZAMIENTO
if port_in_use; then
    kill_port
fi
python3 "$SCRIPT_TARGET" --port "$PORT"
