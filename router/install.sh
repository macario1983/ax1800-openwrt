#!/bin/sh
# install.sh — instala o kit operacional do AX1800 (rodar NO roteador, como root)
#
# Uso:
#   scp -r router root@192.168.31.1:/tmp/ax1800-kit
#   ssh root@192.168.31.1 'sh /tmp/ax1800-kit/install.sh'
#
# Opcional (sobrescreve /etc/config com backup):
#   sh /tmp/ax1800-kit/install.sh --with-config

set -u
BASE=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%s)
WITH_CONFIG=0
[ "${1:-}" = "--with-config" ] && WITH_CONFIG=1

board=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "desconhecido")
[ "$board" = "xiaomi,ax1800" ] || echo "AVISO: board '$board' != 'xiaomi,ax1800' — continuando mesmo assim."

echo "== 1/5: scripts e init.d"
cp "$BASE/usr/local/bin/"*.sh /usr/local/bin/
chmod 755 /usr/local/bin/guard.sh /usr/local/bin/bait.sh /usr/local/bin/mon.sh \
          /usr/local/bin/check.sh /usr/local/bin/memprobe.sh /usr/local/bin/relief.sh
cp "$BASE/etc/init.d/guard"   /etc/init.d/guard
cp "$BASE/etc/init.d/mon"     /etc/init.d/mon
cp "$BASE/etc/init.d/memprobe" /etc/init.d/memprobe
cp "$BASE/etc/init.d/relief"  /etc/init.d/relief
chmod 755 /etc/init.d/guard /etc/init.d/mon /etc/init.d/memprobe /etc/init.d/relief

echo "== 2/5: hotplug (fixsrc + cal band-aid)"
cp "$BASE/etc/hotplug.d/iface/99-fixsrc" /etc/hotplug.d/iface/
cp "$BASE/etc/hotplug.d/firmware/20-xiaomi-ax1800-cal" /etc/hotplug.d/firmware/
chmod 755 /etc/hotplug.d/iface/99-fixsrc /etc/hotplug.d/firmware/20-xiaomi-ax1800-cal

echo "== 3/5: sysctl"
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf "/etc/sysctl.conf.bak.$TS"
cp "$BASE/etc/sysctl.conf" /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

echo "== 4/5: habilitar serviços"
for s in mon memprobe relief guard; do /etc/init.d/$s enable; done
/etc/init.d/mon restart
/etc/init.d/memprobe restart
/etc/init.d/relief restart
/etc/init.d/guard restart

echo "== 5/5: checagens"
if ! command -v relayd >/dev/null 2>&1; then
	echo "AVISO: relayd ausente. Instale o pacote (apk add relayd) ou"
	echo "       reconstrua a imagem com CONFIG_PACKAGE_relayd=y."
else
	rc-service relayd restart 2>/dev/null || /etc/init.d/relayd restart 2>/dev/null || true
fi

if [ "$WITH_CONFIG" = 1 ]; then
	for f in network wireless dhcp system; do
		[ -f "/etc/config/$f" ] && cp "/etc/config/$f" "/etc/config/$f.bak.$TS"
		cp "$BASE/etc/config/$f" "/etc/config/$f"
	done
	echo "AVISO: /etc/config instalado — EDITE SSID/chaves/IPs antes de reiniciar a rede."
fi

echo
echo "Instalado. Próximos passos MANUAIS:"
echo "  1) Ajuste o IP do cliente de teste /32 em:"
echo "     /etc/hotplug.d/iface/99-fixsrc  e  /usr/local/bin/guard.sh"
echo "     (valor atual: 192.168.1.100 — remova a rota se não precisar)"
echo "  2) Configure SSID/chave/BSSID em /etc/config/wireless (veja ./etc/config/)"
echo "  3) Ajuste as redes em /etc/config/network (192.168.1.2 / 192.168.31.1)"
echo "  4) Coletor syslog: /etc/config/system (log_ip/log_port)"
echo "  5) Em modo CABEADO: /etc/init.d/guard disable; /etc/init.d/guard stop"
echo "     e desabilite a STA antes de plugar o cabo (evita loop L2)."
echo
echo "Estado atual:"
/usr/local/bin/check.sh 2>/dev/null || true
