# 00 — Visão geral

Este repositório documenta e distribui o **port comunitário do OpenWrt para o
Xiaomi Redmi AX1800 (RM1800)** — um roteador Wi-Fi 6 de entrada com SoC
Qualcomm IPQ6000, 256 MB de RAM e 128 MB de NAND.

O objetivo do trabalho foi substituir o firmware stock (com componentes EOL,
telemetria e limitações de segurança) por um OpenWrt atualizado, **mantendo**:

- o esquema de boot A/B do U-Boot stock (com fallback de slot);
- o layout de partições original da NAND (nada de reparticionar);
- a calibração de rádio original (ART), essencial para o Wi-Fi funcionar;
- os MACs de fábrica, lidos do setor de ART.

Além do port em si, o repositório inclui um **kit operacional de campo** para
usar o aparelho como **repetidor/AP (relayd)** da rede principal, com
auto-recuperação — o cenário em que ele foi validado por uma noite inteira.

## O que foi feito, em resumo

1. **Análise do hardware e do firmware stock** (partições, U-Boot, ART,
   assinaturas de firmware, console UART) a partir de dumps da NAND.
2. **Port para OpenWrt 25.12.4** (`qualcommax/ipq60xx`):
   - DTS do board;
   - entrada em `ipq60xx.mk` (imagens FIT/UBI);
   - `board.d` (mapeamento LAN/WAN);
   - `bootcount` (confirmação de slot no U-Boot);
   - `platform.sh` (sysupgrade para o slot alternado);
   - `uboot-envtools` (acesso ao APPSBLENV);
   - BDF `board-2.bin` próprio;
   - correção do `11-ath11k-caldata` (64 KB em vez de 128 KB).
3. **Gravação e validação em hardware real**, incluindo console UART, boot em
   RAM (initramfs/TFTP) e instalação no slot 1.
4. **Correções de campo**: bug de máscara de rede (`/32`), calibração do
   Wi-Fi, comportamento do relayd, regras de rota do host, proteção contra OOM.
5. **Validação noturna automatizada** (~8 h, 48 ciclos) com medição de
   throughput, LuCI, SSH, memória e reboots.
6. **Investigação de estabilidade**: reboots periódicos do board foram
   rastreados até tempestades de OOM + watchdog de hardware; o mecanismo,
   evidências e mitigações estão em [07-memory-and-oom.md](07-memory-and-oom.md)
   e [09-code-review.md](09-code-review.md).

## Como ler a documentação

| Documento | Conteúdo |
|---|---|
| [01-hardware.md](01-hardware.md) | anatomia do AX1800, partições, boot A/B, ART, memória reservada |
| [02-port-design.md](02-port-design.md) | o que o port adiciona e por quê (DTS, mk, bootcount, platform.sh, BDF, cal) |
| [03-build.md](03-build.md) | como reproduzir o build (container, gotchas, config) |
| [04-flash-and-recovery.md](04-flash-and-recovery.md) | gravação segura, UART/TFTP, recuperação, sysupgrade |
| [05-calibration.md](05-calibration.md) | o problema da calibração Wi-Fi e a correção definitiva |
| [06-repeater-relay.md](06-repeater-relay.md) | modo repetidor: relayd, quirks de ARP/rotas, guard |
| [07-memory-and-oom.md](07-memory-and-oom.md) | anatomia da memória, OOM, watchdog e mitigações |
| [08-validation-2026-10-18.md](08-validation-2026-10-18.md) | metodologia e resultados dos testes de campo |
| [09-code-review.md](09-code-review.md) | revisão minuciosa, arquivo por arquivo, com riscos e pendências |
| [10-troubleshooting.md](10-troubleshooting.md) | sintomas → causa → correção |

## Convenções

- Valores de rede do autor foram **substituídos por placeholders**:
  - rede de gestão/backdoor: `192.168.31.0/24` (IP do roteador `192.168.31.1`);
  - rede principal (uplink): `192.168.1.0/24` (`192.168.1.1` = roteador principal);
  - SSID de exemplo: `HomeNet`;
  - MACs de exemplo: `AA:BB:CC:DD:EE:FF`.
- Comandos são para o shell do OpenWrt (`ash`/busybox).
- Logs reais estão em [tests/results](../tests/results); trechos citados na
  documentação vieram desses arquivos.
- O documento histórico do trabalho (log de engenharia original, em português)
  está em [history/PORT-AX1800.md](history/PORT-AX1800.md). Ele contém a
  cronologia crua; os documentos numerados acima são a versão curada e
  corrigida (por exemplo: o nó de memória do DTS é de **256 MB**, não 512 MB).
