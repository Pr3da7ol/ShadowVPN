#!/bin/bash

# Configuración
# Usamos 'raw' para descargar el archivo directamente, no la página web de GitHub
ZIP_URL="https://github.com/Pr3da7ol/ShadowVPN/raw/main/Shadow_VPN.zip"
NOMBRE_ZIP="Shadow_VPN.zip"
CARPETA_VPN="Shadow_VPN"

export DEBIAN_FRONTEND=noninteractive

# Colores
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[0;33m'
NC='\033[0m'

imprimir_mensaje() {
    echo -e "${2}[${1}] ${3}${NC}"
}

instalar_dependencias() {
    imprimir_mensaje "INFO" "$AMARILLO" "Instalando dependencias (wget, unzip, python3)..."
    pkg update -y && pkg install -y wget unzip python3
}

# Verificar dependencias
if ! command -v wget &> /dev/null || ! command -v unzip &> /dev/null || ! command -v python3 &> /dev/null; then
    instalar_dependencias
fi

# Descargar y descomprimir SIEMPRE para asegurar la última versión
imprimir_mensaje "INFO" "$AMARILLO" "Actualizando Shadow_VPN..."
rm -rf "$CARPETA_VPN" "$NOMBRE_ZIP"

if wget --tries=3 --timeout=15 -4 -O "$NOMBRE_ZIP" "$ZIP_URL"; then
    imprimir_mensaje "INFO" "$AMARILLO" "Descarga completada."
else
    imprimir_mensaje "ERROR" "$ROJO" "Wget falló. Intentando con Curl..."
    if curl -L -4 -o "$NOMBRE_ZIP" "$ZIP_URL"; then
         imprimir_mensaje "INFO" "$AMARILLO" "Descarga completada con Curl."
    else
         imprimir_mensaje "ERROR" "$ROJO" "Error al descargar Shadow_VPN.zip. Verifica tu conexión."
         rm -f "$NOMBRE_ZIP"
         exit 1
    fi
fi

imprimir_mensaje "INFO" "$AMARILLO" "Descomprimiendo..."
unzip -o "$NOMBRE_ZIP" > /dev/null
rm "$NOMBRE_ZIP"


if [ ! -d "$CARPETA_VPN" ]; then
    imprimir_mensaje "ERROR" "$ROJO" "No se encuentra la carpeta $CARPETA_VPN tras descomprimir."
    imprimir_mensaje "AYUDA" "$AMARILLO" "Asegúrate de que el ZIP contiene una carpeta llamada 'Shadow_VPN'."
    exit 1
fi

cd "$CARPETA_VPN/"

# Permisos de almacenamiento
if [ ! -d "../storage" ]; then
    imprimir_mensaje "INFO" "$AMARILLO" "Configurando almacenamiento..."
    termux-setup-storage
fi

imprimir_mensaje "ÉXITO" "$VERDE" "Iniciando Shadow_VPN en puerto 8080..."
echo "Accede a: http://localhost:8080"
python3 main.py
