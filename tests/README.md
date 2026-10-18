# tests — harness e resultados de campo

## Conteúdo

| Caminho | O que é |
|---|---|
| `overnight_mon.sh` | monitor noturno (macOS/zsh): 48 ciclos, check.sh, throughput 4 MB, LuCI, detecção de reboot (executado como está em 18/10) |
| `results/guardtest.log` | teste E2E do guard (wifi down → reboot → recuperação) |
| `results/overnight.log` | log completo do monitor (48 ciclos + eventos) |
| `results/overnight_summary.txt` | resumo agregado gerado ao final |
| `mac/fix_en7.sh` | ajuste da interface USB-C do Mac (IP estático/rotas) usado nos testes |

## Pré-requisitos para reproduzir

1. Roteador acessível por SSH **sem senha** em `192.168.31.1` (modo cabo) e
   `192.168.1.2` (modo relay).
2. Servidor HTTP no Mac em `:8123` servindo os payloads de teste
   (ex.: `python3 -m http.server 8123` na pasta com `small4m.bin`).
3. Coletor de syslog UDP no Mac (porta `5141`), configurado em
   `/etc/config/system` (`log_remote`).
4. `curl`, `perl` (timeout por alarme) e `ping -b` (usa `en0` como interface
   Wi-Fi do Mac — ajuste se a sua for outra).
5. `check.sh` instalado no roteador ([router/](../router)).

## Como rodar

```bash
# edite os paths/IPs no topo do script se necessário
chmod +x overnight_mon.sh
caffeinate -i ./overnight_mon.sh   # impede o Mac de dormir
```

Saída: `overnight.log` e `overnight_summary.txt` no diretório `B` definido no
script (na execução original, um diretório temporário do opencode).

## O que o monitor mede em cada ciclo (~9 min)

- ping no cabo (`192.168.31.1`) e pelo relay (`192.168.1.2` → `en0`);
- via SSH + `check.sh`: uptime, `MemFree`, `MemAvailable`, kills de OOM,
  guard, isca, STA associada, relayd, sinal, internet;
- a cada 6 ciclos: **4 MB** de download por cada caminho (taxa calculada nos
  contadores de `br-lan`/`phy0-sta0`) + **LuCI** `200` nos dois caminhos;
- reboot = queda de uptime; em OOM/reboot, anexa trechos do `dmesg`/`logread`.

## Resultado oficial (18/10/2026)

- 48/48 ciclos com rede funcional; 16 reboots detectados (18 reais — ver
  [docs/08](../docs/08-validation-2026-10-18.md)); LuCI 200/200; throughput
  cabo 117–244 Mbps / relay 24–103 Mbps (4 MB).
- O teste **não** mede o throughput máximo: para isso veja a tabela de
  4/16/40/160 MB em [docs/08](../docs/08-validation-2026-10-18.md).

## Limitações conhecidas

- Detecção de reboot por uptime **subestima** eventos entre ciclos.
- O relógio do roteador estava em UTC; os timestamps do log são do Mac.
- O próprio monitor gera carga (SSH/wget/4 MB) — parte da pressão de memória
  observada vem dele. Nas últimas horas os scripts do roteador foram afinados
  (`iw` 1×/2,5 min, 1 `ps`/ciclo) e o probe ficou a 10 s.
