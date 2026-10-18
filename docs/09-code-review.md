# 09 — Code review minucioso (port + kit operacional + testes)

Revisão feita em 2026-10-18 a partir de:

1. leitura integral dos arquivos do repositório e do patch;
2. arqueologia do git (commit `63c6eff` sobre `ba915c2` = v25.12.4);
3. verificação **no equipamento real** (dmesg, `fw_printenv`, rotas, UCI,
   arquivos de firmware, syslog);
4. conferência dos hashes das imagens e do BDF;
5. reanálise dos logs da noite e do teste E2E do guard.

Legenda de severidade: **ALTA** (quebra reprodução/operacão), **MÉDIA**
(atrito/risco em cenários específicos), **BAIXA** (cosmético/manutenção).

---

## 1. DTS — `ipq6000-xiaomi-ax1800.dts`

**Verificado OK**

- `compatible = "xiaomi,ax1800", "qcom,ipq6018"` — casa com `board.d`,
  `bootcount`, `platform.sh` e `uboot-envtools`.
- Memória: `reg = <0x0 0x40000000 0x0 0x10000000>` = **256 MB**. O include
  `ipq6018-512m.dtsi` **não define** nó de memória (só ajusta `q6_region`) —
  conferido na árvore; o DTB final tem um único nó de memória.
- Partições: 16 entradas com tamanhos que fecham exatamente
  (`rootfs` termina em `0x3800000` = início de `rootfs_1`; `rootfs_1` termina
  em `0x6480000` = início de `overlay`).
- MACs: `nvmem-layout` em `0:ART` (`macaddr@6` LAN, `macaddr@18` WAN) e
  `label-mac-device = &dp5` (WAN/etiqueta) — verificado no equipamento
  (`fw_printenv`/interfaces).
- Switch/MDIO: `qcom,qca8075-package`, PHYs 1..4 ligados a `port@2..5`,
  reset no GPIO 75 ativo baixo — Ethernet operacional nos testes.
- `&wifi`: depende do patch do target
  `0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch` (presente em
  `patches-6.12/`); o `qcom,rproc = <&q6v5_wcss>` confirmado no boot
  (`remoteproc0` sobe `IPQ6018/q6_fw.mdt`).

**Observações**

| Sev. | Achado | Comentário |
|---|---|---|
| BAIXA | Partição `overlay` (`0x6480000`) marcada `read-only` e não usada | espelha o stock; o overlay real é volume UBIFS dentro do UBI do slot. Documentado. |
| BAIXA | Nó `memory` sem unit-address | funciona porque não há outro nó (`ipq6018.dtsi` não define memória). Manter como está. |
| BAIXA | `uart_en=1` vem do bootloader stock | não é setado no DTS; o console funciona. |

**Correções de documentação** (feitas neste repositório):

- A nota antiga dizia “nó memory 512MB” — **é 256 MB**.
- A nota antiga chamava os 55 MB de “reserva do NSS” — **é o `q6_region`, do
  firmware Q6/WCSS (Wi-Fi)**.

---

## 2. Calibração — `11-ath11k-caldata`

- `caldata_extract "0:ART" 0x1000 0x10000` — label idêntica à do DTS
  (maiúsculas) e **64 KB** (correto; `0x11000..0x21000` é `0xFF`).
- `redmi,ax1800` incluído como alias defensivo (o `compatible` do DTS usa
  `xiaomi,ax1800`; o alias não é exercitado hoje).
- **Bug histórico evitado:** usar o tamanho “padrão da família” (128 KB) gera
  um arquivo de cal com lixo e o firmware ath11k morre silenciosamente.
- Verificação no device: `cal-ahb-c000000.wifi.bin` = 65 536 B; `board-2.bin`
  = 65 640 B; STA associado e APs no ar.

**Risco residual (BAIXO):** o hotplug do firmware roda antes de o `ART` estar
necessariamente pronto? Na prática, o cal é extraído no coldplug do firmware
(MD) e nunca falhou nos boots observados. O band-aid `20-xiaomi-ax1800-cal`
cobre a ausência do arquivo.

---

## 3. `bootcount` (confirmação A/B)

**OK**

- Usa `find_mtd_index` — definido em `/lib/functions.sh`, carregado pelo
  `rc.common` (verificado na árvore).
- `local` funciona no `ash` do busybox.
- No initramfs (sem `ubi.mtd=`), `cur_boot_part` vazio → `return 0`.
- `fw_setenv -s -` com heredoc — suportado pelo `uboot-envtools`.
- No equipamento: `/etc/fw_env.config` = `/dev/mtd6 0x0 0x10000 0x20000` e
  flags corretas (`flag_boot_rootfs=1`, `flag_boot_success=1`, …).

**Riscos (BAIXO/MÉDIO)**

| Sev. | Achado |
|---|---|
| BAIXA | O “guard” do `fw_env.config` só verifica duplicata do **mesmo** índice de MTD; se o número de MTD mudar entre builds (reflash/partições diferentes), pode sobrar uma linha antiga apontando para o mtd errado. No AX1800 o índice é estável (mtd6). |
| BAIXA | Se `fw_setenv` falhar (env corrompido), não há retry/alarme no syslog — só o log local `logger` que não é emitido em caso de falha do `fw_setenv`. |

**Sugestão:** adicionar `|| logger -t bootcount "FALHA ao confirmar slot"` no
`fw_setenv` (não implementado para manter o port mínimo).

---

## 4. `platform.sh` (sysupgrade A/B)

**OK**

- `xiaomi_get_boot_part()` usa `/proc/cmdline` e tem fallback por
  `fw_printenv` (initramfs).
- `remove_oem_ubi_volume ubi_rootfs` é necessário para o novo volume `rootfs`
  receber o **ID 1** (`ubiblock0_1` no bootargs). Mesma abordagem de outros
  boards da família.
- `nand_do_upgrade "$1"` é o fluxo padrão (grava no slot alternado).

**Riscos (BAIXO)**

- Se a cmdline não tiver `ubi.mtd` e o `fw_printenv` também falhar, o fallback
  assume `rootfs` (slot 0) — comportamento conservador, mas pode gravar por
  cima do slot errado em cenário exótico. Não observado em campo.

---

## 5. `uboot-envtools`

- `"0:APPSBLENV" "0x0" "0x10000" "0x20000"` — verificado no device
  (`/dev/mtd6 0x0 0x10000 0x20000`).
- **OK**, sem ressalvas.

---

## 6. `ipq-wifi` (Makefile + BDF)

- Pacote `ipq-wifi-xiaomi_ax1800` presente no manifest e na imagem.
- BDF sha256 idêntico ao arquivo fonte (`9f841a8d…`).
- **Mudança global** no Makefile (wildcard também em `$(CURDIR)/files/…`):

| Sev. | Comentário |
|---|---|
| MÉDIA | É uma alteração no empacotamento compartilhado. Só age quando existe `files/board-<pkg>.*`; não afeta outros boards. **Porém**, ao rebasear para uma versão nova do OpenWrt, esse trecho pode conflitar. Alternativa upstreamável: manter o BDF no repositório oficial `ipq-wifi` e remover essa mudança. |
| BAIXA | O BDF é um blob de origem vendor (sem MACs). Documentado no `src/README`. |

---

## 7. Imagem — `ipq60xx.mk`

- `Device/FitImage` + `Device/UbiFit` com `BLOCKSIZE 128k`/`PAGESIZE 2048` —
  compatível com a NAND (128 KB blocos, 2 KB páginas).
- `DEVICE_DTS_CONFIG := config@cp03-c1` — **igual ao config padrão do U-Boot
  stock** (verificado no FIT extraído).
- `DEVICE_PACKAGES := ipq-wifi-xiaomi_ax1800 uboot-envtools` — ambos presentes
  no manifest.
- **Sem ressalvas.**

---

## 8. Overlay `files/etc/uci-defaults/99-xiaomi-ax1800-lan`

- Define IP `192.168.31.1` **e máscara** `255.255.255.0` — corrige o bug do
  `/32` (documentado em [04](04-flash-and-recovery.md)).
- **Achado MÉDIO:** o arquivo **não está no commit do port** (é conteúdo local
  de `files/`). Este repositório o carrega em `src/overlay/` e o instalador do
  build o copia; para um port “upstreamável”, mova para
  `target/linux/qualcommax/files/etc/uci-defaults/` (aí entra na imagem pelo
  próprio target).

---

## 9. Configuração de build (`.config`/`buildinfo`) e **relayd**

- **ALTA (reprodução):** a imagem validada **não inclui o pacote `relayd`**
  (`# CONFIG_PACKAGE_relayd is not set`, ausente do manifest). O modo repetidor
  dependeu de instalação **posterior** no equipamento (`/usr/sbin/relayd` +
  `/etc/init.d/relayd`, habilitado em `S80relayd`).
  **Correção recomendada:** habilitar `CONFIG_PACKAGE_relayd=y` antes do build
  (documentado em [configs/README](../configs/README.md) e
  [router/README](../router/README.md)).
- O init do `relayd` **implementa** o `proto relay`: varre os `config interface`
  e resolve `network`/`ifname`; por isso `ubus` mostra `"proto": "none"` para a
  `wwan` — **não é bug**.
- `config.buildinfo` (1 022 B) é a fonte de verdade do build; o snapshot
  completo é conveniência.

---

## 10. Kit operacional (`router/`)

### guard.sh

| Item | Avaliação |
|---|---|
| Ordem do reboot (`echo "$now" >> reboots` **antes** de `reboot`) | ✅ correta — permite auditar cada reboot do guard |
| Cap de 3 reboots/hora + graça de 5 min | ✅ correto (`awk` sobre timestamps) |
| `protect()` com 1 `ps w` (hoisted) | ✅ reduz ~18 forks/ciclo |
| `fixroute()` apaga default via `br-lan` antes de repor | ✅ necessário (netifd re-instala) |
| **IP fixo do cliente `/32`** (`192.168.1.100` neste repositório) | ⚠️ MÉDIA: específico do ambiente; remova/ajuste |
| Dependência de `iw` em `fixroute` (1×/ciclo) | ⚠️ BAIXA: `iw` é rápido, mas é um fork; poderia usar `/sys` (não há sinal em sysfs) |
| Sem `set -e` | ✅ intencional (script de watchdog) |
| `sleep 1800` no cap | ⚠️ BAIXA: após o cap, o guard fica cego por 30 min (por design) |

### bait.sh

- Trivial e correto (`sleep` loop, adj +1000). Sem ressalvas.

### mon.sh / check.sh

- `mon.sh`: `iw` a cada 5ª iteração (cacheado), leitura de `/sys/class/net`;
  **BAIXA:** `pidof relayd | wc -w` gasta 2 forks/30 s — poderia ler
  `/proc/*/comm`; irrelevante.
- `check.sh`: `dmesg | grep -c 'Killed process'` conta desde o boot (ring pode
  rodar em uptimes longos) — **BAIXA**.
- Ambos: sem `set -u`; OK.

### memprobe.sh (v3)

- 1 `awk` para o meminfo + 1 `logger` por iteração (10 s); bloco pesado só a
  cada 30 iterações (5 min) ou quando `avail < 3500 kB`.
- **BAIXA:** `awk` do top-RSS usa `"ls /proc" | getline` (1 fork) + `sort`/
  `head`/`logger` no bloco pesado — aceitável para uso forense.
- **Recomendação:** desabilitar em uso normal (o kit explica).

### relief.sh

- `drop_caches` (echo 3) a cada 5 s enquanto `free<6 MB` ou `avail<5 MB`.
- **BAIXA:** `drop_caches` pode mascarar a leitura de “pressão real” e gerar
  linhas de log; inofensivo funcionalmente.

### 99-fixsrc / 20-xiaomi-ax1800-cal

- `fixsrc`: roda no ifup de `wwan`/`lan`, dorme 3 s em background. **BAIXA:**
  múltiplos ifups podem empilhar sleeps; inofensivo.
- `20-cal`: no-op quando a cal existe; correto.

### init.d

- `guard` abre **duas instâncias procd** (`guard`, `bait`) com `respawn 3600 5 5`
  — OK.
- `mon`/`memprobe`/`relief`: `respawn` padrão; OK.

### sysctl.conf

- `min_free_kbytes=4096` (ver [07](07-memory-and-oom.md)), caps TCP/conntrack,
  `netdev_budget=600`, `dev_weight=128`, `panic=10`.
- **BAIXA:** `panic=10` é forense (mantém o boot 10 s após pânico); se você
  quiser reboot mais rápido, reduza.

---

## 11. Harness de testes (`tests/`)

| Item | Avaliação |
|---|---|
| Detecção de reboot por uptime | ⚠️ MÉDIA: subestima (perde reboots entre ciclos; reconhecido) |
| `ping -b en0` / `curl --interface en0` | ⚠️ BAIXA: específico do Mac do autor |
| Throughput 4 MB | ⚠️ MÉDIA: payload pequeno sofre overhead; para números de pico use 40/160 MB |
| `check.sh` via SSH (20 s alarm) | ✅ adequado |
| `fix_en7.sh` | ⚠️ BAIXA: macOS-específico (interface USB-C) |

---

## 12. Tabela consolidada de achados

| # | Sev. | Achado | Ação |
|---|---|---|---|
| 1 | **ALTA** | `relayd` fora da imagem; instalado post-flash | habilitar `CONFIG_PACKAGE_relayd=y` (documentado) |
| 2 | **ALTA** | Pressão de memória → OOM → watchdog resets | ver [07](07-memory-and-oom.md); mitigado, não resolvido |
| 3 | MÉDIA | `99-xiaomi-ax1800-lan` fora do commit do port | incluído em `src/overlay`; sugerido mover para o target |
| 4 | MÉDIA | Mudança global no `ipq-wifi/Makefile` | documentada; rebase cuidado |
| 5 | MÉDIA | IPs fixos no guard/fixsrc e coletor syslog | placeholders no repo; ajustar no deploy |
| 6 | MÉDIA | Detecção de reboot do harness subestima | documentado nos resultados |
| 7 | BAIXA | Doc antiga: “memory 512MB” / “NSS 55MB” | **corrigido** neste repo (256 MB / q6_region) |
| 8 | BAIXA | `fw_env.config` pode manter linha de MTD antigo | índice estável no AX1800; monitorar |
| 9 | BAIXA | `drop_caches` pode mascarar pressão | intencional; monitorar |
| 10 | BAIXA | Sem retry/alarme se `fw_setenv` falhar | sugestão de melhoria |

---

## 13. Recomendações (ordem prática)

1. **Rebuild com `CONFIG_PACKAGE_relayd=y`** (fecha a lacuna de reprodução).
2. Mover o `99-xiaomi-ax1800-lan` para `target/linux/qualcommax/files/…`
   (ou manter o overlay, mas documentado).
3. **Não** remover o `q6_region` sem teste: ele é a memória do firmware Wi-Fi.
   Se quiser tentar reduzir (ex.: 47 MB), faça um build experimental com
   console serial disponível.
4. Se a estabilidade for prioridade: avaliar **zram/swap via rebuild** ou um
   kernel/ath11k mais novo; e manter o kit de mitigação ativo.
5. Ao publicar o repositório: revisar segredos (já sanitizado: SSID genérico,
   chave `REDACTED`, BSSID/MACs de exemplo, DUID/ULA zerados).

---

## 14. O que foi validado de ponta a ponta (não apenas revisado)

- Boot A/B, `bootcount`, `fw_printenv`, `sysupgrade`.
- Ethernet (3×LAN+WAN), MACs, LEDs.
- Wi-Fi 2,4/5 GHz (cal 64 KB), STA + AP simultâneos.
- Relayd + quirks de ARP/rotas + guard + isca (E2E com reboot provocado).
- Throughput em 4 tamanhos de payload.
- 48 ciclos noturnos com telemetria contínua e recuperação automática.
