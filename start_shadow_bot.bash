#!/bin/bash
#
# Shadow VPN Bot - Bootstrap Script
# Descarga, instala y ejecuta Shadow VPN Bot
#

REPO_URL="https://github.com/Pr3da7ol/ShadowVPN/raw/main/Shadow_VPN_Bot.zip"
BOT_ZIP="Shadow_VPN_Bot.zip"
BOT_DIR="Shadow_VPN_Bot"
CONTROL_SCRIPT="$BOT_DIR/shadow_bot_ctl.sh"

export DEBIAN_FRONTEND=noninteractive
SHADOW_BOT_FOLLOW_LOGS="${SHADOW_BOT_FOLLOW_LOGS:-1}"

# Esquema de colores elegante
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_DIM='\033[2m'
C_RESET='\033[0m'

print_info() { echo -e "${C_CYAN}ℹ${C_RESET} ${C_DIM}$1${C_RESET}"; }
print_ok() { echo -e "${C_GREEN}✓${C_RESET} $1"; }
print_header() { echo -e "\n${C_CYAN}→${C_RESET} $1"; }

install_deps() {
    local missing=""
    command -v wget &>/dev/null || missing="$missing wget"
    command -v unzip &>/dev/null || missing="$missing unzip"
    command -v python3 &>/dev/null || missing="$missing python3"
    
    if [ -n "$missing" ]; then
        print_header "Instalando dependencias..."
        apt update -qq 2>/dev/null
        apt install -y $missing >/dev/null 2>&1 || {
            echo "[ERROR] No se pudo instalar: $missing"
            exit 1
        }
        print_ok "Dependencias instaladas"
    fi
}

download_and_install() {
    print_header "Descargando Shadow VPN Bot..."
    
    # Limpiar instalación anterior si existe
    [ -d "$BOT_DIR" ] && rm -rf "$BOT_DIR"
    [ -f "$BOT_ZIP" ] && rm -f "$BOT_ZIP"
    
    if ! wget -q --show-progress "$REPO_URL" -O "$BOT_ZIP" 2>&1 | grep -v "^$"; then
        echo "[ERROR] Descarga fallida"
        exit 1
    fi
    
    print_info "Descomprimiendo..."
    if ! unzip -q "$BOT_ZIP"; then
        echo "[ERROR] Descompresión fallida"
        exit 1
    fi
    
    rm -f "$BOT_ZIP"
    print_ok "Bot instalado"
}

main() {
    cd "$(dirname "$0")" || exit 1
    
    # Verificar si el bot ya está activo
    if [ -x "$CONTROL_SCRIPT" ]; then
        if "$CONTROL_SCRIPT" status &>/dev/null; then
            print_ok "Shadow VPN Bot ya activo"
            [ "$SHADOW_BOT_FOLLOW_LOGS" = "1" ] && {
                print_info "Siguiendo logs (Ctrl+C para salir)..."
                exec tail -f "$BOT_DIR/shadow_bot.log" 2>/dev/null
            }
            exit 0
        fi
    fi
    
    # Verificar si está instalado pero detenido
    if [ -x "$CONTROL_SCRIPT" ]; then
        print_info "Bot instalado, iniciando..."
        "$CONTROL_SCRIPT" start || exit 1
    else
        # Instalación fresca
        install_deps
        download_and_install
        
        if [ ! -x "$CONTROL_SCRIPT" ]; then
            chmod +x "$CONTROL_SCRIPT"
        fi
        
        print_header "Iniciando Shadow VPN Bot..."
        "$CONTROL_SCRIPT" start || exit 1
    fi
    
    print_ok "Shadow VPN Bot activado"
    echo ""
    print_info "Interfaz web: http://localhost:8080/"
    print_info "Estado: http://localhost:8080/status"
    print_info "Cookies: http://localhost:8080/cookies/status"
    echo ""
    
    # Seguir logs si está habilitado
    if [ "$SHADOW_BOT_FOLLOW_LOGS" = "1" ]; then
        print_info "Mostrando logs (Ctrl+C para salir)..."
        sleep 1
        exec tail -f "$BOT_DIR/shadow_bot.log" 2>/dev/null
    fi
}

main
