# 04 — Gravação, primeiro boot e recuperação

> ⚠️ **Leia tudo antes de gravar.** Tenha o dump da NAND, o adaptador UART e o
> firmware stock à mão. O procedimento abaixo foi executado e validado no
> hardware real, mas gravar firmware não-oficial tem risco de brick.

## 0. Antes de tudo: backups

Com o firmware stock (ou custom com SSH) acessível:

```sh
# ambiente usado: dumps completos em ~/ax1800/nand/
dd if=/dev/mtd6  of=/tmp/mtd6_APPSBLENV.bin    # U-Boot env (flags A/B)
dd if=/dev/mtd7  of=/tmp/mtd7_APPSBL.bin       # U-Boot
dd if=/dev/mtd8  of=/tmp/mtd8_ART.bin          # ART (calibração + MACs) — NUNCA perca
dd if=/dev/mtd12 of=/tmp/mtd12_rootfs.bin      # slot A
dd if=/dev/mtd13 of=/tmp/mtd13_rootfs_1.bin    # slot B
```

Guarde também `nvram show`/`fw_printenv` e o `factory.ubi` original.

## Opção A — UART + TFTP (teste sem tocar na NAND) — recomendada

1. Conecte um adaptador USB-TTL **3,3 V** nos pads UART (TX/RX/GND) da placa e
   abra o console a **115200 8N1**.
2. Ligue o roteador e interrompa o U-Boot (tecla durante o boot).
3. Suba um servidor TFTP no seu computador com o `initramfs-uImage.itb` e, no
   console do U-Boot:

```
setenv ipaddr 192.168.31.10
setenv serverip 192.168.31.100
tftpboot 0x44000000 openwrt-qualcommax-ipq60xx-xiaomi_ax1800-initramfs-uImage.itb
bootm 0x44000000
```

4. O OpenWrt sobe **em RAM**. Valide rede (LAN/WAN), Wi-Fi (scan/associação),
   LEDs, tecla reset, `fw_printenv` e `ubinfo`.
5. Só então grave na NAND.

## Opção B — instalação no slot 1 via SSH (usada no hardware)

Do firmware atual (com SSH habilitado):

```sh
scp openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1
ubiformat /dev/mtd13 -f /tmp/openwrt-...-factory.ubi   # slot 1 (rootfs_1)
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_boot_success=1
nvram set flag_ota_reboot=0
nvram commit && reboot
```

- O **slot 0 permanece intacto** (recuperação pelo próprio U-Boot em caso de
  falha do slot 1).
- No stock, `nvram` é o wrapper do Xiaomi para o env do U-Boot; no OpenWrt o
  equivalente é `fw_setenv` (o init `bootcount` já mantém os flags).

## Primeiro boot — checklist de validação

No OpenWrt recém-bootado:

```sh
cat /proc/cmdline        # deve conter: ubi.mtd=rootfs_1 ... root=/dev/ubiblock0_1
logread | grep bootcount # "confirmed boot from rootfs slot 1"
fw_printenv | grep flag_ # flag_boot_rootfs=1, flag_boot_success=1, ...
ls -l /lib/firmware/ath11k/IPQ6018/hw1.0/cal-*.bin   # 65536 bytes
iw dev                   # phy0/phy1 + interfaces
ping 192.168.1.1         # (se estiver como repetidor/cliente)
```

- `fw_printenv` deve funcionar direto (`/etc/fw_env.config` → `/dev/mtd6`).
- **Wi-Fi**: se as interfaces não subirem, confira a calibração
  ([05-calibration.md](05-calibration.md)).

## O bug da máscara `/32` (importante)

Na primeira instalação, o OpenWrt subiu com `network.lan.ipaddr='192.168.31.1'`
**sem máscara**. O netifd aplicou `/32`, o que deixou:

- a `br-lan` com `192.168.31.1/32` e **nenhuma rota IPv4** (`ip route` vazio);
- o kernel respondendo **apenas ARP** (ICMP/TCP IPv4 não funcionavam — parecia
  U-Boot travado);
- `dnsmasq` sem conseguir criar o DHCP (`unable to set dhcp-range`);
- IPv6 link-local/RA funcionando (foi por ali que o acesso inicial aconteceu).

Correção (runtime e fonte):

```sh
uci set network.lan.netmask='255.255.255.0'
uci commit network
ifup lan
/etc/init.d/dnsmasq restart
```

No build, o overlay
[`src/overlay/files/etc/uci-defaults/99-xiaomi-ax1800-lan`](../src/overlay/files/etc/uci-defaults/99-xiaomi-ax1800-lan)
já define IP **e máscara**.

## Teste de reboot e persistência

```sh
reboot
```

- IPv4 responde ~20 s após o reboot.
- A configuração persiste no overlay (`/overlay/upper/etc/config/...`).

## Atualizações (sysupgrade / A/B)

```sh
sysupgrade -n /tmp/openwrt-...-sysupgrade.bin   # -n = não preservar config
```

- O `platform.sh` do port grava no **slot alternado** e ajusta os flags; o
  boot seguinte usa o slot novo.
- Se o boot falhar, o U-Boot volta ao slot anterior (failover do stock).

## Recuperação de emergência

| Cenário | Ação |
|---|---|
| Boot loop / slot novo não sobe | deixar o U-Boot alternar (failover); se não alternar, console UART + `run` do slot antigo |
| Firmware corrompido | UART + TFTP: `tftpboot` do `initramfs` → regravar o `factory.ubi` com `ubiformat` no slot |
| ART corrompida | restaurar `mtd8_ART.bin` pelo console (último recurso; sem ART não há Wi-Fi/MACs) |
| Esqueceu a senha | failsafe (LED piscando) → `mount_root` → `passwd`; ou console |

> Os dumps do equipamento de teste estão preservados no acervo do autor
> (`~/ax1800/nand/`), incluindo `mtd8_0_ART.bin` — a base da análise da
> calibração.
