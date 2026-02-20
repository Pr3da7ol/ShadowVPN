# Shadow VPN Bot

Bot de VPN con servidor proxy integrado, descargas por chunks y soporte multi-plataforma (Nextcloud/Moodle).

## 🚀 Inicio Rápido

### Instalación Automática

```bash
wget https://github.com/Pr3da7ol/ShadowVPN/raw/main/start_shadow_bot.bash
chmod +x start_shadow_bot.bash
./start_shadow_bot.bash
```

El script automáticamente:
- ✅ Instala dependencias (wget, unzip, python3)
- ✅ Descarga Shadow_VPN_Bot.zip
- ✅ Descomprime e inicia el bot
- ✅ Mantiene logs en pantalla

### Control Manual

```bash
# Iniciar
cd Shadow_VPN_Bot
./shadow_bot_ctl.sh start

# Detener
./shadow_bot_ctl.sh stop

# Ver estado
./shadow_bot_ctl.sh status

# Ver logs en vivo
./shadow_bot_ctl.sh logs
```

## 📡 Endpoints Disponibles

### VPN Core
- `GET /status` - Estado del sistema y cookies
- `GET /cookies/status` - Estado de cookies por perfil
- `POST /cookies/refresh` - Refrescar cookies manualmente
- `GET /resolve?url=<url>` - Resolver URLs acortadas (tinyurl, etc)
- `GET /stream?url=<url>` - Streaming de archivos
- `GET /watch?url=<url>` - Streaming de video

### Bot DF_VPN
- `GET /` - Interfaz web de descargas
- `POST /download` - Iniciar descarga por chunks
- `GET /download/status/<id>` - Estado de descarga

## 🔧 Configuración

### Perfiles (Dioses)

El bot soporta 3 perfiles:

| Dios | Plataforma | URL |
|------|-----------|-----|
| **shiva** | Nextcloud | https://cloud.udg.co.cu |
| **ares** | Nextcloud | https://nube.uo.edu.cu |
| **fenix** | Moodle | https://moodle.instec.cu |

### Variables de Entorno

```bash
# No seguir logs al iniciar
SHADOW_BOT_FOLLOW_LOGS=0 ./start_shadow_bot.bash

# Puerto personalizado (editar config.py)
PORT=8080  # default
```

## 🔐 Seguridad

- ✅ Archivos Python **encriptados** (.enc)
- ✅ Desencriptación en memoria (tmpfs)
- ✅ Limpieza automática de archivos temporales
- ✅ No expone código fuente

## 📦 Estructura

```
Shadow_VPN_Bot/
├── run_shadow_bot.py      # Launcher + desencriptador
├── shadow_bot_ctl.sh       # Control script
├── *.enc                   # Archivos encriptados
├── cookies.json            # Cookies de perfiles
└── shadow_bot.log          # Logs del servidor
```

## 🛠️ Desarrollo

### Archivos Encriptados

Los siguientes archivos están encriptados con XOR:
- `main.py` → `main.enc`
- `config.py` → `config.enc`
- `vpn_core.py` → `vpn_core.enc`
- `vpn_routes.py` → `vpn_routes.enc`
- `flask_routes.py` → `flask_routes.enc`

### Desencriptado

El archivo `run_shadow_bot.py` desencripta automáticamente en `/tmp/shadow_bot_secure_*/`

## 📝 Notas

- Puerto por defecto: **8080**
- Requiere Python 3.12+
- Compatible con Termux/Linux
- Cookies se sincronizan desde VPS automáticamente

## 📄 Licencia

Privado - Solo para uso autorizado

---

**Autor**: Pr3da7ol  
**Repo**: https://github.com/Pr3da7ol/ShadowVPN
