# 01 — Hardware: Xiaomi Redmi AX1800 (RM1800)

## Ficha técnica

| Item | Valor |
|---|---|
| Modelo | Xiaomi Redmi AX1800 (`RM1800`) |
| SoC | Qualcomm **IPQ6000** (família IPQ6018), 4× Cortex-A53 |
| RAM | **256 MB** (DDR3L) — o DTS declara 256 MB @ `0x40000000` |
| NAND | **128 MB** SPI-NAND via QPIC (páginas 2 KB, blocos 128 KB) |
| Wi-Fi | IPQ6018 integrado (ath11k): 2×2 **5 GHz** (HE80) + 2×2 **2,4 GHz** (HE20) |
| Ethernet | QCA8075 (5 portas PHY) via **PSGMII**: 3× LAN + 1× WAN |
| Botão | reset (GPIO 19, ativo em nível baixo) |
| LEDs | status azul/amarelo (GPIO 29/30) + net azul/amarelo (GPIO 31/32) |
| Console | UART 3,3 V, **115200 8N1** (pads na placa) |
| Boot | U-Boot stock com **dois slots** (`rootfs` / `rootfs_1`) e flags de A/B |

## Mapa de memória (visão do Linux)

O kernel recebe 256 MB físicos, mas **~100 MB são reservados** (`nomap`,
non-reusable) para firmware/secure world. Dados reais do `dmesg` no
equipamento com este port:

```
OF: reserved mem: 0x0000000000060000..0x0000000000065fff (24 KiB)     memory@60000
OF: reserved mem: 0x0000000040000000..0x0000000040ffffff (16384 KiB)  memory@40000000
OF: reserved mem: 0x000000004a100000..0x000000004a4fffff (4096 KiB)   bootloader@4a100000
OF: reserved mem: 0x000000004a500000..0x000000004a5fffff (1024 KiB)   sbl@4a500000
OF: reserved mem: 0x000000004a600000..0x000000004a9fffff (4096 KiB)   memory@4a600000
OF: reserved mem: 0x000000004aa00000..0x000000004aafffff (1024 KiB)   memory@4aa00000
OF: reserved mem: 0x000000004ab00000..0x000000004e1fffff (56320 KiB)  memory@4ab00000
Memory: 157440K/262144K available (102980K reserved, 0K cma-reserved)
```

- **`memory@4ab00000` (55 MB)** é o **`q6_region`**: a região de memória do
  **firmware do Q6/WCSS** (o `remoteproc@cd00000` / `q6v5_wcss` que carrega o
  `IPQ6018/q6_fw.mdt` e roda o Wi-Fi). O `ipq6018-512m.dtsi` ajusta o tamanho
  dessa região. **Não é “reserva do NSS”** e não pode ser simplesmente
  removida — o firmware não sobe sem ela. Ver
  [07-memory-and-oom.md](07-memory-and-oom.md) para a anatomia completa.
- `MemTotal` reportado pelo Linux: **160 124 kB** (~156 MB).

## Layout da NAND (16 partições, espelho do stock)

| # | Label | Offset | Tamanho | Uso no port |
|---|---|---|---|---|
| 0 | `0:SBL1` | `0x000000` | 1,5 MB | bootloader primário (ro) |
| 1 | `0:MIBIB` | `0x180000` | 1 MB | tabela de boot (ro) |
| 2 | `0:QSEE` | `0x280000` | 3,5 MB | secure world (ro) |
| 3 | `0:DEVCFG` | `0x600000` | 512 KB | config de device (ro) |
| 4 | `0:RPM` | `0x680000` | 512 KB | resource power manager (ro) |
| 5 | `0:CDT` | `0x700000` | 512 KB | config de DDR (ro) |
| 6 | `0:APPSBLENV` | `0x780000` | 512 KB | **U-Boot env** (flags A/B) |
| 7 | `0:APPSBL` | `0x800000` | 1,5 MB | U-Boot (ro) |
| 8 | `0:ART` | `0x980000` | 512 KB | **calibração + MACs** (ro) |
| 9 | `bdata` | `0xa00000` | 512 KB | dados de fábrica (ro) |
| 10 | `crash` | `0xa80000` | 512 KB | crashlog stock (ro) |
| 11 | `crash_syslog` | `0xb00000` | 512 KB | crashlog stock (ro) |
| 12 | `rootfs` | `0xb80000` | 44,5 MB | slot A (UBI) |
| 13 | `rootfs_1` | `0x3800000` | 44,5 MB | slot B (UBI) — slot usado pelo port |
| 14 | `overlay` | `0x6480000` | 22,5 MB | partição stock (não usada; ro no DTS) |
| 15 | `cfg_bak` | `0x7b00000` | 512 KB | backup de config stock (ro) |

> O overlay persistente do OpenWrt **não** usa a partição 14: ele é criado
> como volume UBIFS dentro do UBI do slot ativo.

## ART: calibração e MACs

O setor `0:ART` (512 KB) contém, no início, os dados de calibração do rádio e
os MACs de fábrica:

- **calibração válida:** `0x1000` … `0x11000` (**64 KB**); do fim desse bloco
  até `0x21000` o conteúdo é `0xFF` (região não gravada). Este é o motivo da
  correção do script de cal (ver [05-calibration.md](05-calibration.md)).
- **MAC LAN:** offset `0x6` (6 bytes) → usado por `lan1..lan3` e bridge.
- **MAC WAN:** offset `0x18` (6 bytes) → usado pela porta `wan`; é o MAC da
  etiqueta do produto (`label-mac-device = &dp5`).

## Boot chain (U-Boot stock)

1. BootROM → SBL → U-Boot (`0:APPSBL`).
2. O U-Boot lê o ambiente em `0:APPSBLENV` e escolhe o slot conforme
   `flag_boot_rootfs` / `flag_last_success` / `flag_try_sysN_failed`.
3. Carrega o **FIT** do slot (config `config@cp03-c1`), com o DTB embutido e
   `bootargs-append root=/dev/ubiblock0_1`.
4. O OpenWrt sobe do volume `rootfs` do UBI do slot ativo; o init `bootcount`
   confirma o slot (`flag_boot_success=1`) — senão o U-Boot volta ao outro slot.

Flags observadas no equipamento após o boot (via `fw_printenv`):

```
flag_boot_rootfs=1
flag_boot_success=1
flag_last_success=1
flag_ota_reboot=0
flag_try_sys1_failed=0
flag_try_sys2_failed=0
```

## Acesso físico

- **UART:** 3,3 V, 115200 8N1. Com o console, o U-Boot pode ser interrompido e
  um `initramfs` carregado via TFTP — modo de teste/recuperação sem tocar na
  NAND.
- **TFTP no U-Boot:** `tftpboot` + `bootm` (imagem `initramfs-uImage.itb`).

## Observações de projeto

- O DTS usa `#include "ipq6018-512m.dtsi"` (nome herdado da família, que apenas
  ajusta a região `q6_region`) e **sobrescreve o nó de memória para 256 MB**.
- `compatible = "xiaomi,ax1800", "qcom,ipq6018"`.
- O `qcom,ath11k-fw-memory-mode = <1>` é propriedade de DTS (não ajustável em
  runtime) e foi mantido como no stock.
