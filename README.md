# airplayer-dependecies-installer
## Proxmox Audio Prep

Prepara un nodo Proxmox/Debian para audio:
- Instala herramientas ALSA (alsa-utils) y pciutils
- Asegura grupo `audio` y añade root
- Añade `options snd_usb_audio index=-2` para evitar que USB audio robe el índice 0
- Genera log en `/tmp/proxmox-audio-prep.log`

### Instalación (one-liner)
```bash
curl -fsSL https://raw.githubusercontent.com/jarcos-al/airplayer-dependecies-installer/main/install.sh | bash
