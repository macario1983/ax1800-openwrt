# 02 — Desenho do port (o que foi adicionado e por quê)

O patch [0001-ipq60xx-add-Xiaomi-AX1800.patch](../src/patches/0001-ipq60xx-add-Xiaomi-AX1800.patch)
toca 9 arquivos (`+444 −1` linhas). Abaixo, o papel de cada um — os detalhes de
revisão/risco estão em [09-code-review.md](09-code-review.md).

## 1. DTS — `ipq6000-xiaomi-ax1800.dts`

Arquivo novo em `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/`.

```
model = "Xiaomi Redmi AX1800"
compatible = "xiaomi,ax1800", "qcom,ipq6018"
chosen: bootargs-append = " root=/dev/ubiblock0_1"
memory: reg = <0x0 0x40000000 0x0 0x10000000>   // 256 MB
```

Pontos principais:

- **Includes**: `ipq6018-512m.dtsi` (apenas ajusta `q6_region` — **não** define
  memória) + `ipq6018-ess.dtsi` (ESS switch/EDMA/dp2..dp5). O nó `&wifi` vem do
  patch do target `0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch`.
- **Partições**: as 16 do stock, com tamanhos idênticos (ver
  [01-hardware.md](01-hardware.md)). `rootfs`/`rootfs_1` são os slots UBI;
  `0:APPSBLENV` recebe os flags de boot.
- **MACs**: `nvmem-layout` sobre `0:ART` expõe `macaddr@6` (LAN) e `macaddr@18`
  (WAN); `aliases { label-mac-device = &dp5; }` faz a etiqueta virar o MAC da
  WAN.
- **Switch**: `switch_lan_bmp = ESS_PORT2|3|4`, `switch_wan_bmp = ESS_PORT5`,
  `MAC_MODE_PSGMII`; `qcom,port_phyinfo` liga port@2..5 aos PHYs 1..4 do
  qca8075; reset do MDIO no GPIO 75 (ativo baixo).
- **Rede**: `&dp2..&dp5` com `label = lan1/lan2/lan3/wan` e `nvmem-cells`.
- **Wi-Fi**: `qcom,ath11k-calibration-variant = "Xiaomi-AX1800"` e
  `qcom,ath11k-fw-memory-mode = <1>`.
- **LEDs/tecla**: status azul/amarelo (29/30), net azul/amarelo (31/32);
  reset no GPIO 19 (`KEY_RESTART`).

## 2. Imagem — `image/ipq60xx.mk`

```make
define Device/xiaomi_ax1800
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Xiaomi
	DEVICE_MODEL := Redmi AX1800
	DEVICE_DTS := ipq6000-xiaomi-ax1800
	DEVICE_DTS_CONFIG := config@cp03-c1
	SOC := ipq6000
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_PACKAGES := ipq-wifi-xiaomi_ax1800 uboot-envtools
	SUPPORTED_DEVICES += xiaomi,ax1800
endef
TARGET_DEVICES += xiaomi_ax1800
```

- `DEVICE_DTS_CONFIG := config@cp03-c1` reproduz o **mesmo config FIT que o
  U-Boot stock usa** (verificado extraindo o kernel do UBI).
- Gera `factory.ubi` (para `ubiformat`), `sysupgrade.bin` e o
  `initramfs-uImage.itb` (boot em RAM).

## 3. `board.d/02_network`

```sh
xiaomi,ax1800)
	ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"
	;;
```

Mapeia as portas conforme o DTS. Sem isso, o OpenWrt sobe sem `br-lan`/`wan`
corretos.

## 4. `bootcount` (confirmação de boot A/B)

Adiciona o case `xiaomi,ax1800` no init de boot:

- garante `/etc/fw_env.config` apontando para o MTD do `0:APPSBLENV` (o arquivo
  é criado no primeiro boot pelo `30_uboot-envtools`; o guard cobre os boots
  seguintes se algo regredir) — usa `find_mtd_index`, disponível via
  `/lib/functions.sh` (carregado pelo `rc.common`);
- descobre o slot pelo `/proc/cmdline` (`ubi.mtd=rootfs` → 0,
  `ubi.mtd=rootfs_1` → 1);
- **no initramfs** (sem `ubi.mtd` na cmdline) o script é no-op;
- confirma o boot no U-Boot env:

```
flag_boot_rootfs <slot>
flag_boot_success 1
flag_last_success <slot>
flag_ota_reboot 0
flag_try_sys1_failed 0
flag_try_sys2_failed 0
```

Sem essa confirmação, o U-Boot considera o boot falho e pode voltar ao outro
slot (comportamento de recuperação do stock).

## 5. `platform.sh` (sysupgrade para o slot alternado)

- `xiaomi_get_boot_part()`: descobre o slot atual pela cmdline e, como
  fallback (ex.: rodando initramfs), por `fw_printenv flag_boot_rootfs`.
- `remove_oem_ubi_volume ubi_rootfs`: remove o volume OEM com ID 1 para que o
  novo `rootfs` receba o ID 1 e o `ubiblock0_1` continue válido — detalhe
  crítico herdado do stock (o bootargs aponta para `ubiblock0_1`).
- `nand_do_upgrade "$1"`: fluxo padrão de gravação em NAND do OpenWrt
  (escreve no slot alternado e ajusta os flags).

## 6. `uboot-envtools`

```sh
xiaomi,ax1800)
	ubootenv_add_mtd "0:APPSBLENV" "0x0" "0x10000" "0x20000"
	;;
```

Registra o env do U-Boot: offset `0x0`, tamanho `0x10000`, setor `0x20000`.
No equipamento isso resulta em `/etc/fw_env.config` com `/dev/mtd6`.

## 7. `ipq-wifi` (Makefile + BDF)

- Adiciona `xiaomi_ax1800` em `ALLWIFIBOARDS` e o pacote
  `ipq-wifi-xiaomi_ax1800` (`DEVICE_PACKAGES` da imagem).
- Estende o wildcard de `install-overlay` para incluir
  `$(CURDIR)/files/board-$(1).*` — assim o BDF pode viver na própria árvore do
  port. **É a única mudança “global” do patch** (ver riscos em
  [09-code-review](09-code-review.md)).
- BDF: `board-xiaomi_ax1800.ipq6018` (65 640 B, variant `Xiaomi-AX1800`, sem
  MACs) → instalado como `board-2.bin` do ath11k `IPQ6018/hw1.0`.

## 8. `11-ath11k-caldata` (correção da calibração)

```sh
xiaomi,ax1800|\
redmi,ax1800)
	caldata_extract "0:ART" 0x1000 0x10000
	;;
```

Extrai **64 KB** (`0x10000`) a partir de `0x1000` da ART. O padrão dos outros
boards (128 KB) quebrava o firmware porque `0x11000..0x21000` é `0xFF` —
histórico completo em [05-calibration.md](05-calibration.md).

## 9. Overlay de build — `files/etc/uci-defaults/99-xiaomi-ax1800-lan`

Fora do patch (diretório de conteúdo local da árvore), incluído neste
repositório em [src/overlay](../src/overlay):

```sh
uci set network.lan.ipaddr='192.168.31.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network
```

- Mantém o IP de gestão do firmware original (`192.168.31.1`) em vez do
  `192.168.1.1` default do OpenWrt (que colidiria com a rede do roteador
  principal no modo repetidor).
- A **máscara explícita** corrige o bug que deixava a `br-lan` como `/32`
  (sem rota v4, sem DHCP, “parecendo travado”) — ver
  [04-flash-and-recovery.md](04-flash-and-recovery.md).

## Desvios em relação ao upstream (resumo)

| Desvio | Motivo | Impacto |
|---|---|---|
| Wildcard do `ipq-wifi/Makefile` | manter o BDF na árvore | baixo (só age se o arquivo existir) |
| `99-xiaomi-ax1800-lan` em `files/` | corrigir IP/máscara no primeiro boot | nenhum em outros boards |
| `bootcount` com `find_mtd_index` | robustez do `fw_env.config` | nenhum em outros boards |

O restante segue exatamente os padrões da família `qualcommax/ipq60xx`
(`Device/FitImage` + `Device/UbiFit`, `nand_do_upgrade`, `caldata_extract`).
