# OpenWrt para o Xiaomi Redmi AX1800 (RM1800)

Port não-oficial do **OpenWrt 25.12.4** para o **Xiaomi Redmi AX1800** (modelo
`RM1800`, SoC `IPQ6000` da família IPQ6018), com suporte completo a boot A/B,
Wi-Fi calibrado (ath11k), `sysupgrade`, LuCI e um conjunto de ajustes
operacionais testados em campo — incluindo modo **repetidor/AP (relayd)** com
auto-recuperação.

> English abstract: this repository contains a community OpenWrt port for the
> Xiaomi Redmi AX1800 (IPQ6000), including the device tree, BDF/firmware
> calibration fix, A/B boot glue, build configuration and a battle-tested
> relay/repeater hardening kit (`relayd` + watchdog/guard scripts).

---

## Status

| Item | Estado |
|---|---|
| Boot no hardware | ✅ validado (slot A/B, U-Boot stock) |
| Layout de NAND / partições | ✅ espelha o stock (16 partições) |
| Ethernet (3×LAN + WAN, qca8075) | ✅ validado |
| MACs (LAN/WAN da ART) | ✅ validado |
| Wi-Fi 2.4 + 5 GHz (ath11k) | ✅ calibração corrigida (ART 64 KB) |
| LuCI / SSH / IPv4 / IPv6 | ✅ validado |
| `sysupgrade` (grava slot alternado) | ✅ validado |
| Modo repetidor/AP (relayd) | ✅ validado (48/48 ciclos em teste noturno) |
| Estabilidade de memória do board | ⚠️ limitada por hardware/driver — ver [docs/07](docs/07-memory-and-oom.md) |

**Versão:** OpenWrt `25.12.4` (`r32933-4ccb782af7`), kernel `6.12.87`,
target `qualcommax/ipq60xx`, perfil `xiaomi_ax1800`.

## Destaques do port

- **DTS próprio** (`ipq6000-xiaomi-ax1800.dts`): NAND QPIC, switch qca8075 via
  PSGMII, 3 portas LAN + 1 WAN, MACs lidas da ART, LEDs e tecla reset.
- **Calibração Wi-Fi corrigida** — o script genérico `11-ath11k-caldata` usava
  128 KB (`0x20000`); no AX1800 só os primeiros **64 KB** (`0x10000`) da ART são
  válidos. A correção evita o firmware ath11k morrer ao carregar.
- **BDF próprio** (`board-xiaomi_ax1800.ipq6018`, variant `Xiaomi-AX1800`).
- **Boot A/B coerente** — `bootcount` confirma o slot no U-Boot
  (`flag_boot_rootfs`, `flag_boot_success`, `flag_last_success`, …) e o
  `platform.sh` grava o `sysupgrade` no slot **alternado**.
- **Repetidor relayd endurecido** — `fixsrc` para os quirks de ARP/rotas do
  relay, `guard` de auto-recuperação (uplink morto → reboot gracioso),
  blindagem de OOM nos daemons críticos e isca sacrificial.

## Estrutura do repositório

```
docs/        documentação técnica (hardware, port, build, flash, calibração,
             repetidor, memória/OOM, validação, code review, troubleshooting)
             + history/ com o log de engenharia original (sanitizado)
src/         código-fonte do port (patch aplicável + arquivos avulsos)
router/      kit operacional do roteador (scripts, init.d, hotplug, configs)
configs/     configuração de build (defconfig + buildinfo)
tests/       harness de validação e resultados dos testes de campo
images/      metadados/checksums das imagens geradas
```

Comece por **[docs/00-overview.md](docs/00-overview.md)**.

## Início rápido

### 1. Build

```bash
git clone https://git.openwrt.org/openwrt/openwrt.git
cd openwrt
git checkout ba915c2   # v25.12.4
git am /caminho/ax1800-openwrt/src/patches/0001-ipq60xx-add-Xiaomi-AX1800.patch
cp -r /caminho/ax1800-openwrt/src/overlay/files .
cp /caminho/ax1800-openwrt/configs/ax1800.config .config
make defconfig && make -j$(nproc)
```

Detalhes (incluindo gotchas de build em macOS/Docker) em
[docs/03-build.md](docs/03-build.md).

### 2. Gravação

- **Sem risco à NAND:** boot em RAM via UART + TFTP (`initramfs-uImage.itb`).
- **Instalação:** `ubiformat /dev/mtd13` com `factory.ubi` + flags no U-Boot env.

Passo a passo completo em [docs/04-flash-and-recovery.md](docs/04-flash-and-recovery.md).

### 3. Modo repetidor

Configuração e armadilhas (relayd, ARP do host, rotas, guard) em
[docs/06-repeater-relay.md](docs/06-repeater-relay.md). O kit pronto para o
roteador está em [router/](router/README.md).

> O modo repetidor usa o pacote **`relayd`** — inclua
> `CONFIG_PACKAGE_relayd=y` no build (veja
> [configs/README](configs/README.md)).

## Validação

- **E2E do guard:** derrubar o Wi-Fi de propósito → reboot automático em ~5,5 min
  → recuperação completa em ~1 min. ✅
- **Throughput (1 fluxo TCP):** cabo até **885 Mbps**; relay Wi-Fi
  **122–161 Mbps** (down) / **273 Mbps** (up). Tabela completa em
  [docs/08-validation](docs/08-validation-2026-10-18.md).
- **Teste noturno (8 h):** **48/48 ciclos** com rede 100% funcional
  (cabo + relay + STA + relayd), LuCI 200/200, SSH operacional.
- **Limitação conhecida:** o board tem 256 MB de RAM e reservas de firmware que
  deixam ~10–20 MB livres; sob pressão de memória o kernel vendor pode entrar em
  tempestades de OOM e o watchdog `qcom_wdt` reinicia o equipamento. Causa,
  evidências e mitigação em [docs/07-memory-and-oom.md](docs/07-memory-and-oom.md)
  e [docs/09-code-review.md](docs/09-code-review.md).

## Aviso

Gravar um firmware não-oficial **pode brickar** o aparelho. Tenha sempre:
dump completo da NAND, acesso UART 3.3 V e o firmware stock para recuperação.
Nenhum destes arquivos é afiliado à Xiaomi ou ao OpenWrt.

## Licença e créditos

- Conteúdo derivado do **OpenWrt** — licença [GPL-2.0](LICENSE).
- DTS baseado nos boards `glinet_gl-ax1800` / `qihoo_360v6` e nos includes
  `ipq6018-512m.dtsi` / `ipq6018-ess.dtsi`.
- Agradecimentos à comunidade OpenWrt pelo target `qualcommax/ipq60xx`.

---

*Documentação escrita a partir de evidências de hardware real (dumps de NAND,
logs de console e testes de campo). Números e trechos de log não foram
inventados; quando há incerteza, ela está explicitada no texto.*
