> **Nota do repositório:** este é o documento **histórico de trabalho** (log de
> engenharia original do port, em português), preservado para rastreabilidade.
> Ele contém o relato cronológico cru e foi **sanitizado** (SSID/MACs/IPs de
> exemplo). As versões curadas e revisadas estão em `docs/00`–`docs/10`;
> correções já aplicadas aqui: nó de memória do DTS é **256 MB** (não 512 MB) e
> a região de 55 MB é o **`q6_region` do firmware Q6/WCSS** (não “reserva do
> NSS”). Consulte [09-code-review.md](../09-code-review.md) para a revisão
> completa.

---

# Port OpenWrt — Xiaomi/Redmi AX1800 (RM1800)

**Data:** 2026-10-15 (atualizado 2026-10-16)
**Base:** OpenWrt **v25.12.4** — target `qualcommax/ipq60xx`, SOC ipq6000
**Resultado:** ✅ port completo + **build OK** + imagens verificadas end-to-end
**Status:** ✅ **testado em hardware — FUNCIONANDO** (2026-10-16): boota do slot 1, IPv4+IPv6 operacionais, LuCI/SSH ativos. Ver §6.

---

## 1. Artefatos gerados (`~/ax1800/images/`)

| Imagem | Tamanho | SHA256 |
|---|---|---|
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-initramfs-uImage.itb` | 13.229.160 | `60beda1937d55067e30603921bbd1c0995a87de1a1de304ec848000a6fd519ba` |
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-factory.ubi` | 13.500.416 | `806cf38a0d51e28c5ee18cc95adfd902ae10d1b9bb9f64d29052b74d9747139c` |
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-sysupgrade.bin` | 12.769.564 | `31c1aecbce202b1dc2d5fa77f1fbab5e13aa5f81d53773e38f166c1c02c97971` |

Também no diretório: `.manifest`, `profiles.json`, `sha256sums`, `config.buildinfo`.

- `factory.ubi` → gravação via `ubiformat` em um slot (mtd12 = rootfs / mtd13 = rootfs_1)
- `sysupgrade.bin` → uso normal pelo OpenWrt (`sysupgrade`), grava no slot ativo automaticamente
- `initramfs-uImage.itb` → boot em RAM via **UART+TFTP** (teste sem tocar a NAND)

## 2. Arquivos do port

Árvore canônica: **`~/ax1800/openwrt/`** (espelhada em `~/ax1800/owrt-mnt/openwrt/`, que foi a árvore do build)

| Arquivo | Conteúdo |
|---|---|
| `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-xiaomi-ax1800.dts` | **DTS novo** (base: 360v6/glinet; include `ipq6018-512m.dtsi` + `ipq6018-ess.dtsi`; sem `cp-cpu`; nó memory **256MB** — o include 512m só ajusta o `q6_region`; `root=/dev/ubiblock0_1`) |
| `target/linux/qualcommax/image/ipq60xx.mk` | bloco `Device/xiaomi_ax1800`: `FitImage`+`UbiFit`, 128k/2048, `DEVICE_DTS := ipq6000-xiaomi-ax1800`, `DEVICE_DTS_CONFIG := config@cp03-c1`, SOC ipq6000 |
| `target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network` | caso `xiaomi,ax1800`: lan1-3 + wan |
| `target/linux/qualcommax/ipq60xx/base-files/etc/init.d/bootcount` | caso `xiaomi,ax1800` (START=99): lê `/proc/cmdline` (ubi.mtd=rootfs/rootfs_1) → `fw_setenv` `flag_boot_rootfs/boot_success/last_success/ota_reboot` + zera `flag_try_sys{1,2}_failed`. Guard: se `/dev/mtdN` não estiver no `/etc/fw_env.config`, adiciona a linha. Não-initramfs: no-op |
| `target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh` | `xiaomi_get_boot_part()` (cmdline + fallback `fw_printenv`) → `CI_UBIPART=rootfs/rootfs_1`; `remove_oem_ubi_volume ubi_rootfs` (libera o ID 1 p/ o novo volume `rootfs` pegar `ubiblock0_1`); `nand_do_upgrade "$1"` |
| `package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq60xx` | `xiaomi,ax1800) ubootenv_add_mtd "0:APPSBLENV" "0x0" "0x10000" "0x20000"` |
| `package/firmware/ipq-wifi/Makefile` | `ipq-wifi-xiaomi_ax1800` (+ wildcard do install estendido p/ usar o BDF local de `files/`) |
| `package/firmware/ipq-wifi/files/board-xiaomi_ax1800.ipq6018` | BDF PR71 (65.640 B) — variant `Xiaomi-AX1800` (sem MACs) |
| `.config` | perfil do build (device `xiaomi_ax1800` + LuCI + pacotes padrão) |

### Decisões de design relevantes
- **MACs**: LAN = ART `0x6` (XX:XX:XX:XX:XX:81), WAN/sticker = ART `0x18` (XX:XX:XX:XX:XX:8F) — `label-mac-device = &dp5` (WAN = sticker).
- **Ess**: PSGMII, `lan_bmp=ESS_PORT2|3|4`, `wan_bmp=ESS_PORT5`, `port_phyinfo` port@2..5 → phy 1..4, mdio com 5 phys (qca8075), reset tlmm GPIO 75 ACTIVE_LOW.
- **WiFi**: `qcom,ath11k-calibration-variant = "Xiaomi-AX1800"` + `fw-memory-mode = <1>`; sem `nvmem-cells` (evita colisão de MAC de rádio).
- **LEDs/tecla**: boot/failsafe/upgrade = amarelo (tlmm 30), running = azul (tlmm 29), net = azul/amarelo (tlmm 31/32); tecla reset tlmm 19 (`KEY_RESTART`, ACTIVE_LOW).
- **Partições do DTS** espelham o layout stock (16 partições, labels `0:SBL1`…`cfg_bak`); gravação somente em APPSBLENV/rootfs(12)/rootfs_1(13) pelo userspace.
- **OTA stock desativado** (`otapredownload` off) — evita o stock sobrescrever o slot.

## 3. Verificação end-to-end (antes do hardware)

- **DTS**: compilado com `cpp`+`dtc` (stubs/dt-bindings reais v6.12 + patch 0906 do OpenWrt p/ o nó `wifi`) → OK, só warnings benignos (os mesmos da família).
- **DTB final** (`image-ipq6000-xiaomi-ax1800.dtb`): `model = "Xiaomi Redmi AX1800"`; 16 partições; bmps 0x1c/0x20; reset mdio `<0x4b 0x01>`; `nvmem-cells` LAN→cell@6, WAN→cell@18; KEY_RESTART 0x198; `label-mac-device`.
- **factory.ubi** (parse UBI): layout vol (vtbl) + **kernel (vol 0, 43 PEBs)** + **rootfs (vol 1, 58 PEBs)**.
- **FIT do kernel extraído do UBI**: `default = "config@cp03-c1"` (o mesmo que o U-Boot stock usa!), kernel 6.12.87 gzip.
- **DTB embutido no FIT**: `bootargs-append = " root=/dev/ubiblock0_1"` ✓
- **rootfs do UBI**: squashfs OK; contém `bootcount`, `02_network`, `platform.sh`, `30_uboot-envtools`, `fw_printenv/fw_setenv`.
- **BDF**: `board-2.bin` dentro da imagem = **sha256 idêntico** ao nosso arquivo fonte (o override do brew funcionou).
- **sysupgrade.bin**: tar `sysupgrade-xiaomi_ax1800/{CONTROL,kernel,root}` (fluxo padrão da família gl-ax1800/360v6).
- Scripts: `dash -n` OK; pacote `ipq-wifi-xiaomi_ax1800` presente no manifest.

## 4. Como rebuildar

O build roda em container Docker (deps já instaladas na imagem `owrt-build-img`):

```bash
# se o container estiver parado:
docker start owrt-build

docker exec owrt-build bash -c 'cd /build && export FORCE_UNSAFE_CONFIGURE=1 && make -j$(nproc)'

# copiar imagens (bin/ é volume → copiar via tar):
docker exec owrt-build bash -c 'cd /build/bin/targets/qualcommax/ipq60xx && tar cf - openwrt-qualcommax-ipq60xx-xiaomi_ax1800-*' | tar xf - -C ~/ax1800/images
```

**Gotchas do ambiente (macOS + Docker Desktop):**
- VirtioFS não suporta *punch-hole* → `install(1)`/`cp` falham com "error deallocating". Solução: `staging_dir`, `build_dir`, `tmp`, `bin`, `dl` são **volumes Docker** (`/vol-*`) ligados por **symlink** na árvore.
- Build como root exige `FORCE_UNSAFE_CONFIGURE=1` (GNU tar/configure).

## 5. Plano de teste em hardware

### Opção A — **UART + TFTP (recomendada, zero risco à NAND)**
1. Conectar adaptador USB-TTL 3.3V nos pads UART (TX/RX/GND) — teclado no U-Boot.
2. `tftpboot` do `initramfs-uImage.itb` → `bootm` → OpenWrt rodando **em RAM**.
3. Validar: rede lan1-3/wan (+ ordem dos jacks com um cabo), MACs, WiFi (scan/associação), LEDs, tecla reset, `fw_printenv`, `ubiattach`/volumes.
4. Só então gravar: `ubiformat /dev/mtd13 -f factory.ubi` (slot 1) + flags + reboot. Recuperação garantida pelo console.

### Opção B — instalação direta no slot 1 (sem UART, risco médio)
Do SSH do firmware atual (custom):
```sh
scp factory.ubi root@192.168.31.1:/tmp/
ubiformat /dev/mtd13 -f /tmp/factory.ubi
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_boot_success=1
nvram set flag_ota_reboot=0
nvram commit && reboot
```
- Recuperação esperada: slot 0 intacto + auto-failover do U-Boot (`INFO: ota reboot failed, swap to old firmware!`) — **semântica do contador não confirmada** (só strings). Sem UART, se o failover não agir, é preciso UART.
- Depois do boot do OpenWrt: `sysupgrade` passa a gravar no slot ativo automaticamente (lógica em `platform.sh`).

### Opção C — só guardar as imagens (sem teste agora)

### Recuperação já preparada
- Slot 0 intacto (firmware atual com SSH) até o primeiro `ubiformat`.
- Dumps NAND completos em `~/ax1800/nand/` (mtd6 env, mtd7 u-boot, mtd12/13 rootfs).
- UART = recuperação garantida em qualquer cenário.

## 6. Teste em hardware — resultado real (2026-10-16)

**Gravação:** `factory.ubi` no slot 1 (mtd13 `rootfs_1`) via `ubiformat` (SSH do stock — Opção B), flags setadas
(`flag_boot_rootfs=1`, `flag_last_success=1`, `flag_boot_success=1`, `flag_ota_reboot=0`) + reboot.

**Resultado:** ✅ **boot limpo do slot 1 — a imagem sempre bootou.** Confirmações no dispositivo:
- `/proc/cmdline`: `ubi.mtd=rootfs_1 root=mtd:ubi_rootfs rootfstype=squashfs rootwait uart_en=1 root=/dev/ubiblock0_1`
- `bootcount`: `confirmed boot from rootfs slot 1`; `fw_printenv`: `flag_boot_rootfs=1`, `flag_boot_success=1`, `flag_try_sys1_failed=0`, `flag_try_sys2_failed=0`
- OpenWrt 25.12.4 (`r32933-4ccb782af7`), kernel 6.12.87 aarch64, LuCI + dropbear + odhcpd + dnsmasq rodando

**Causa raiz do falso "não boota":** `files/etc/uci-defaults/99-xiaomi-ax1800-lan` setava
`network.lan.ipaddr='192.168.31.1'` **sem máscara** → `br-lan` = `192.168.31.1/32` → **tabela de rotas v4 vazia**:
- kernel respondia **apenas ARP** (o roteador parecia U-Boot travado: sem ICMP/TCP/TFTP v4)
- dnsmasq: `unable to set dhcp-range ... on interface 'br-lan'` → sem servidor DHCP
- IPv6 (link-local + RA do odhcpd, ULA `fdc1:b62f:bc33::/48`) funcionava — foi o canal de entrada (SSH v6)

**Correção aplicada:**
- **Runtime** (persistente em `/etc/config`): `uci set network.lan.netmask='255.255.255.0'` + `uci commit network` + `ifup lan` + `/etc/init.d/dnsmasq restart`
- **Fonte** (para builds futuros): mesma correção em `files/etc/uci-defaults/99-xiaomi-ax1800-lan` — nas duas árvores (`openwrt/` e `owrt-mnt/openwrt/`)

**Validação pós-fix:** `br-lan 192.168.31.1/24` + rota `192.168.31.0/24`; ping v4 ≈0.9 ms; DHCP ACK (lease 192.168.31.198 no Mac);
LuCI `HTTP/1.1 200 OK`; SSH por v4 e v6; internet do cliente intacta (default segue na Wi-Fi, en0).

**Teste de reboot (2026-10-16):** ✅ reboot via SSH → IPv4 respondeu em ~20 s; `br-lan 192.168.31.1/24` + rota + dnsmasq com DHCPACK renovando lease; config persistido no overlay (`/overlay/upper/etc/config/network`, ubifs). `odhcpd`: "No default route present" no RA (esperado — sem WAN).

**Pendências opcionais:** senha do root (hoje em branco), Wi-Fi (LuCI), limpeza de processos órfãos no Mac (popup não autorizado — retry pendente).

## 7. Wi-Fi: calibração (cal/ART) — causa raiz e fix (2026-10-17)

**Sintoma:** os rádios ath11k subiam sem calibração → firmware não inicializava (nenhuma interface wireless).

**Causa raiz dupla:**
1. O `11-ath11k-caldata` **não tinha case** para `xiaomi,ax1800`/`redmi,ax1800` → a cal nunca era extraída da partição `0:ART`.
2. Mesmo extraindo manualmente, **o tamanho errado quebra o firmware**: os outros devices do mesmo script usam `0x20000` (128 KB), mas na NAND do AX1800 a cal termina em `0x11000` — de `0x11000` até `0x21000` é **100% `0xFF`** (região não gravada). Os 64 KB extras inválidos derrubavam o firmware ath11k ao carregar.

Comprovado no dump da partição (`~/ax1800/nand/mtd8_0_ART.bin`, 512 KB):
```
0x1000..0x11000: 65536 bytes, apenas  185 são 0xFF  ← cal válida
0x11000..0x21000: 65536 bytes, 65536 são 0xFF      ← lixo não gravado
```

**Correção definitiva (commitada nas 2 árvores — `280ce00` / `63c6eff`)** em `target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata`:
```sh
xiaomi,ax1800|\
redmi,ax1800)
	caldata_extract "0:ART" 0x1000 0x10000
	;;
```

**Band-aid no roteador:** `/etc/hotplug.d/firmware/20-xiaomi-ax1800-cal` — se a cal estiver ausente no boot, extrai da ART com `0x1000`/`0x10000` (no-op quando a hotplug já gerou a cal).

**Validação no roteador:** `ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin` = 65536 B + `board-2.bin` = 65640 B; STA associado ao AX9000 (canal 149) e APs `HomeNet` no ar (2.4 + 5 GHz). Estabilidade em modo repetidor: ver §8.

## 8. Modo AP/repetidor (relayd) — configuração e persistência (2026-10-17)

**Objetivo:** AX1800 como AP da rede do AX9000 (SSID `HomeNet` nos 2 canais), uplink pela própria Wi-Fi (repetidor), pronto para migrar para cabo.

**Topologia final:**
- `phy0-sta0` (5 GHz STA) pinado no BSSID `AA:BB:CC:DD:EE:FF` (AX9000, canal 149) → interface `wwan` (`proto relay`)
- `phy0-ap0` + `phy1-ap0`: SSID `HomeNet` → bridge `lan`
- `br-lan`: `192.168.1.2/24` (gestão) + `192.168.31.1/24` (backdoor na porta LAN)
- DHCP/odhcpd do AX1800 desligados (clientes pegam DHCP do AX9000 via relay)

**Pontos-chave do relayd (aprendidos na marra):**
1. **`option ipaddr '192.168.1.2'` na `wwan`** é a peça essencial — vira `-L 192.168.1.2` no relayd. Sem isso o roteador não responde ARP pelo próprio IP na rede de cima e a gestão pelo caminho relay não funciona.
2. **`-I br-lan -I phy0-sta0` não precisa ser configurado**: o script do `proto relay` resolve os nomes via `/var/state/network` (tmpfs, regenerado pelo netifd) e acha as interfaces sozinho a cada boot.
3. **Persistência confirmada em boot frio** (power-cycle): `relayd` subiu sozinho com a cmdline correta
   (`/usr/sbin/relayd -I br-lan -I phy0-sta0 -L 192.168.1.2 -B -D`), `ip rule` 16800/16801/16802 presentes, STA re-associado, ping/SSH/LuCI pelo caminho relay OK.
4. **O próprio roteador não é proxiado pelo relayd** (origem local, `iif lo`): o ARP para `192.168.1.1` via `br-lan` falha (`ip neigh` → `FAILED`) → `ping 192.168.1.1`, DNS e a rota default padrão não funcionam pelo bridge. Fixes persistidos no hotplug `/etc/hotplug.d/iface/99-fixsrc`:
   - `ip route replace default via 192.168.1.1 dev phy0-sta0` — rota default do próprio roteador direto pela STA (o kernel aceita rota via porta de bridge); com ela o roteador tem internet própria (NTP/apk/wget OK).
   - `ip rule add to 192.168.31.0/24 lookup main pref 1` — força `src 192.168.31.1` para a rede 31.x (sem isso, as respostas do Mac para 1.2 saíam pela Wi-Fi e o tráfego do "teste cabo" caía no ar).
   - `ip route replace 192.168.1.100/32 dev phy0-sta0` — rota /32 do Mac de teste direto pela STA. O ARP do host para IPs do lado HomeNet (que **não** sejam clientes dos nossos APs) via br-lan fica `INCOMPLETE` (mesmo quirk do item 4); sem ela, `Mac→1.2` (LuCI/SSH pelo relay) quebra, pois a resposta sai pelo br-lan e morre. Também em fixsrc + guard.
   - `option gateway '192.168.1.1'` **removido** da interface `lan` (uci): o netifd re-instalava `default via 192.168.1.1 dev br-lan` a cada re-setup da lan e brigava com a rota correta (ping-pong ≤55 s, internet do roteador intermitente). Sem o gateway na lan, o default via STA (fixsrc/guard) fica estável.
5. **Guard de auto-recuperação** (`/etc/init.d/guard`, START=99, habilitado; duas instâncias procd: `guard.sh` + `bait.sh`) — v4:
   - **Reboot**: `ping -c2 -W3 -I phy0-sta0 192.168.1.1` a cada ~55 s; após **6 falhas (~5,5 min)** reinicia (máx. **3 reboots/hora**; graça de 5 min pós-boot; registros em `/etc/guard/reboots`). Nunca mais power-cycle manual. ⚠️ O `-I phy0-sta0` é **obrigatório** (ver item 4) — sem ele o guard dá reboot falso com o relay 100% funcional.
   - **Blindagem OOM**: a cada ciclo força `oom_score_adj=-1000` nos daemons críticos (wpa_supplicant, hostapd, netifd, relayd, dropbear, uhttpd, rpcd, logd, syslogd, ubusd, ntpd, ubihealthd, crond, mon.sh, guard.sh) e no procd — o OOM killer não sacrifica mais a rede.
   - **Isca (`bait.sh`)**: processo inofensivo com `oom_score_adj=+1000`, supervisionado pelo procd — garante que o OOM sempre tenha uma vítima inofensiva antes de qualquer daemon.
   - **Reparo de rotas**: re-aplica `default via phy0-sta0`, a regra 31.x e o /32 do Mac se sumirem (auto-cura da internet própria do roteador).

**Operação (lado Mac) — lições dos testes:**
- `en7` (hub USB-C Lenovo) deve ficar **estático `192.168.31.100/24` apenas** (`networksetup -setmanual "Lenovo USB-C Hub" 192.168.31.100 255.255.255.0` + `ipconfig set en7 MANUAL 192.168.31.100 255.255.255.0`). Com DHCP, a en7 pegava `192.168.1.199` do AX9000 via relay → dual-homing na mesma L2 (dois MACs do Mac na rede 1.x) e rotas ambíguas.
- Cuidado com **ARP estático venenoso**: certa vez o Mac ficou com `192.168.1.2 → 3c:18:a0:bf:6f:9a permanent` (o próprio MAC da en7!) → todas as respostas para o roteador iam para o próprio adaptador → **stalls de 25 s** nos downloads. Limpar com `sudo arp -d 192.168.1.2`.
- Rotas no Mac: `192.168.31.0/24 → en7` (gestão via cabo) e `192.168.1.2/32 → en7` (opcional; gestão 1.2 via cabo).
- Caminho relay (testes): `ping -b en0 192.168.1.2` / `ssh -b 192.168.1.100 root@192.168.1.2`.

**Migração para cabo (quando quiser):** desabilitar a STA **antes** de plugar o cabo
(`uci set wireless.sta_uplink.disabled='1'; uci commit wireless; wifi reload`) — evita loop L2 (relay + cabo na mesma rede). **Desabilitar também o guard** (`/etc/init.d/guard disable; /etc/init.d/guard stop`) — em modo cabeado o ping `-I phy0-sta0` sempre falha e o guard reiniciaria o box sem necessidade. `wan` já está em DHCP caso queira modo router.

## 9. Memória, OOM e NSS — o limite real do mainline (2026-10-17)

### 9.1 NSS
- O target qualcommax **inclui o NSS Data Plane** (`qca_nss_dp` + `qca_ssdk`; dmesg: `NSS Data Plane driver`) — mas **só para Ethernet** (MACs do switch).
- **Wi-Fi não tem offload NSS no mainline**: os rádios rodam ath11k puro, datapath na CPU + firmware Q6. O vendor (QSDK) usa NSS também no Wi-Fi; no mainline isso não existe — "ligar NSS no Wi-Fi" exigiria portes do QSDK (projeto separado).
- Na prática: tráfego Wi-Fi→Wi-Fi (repetidor) passa 100% por CPU/firmware; o NSS Ethernet ajuda pouco nesse cenário.

### 9.2 Onde a memória vai (256 MB físicos)
- **~103 MB reservados fora do Linux** (`Memory: 157440K/262144K available`, 0 CMA): regiões `nomap` do DTS (Q6/WCSS 55 MB @ `0x4ab00000`, 16 MB @ `0x40000000`, bootloader/SBL etc.) + imagem do kernel.
- Dos ~157 MB gerenciáveis, **~100 MB não aparecem** nos contadores usuais (anon/file/slab) — são alocações DMA/coherent do datapath (ath11k em `FW memory mode: 1` + pools do SSDK/NSS), unreclaimable. Os processos de usuário são minúsculos (o `rpcd` morto pelo OOM tinha **384 KB de RSS**).
- Resultado: `MemFree` ocioso crônico de **16–20 MB**; `MemAvailable` ≈ 0–1 MB.
- `min_free_kbytes` default = **16384 kB**: o free ocioso flutua *exatamente* nesse limite → **qualquer pico dispara direct reclaim → OOM killer em cascata**.

### 9.3 O colapso observado
- Num teste de download de 160 MB, o OOM disparou **8×**: matou `rpcd` (3×), `hostapd`, **`wpa_supplicant`** (→ STA desautenticou → relay morto), `netifd`, `wget`.
- Com procd respawnando os serviços, cada respawn realocava → novo OOM; o dump do kernel (enorme, impresso bem devagar) mantinha a caixa semi-parada: **kernel pinga (0,8 ms), TCP aceita, mas dropbear/uhttpd não completam** — era exatamente o "travamento" visto antes (wedge).
- **Evidência:** syslog remoto do AX1800 → Mac (UDP 5141) capturou tudo (`invoked oom-killer`, `Out of memory: Killed process ...`, `DMA free:16624kB min:16384kB`).

### 9.4 Mitigações aplicadas (estado final)
- `vm.min_free_kbytes=4096` — **valor final**. Com o default (16384) e com 8192 o box ainda entrava em OOM/reclaim-storm sob transferência (o free mergulha 4–8 MB durante TCP; com 8192 o mergulho tocava o piso → 4–5 OOMs por bateria + paradas). Com 4096 (low=5120) os mergulhos normais ficam acima do watermark → **zero reclaim, zero OOM** nos testes finais.
- Caps de buffer TCP: `tcp_rmem`/`tcp_wmem` máx **512 KB**, `core.rmem_max`/`wmem_max` **512 KB** — limita picos por conexão
- `nf_conntrack_max=8192` — limita a tabela de conexões
- **`dnsmasq` e `odhcpd` desligados** (em modo relay não servem nada — o AX9000 faz DHCP/DNS); DNS do próprio roteador via `nameserver 192.168.1.1` em `/etc/resolv.conf`. Baseline de free subiu para ~16–20 MB.
- Persistidos em `/etc/sysctl.conf` (aplicados no boot pelo init `sysctl`)
- **Drenagem de RX**: `net.core.netdev_budget=600` + `net.core.dev_weight=128` (persistidos) — softirq drena os anéis de RX mais rápido sob rajada sustentada.
- **Blindagem OOM + isca** (detalhes no §8.5): daemons a `-1000`, `bait.sh` a `+1000` — sob OOM sustentado as vítimas passam a ser apenas isca/processos de teste, e a rede (Wi-Fi/relayd/rotas) fica de pé. Validado em campo.
- **Insight**: o OOM sob carga sustentada é disparado por **processos locais do roteador** (ex.: `wget`, `apk` — sockets locais via `do_epoll_ctl`). O tráfego dos **clientes é bridged** (sem socket local) — não há invocador de OOM nele; no máximo drops de pacote (alocação GFP_ATOMIC) sem matar processos.
- Num episódio de OOM (00:22) o `logd` morreu (blackout de syslog por ~4 min) e ~4 min depois o box reiniciou sozinho **sem rastro no log** (provável reset pós-storm — watchdog/ubihealthd, sem evidência conclusiva); a recuperação automática foi **completa**. Não recorreu após blindagem + isca + remoção do gateway da lan.
- **Instrumentação permanente**: `mon.sh` (procd, a cada 30 s → syslog remoto) com uptime/free/avail/contadores STA+sig/relayd
- **Guard de auto-recuperação** (`/etc/init.d/guard`, habilitado): reboot gracioso se o uplink ficar inalcançável por ~5,5 min (máx. 3/hora) — substitui o power-cycle manual. Detalhes no §8.
- zram: **indisponível neste kernel** (sem módulo/device) — descartado (precisaria de rebuild).
- `fw_mem_mode`: é propriedade **DTS** (`qcom,ath11k-fw-memory-mode`, valor 1 no nosso DTS) — não é ajustável em runtime e não há evidência de ganho de RAM; não alterado (exigiria rebuild+reflash).

### 9.5 Throughput (medido em 2026-10-18, com as mitigações finais)
- Link STA: **HE 80 MHz 2x2** — rx 1200 Mbps / tx 960 Mbps (phy), sinal **-34 dBm**.
- Cliente HTTP no Mac (en0 `192.168.1.100` na Wi-Fi do AX9000; en7 `192.168.31.100` no cabo). 1 fluxo TCP. **Zero OOM durante toda a bateria.**

| Caminho | Direção | Payload | Taxa |
|---|---|---|---|
| **Cabo** (br-lan) | download | 16 MB | 568 Mbps |
| **Cabo** (br-lan) | download | 40 MB | **758 Mbps** |
| **Cabo** (br-lan) | upload | 16 MB | 391 Mbps |
| **Relay Wi-Fi** (STA) | download | 16 MB (×2) | 137,6 Mbps |
| **Relay Wi-Fi** (STA) | download | 40 MB | **161 Mbps** |
| **Relay Wi-Fi** (STA) | upload | 16 MB | 273,5 Mbps |
| **Cabo** (br-lan) | download | 160 MB | **885 Mbps** (1,54 s) — melhor medição |
| **Relay Wi-Fi** (STA) | download | 160 MB sustentado | 121,8 Mbps (burst; o full-blast sustentado local pode sacrificar o `wget` por OOM — por design, §9.4) |

- O relay Wi-Fi faz **duas travessias do ar por pacote** (Mac→AX9000→AX1800 e volta) — taxas de 135–275 Mbps são típicas desse cenário de canal compartilhado.
- No cabo, as transferências terminam em <0,5 s (bursts) — o número de 40 MB é o mais confiável; a CPU do ipq6018 limita ~750 Mbps em single-flow.
- Validação: transferências completas confirmadas nos contadores das interfaces (br-lan `rx` p/ cabo; phy0-sta0 `rx`/`tx` p/ relay) e no log HTTP do servidor (HTTP 200).

## 10. Memória futura: o `q6_region` de 55 MB (experimento — NÃO validado)

**Correção (18/10, revisão minuciosa):** a região `memory@4ab00000` de 55 MB **não é reserva do NSS** — é o **`q6_region`**, a memória do **firmware do Q6/WCSS (Wi-Fi)**, referenciada pelo remoteproc `q6v5_wcss` (dmesg: `remoteproc0: Booting fw image IPQ6018/q6_fw.mdt`). Ela **não pode ser simplesmente removida**: o firmware do Wi-Fi não sobe sem ela. Um experimento possível (rebuild do FIT + reflash + console serial disponível) seria **reduzir** o tamanho (ex.: 47 MB) e validar o boot do firmware — **não executado**.

## 11. Validação noturna (2026-10-18, ~00:36–09:00)

Operação autônoma de validação: (a) teste de ponta a ponta do guard (derrubar a STA de propósito → reboot automático → recuperação completa); (b) monitor contínuo por ~8 h — checagens a cada ~10 min (cabo, relay, SSH, memória, OOM, STA, guard, isca) + teste leve de 4 MB a cada hora nos dois caminhos + LuCI; (c) `caffeinate` no Mac para não dormir. Logs: `guardtest.log`, `overnight.log`, `overnight_summary.txt` (em `$TMP/opencode/`).

**Resultado parcial (madrugada):**
- **Teste E2E do guard: APROVADO** — `wifi down` às 00:35:50 → **reboot automático às ~00:41:20** (uptime 857→26; registro em `/etc/guard/reboots`) → recuperação completa em ~1 min (STA/relayd/guard/isca no ar, ping e wget pelo relay OK, rotas /32 e default repostas).
- Ajuste pós-teste: blindagem extra do `fixroute`/fixsrc (apagar default residual via `br-lan` antes de repor) — **guard v5**.
- Carga sustentada (o teste que originalmente derrubava a caixa): **cabo 160 MB a 885 Mbps**; relay 160 MB em burst a ~122 Mbps até o OOM sacrificar o `wget` local (comportamento por design — daemons blindados, Wi-Fi permaneceu de pé).

### 11.1 Resultado final da noite (48/48 ciclos)
- **Rede 100% OK em todos os 48 ciclos** de ~9 min (cabo + relay + STA + relayd no ar), incluindo os ciclos imediatamente após cada reboot.
- Throughput amostrado (4 MB/hora, cada caminho): **cabo 117–244 Mbps** (pico 244,1); **relay 24–103 Mbps**. LuCI 200/200 nos dois caminhos (1 único 000 durante tempestade). Zero falhas de SSH.
- Mínimos: `free 6.156 kB` / `avail 4.356 kB` (banda normal do box: avail ~4–28 MB).

### 11.2 Rebotes silenciosos da noite: causa investigada e mecanismo
**~18 reboots espontâneos** (00:26 → 08:28; o monitor detectou 16; ~1 a cada 20–35 min), **todos auto-recuperados** (rede volta em ~1–2 min, sem intervenção; guard/isca/rotas OK a cada vez). Causa-raiz investigada com probe forense próprio (`memprobe.sh`) + coletor syslog no Mac:
- **Não é vazamento**: Slab/SUnreclaim (~24,7 MB)/KernelStack/PageTables/VmallocUsed/Committed_AS todos **planos** ao longo do boot e entre boots.
- **Não é térmico** (48–49 °C), **nem THP** (kernel sem Transparent HugePage), **nem guard/isca** (arquivo de reboots do guard intacto; scripts revisados).
- **Mecanismo (evidência direta)**: tempestades de **OOM a cada ~20–35 min** — falhas de alocação **ordem-0 com ~7–8 MB livres** (anômalo; suspeita de peculiaridade de watermark/fragmentação do kernel vendor 6.12.87) → o OOM killer mata só a isca (+1000) e **re-invoca repetidamente** (até 17×/min) → sistema em reclaim duro por >30 s → **`procd` não alimenta o watchdog de hardware `qcom_wdt` (timeout 30 s)** → **reset sem log** (panic=10 ativo desde 07:48 e o reboot de 07:58 não teve rastro algum → reset duro, não pânico).
- **Fatores**: box com **160 MB gerenciáveis de 256 MB** (~96 MB reservados, incl. 55 MB do NSS §10) e folga real de poucos MB; bursts transientes (`iw`, `wget`, downloads de 4 MB, forks de daemons) entram como gatilho na faca.
- (`vm.min_free_kbytes=8192` foi testado de manhã e **piorou** — reclaim permanente; revertido para 4096.)

### 11.3 Endurecimento aplicado em 18/10 (manhã)
- `panic=10` + `panic_on_oops=1` (forense de pânico; upstream de log garantido).
- Scripts do monitor **afinados** para reduzir bursts: `mon.sh` sem `iw` a cada 30 s (agora 1×/2,5 min, cacheado), `check.sh` com 1 `iw` em vez de 2, `guard.sh` com 1 `ps` por ciclo (antes 18).
- **Probe forense** `memprobe.sh` (10 s; meminfo completo + top-RSS + buddyinfo + zoneinfo sob pressão) → syslog → coletor no Mac.
- **Válvula de alívio** `relief.sh` (procd): `drop_caches` quando `free<6 MB` ou `avail<5 MB` — quebra a escalada da tempestade.
- Blindagem OOM (adj −1000) + isca (+1000) + guard v5 seguem ativos.

### 11.4 Pendências
- **Rebuild com `CONFIG_PACKAGE_relayd=y`** — achado da revisão de código (18/10): o pacote foi instalado no roteador **após** o flash; a imagem validada não o inclui.
- **Experimento `q6_region`** (§10 corrigido): reduzir o tamanho exige rebuild+reflash+console — **não validado**.
- Revalidar uma 2ª noite após o endurecimento; se as tempestades persistirem, investigar o watermark do kernel vendor com console serial.
