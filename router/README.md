# router — kit operacional do AX1800

Arquivos que rodam **no roteador** (OpenWrt deste port), prontos para copiar.
Nada aqui é específico do hardware: são scripts de operação/rede e serviços
procd. Valores de exemplo estão destacados; **ajuste para a sua rede**.

## Conteúdo

| Caminho | O que faz |
|---|---|
| `usr/local/bin/guard.sh` | guard v5: watchdog de uplink (ping `-I phy0-sta0`), blindagem OOM (`-1000`), reparo de rotas |
| `usr/local/bin/bait.sh` | isca sacrificial (`oom_score_adj=+1000`) |
| `usr/local/bin/mon.sh` | monitor leve → syslog (uptime, memória, contadores STA, sinal, relayd) |
| `usr/local/bin/check.sh` | estado resumido sob demanda (usado pelo harness de testes) |
| `usr/local/bin/memprobe.sh` | probe forense de memória (10 s; meminfo, top-RSS, buddyinfo, zoneinfo sob pressão) |
| `usr/local/bin/relief.sh` | válvula: `drop_caches` quando `free<6 MB` ou `avail<5 MB` |
| `etc/init.d/{guard,mon,memprobe,relief}` | serviços procd (guard tem 2 instâncias: guard + bait) |
| `etc/hotplug.d/iface/99-fixsrc` | **quirk do relayd**: regra da rede de gestão, default via STA, rota `/32` do cliente de teste |
| `etc/hotplug.d/firmware/20-xiaomi-ax1800-cal` | band-aid da calibração (extrai 64 KB da ART se faltar) |
| `etc/sysctl.conf` | `min_free_kbytes=4096`, caps TCP/conntrack, drenagem RX, `panic=10` |
| `etc/config/{network,wireless,dhcp,system}` | configuração de referência (repetidor) — **sanitizada** |
| `install.sh` | instalador (copies + enable + checks; `--with-config` opcional) |

## Instalação

```bash
scp -r router root@192.168.31.1:/tmp/ax1800-kit
ssh root@192.168.31.1 'sh /tmp/ax1800-kit/install.sh'
```

O instalador **não** sobrescreve `/etc/config` por padrão. Para usar as
configurações de referência:

```bash
ssh root@192.168.31.1 'sh /tmp/ax1800-kit/install.sh --with-config'
```

Depois **edite** SSID/chave/BSSID em `/etc/config/wireless` e as redes em
`/etc/config/network`, e reinicie (`wifi reload`; `ifup lan wwan`).

## Dependências

- **`relayd`** — necessário para o modo repetidor. A imagem validada **não** o
  inclui (foi instalado depois); para um build limpo habilite
  `CONFIG_PACKAGE_relayd=y`.
- `iw`, `ip` (busybox), `logger` — já presentes na imagem padrão.

## Ajustes que você DEVE fazer

| Item | Onde | Padrão do repositório |
|---|---|---|
| IP do cliente de teste (rota `/32`) | `99-fixsrc`, `guard.sh` | `192.168.1.100` |
| Redes de gestão/uplink | `etc/config/network` | `192.168.31.1`, `192.168.1.2` |
| SSID/chave/BSSID | `etc/config/wireless` | `HomeNet` / `REDACTED` / `AA:BB:CC:DD:EE:FF` |
| Coletor syslog | `etc/config/system` | `192.168.31.100:5141` UDP |
| Watchdog de uplink | `guard.sh` (`ping ... 192.168.1.1`) | gateway do uplink |

## Avisos

- **Modo cabeado:** desabilite o guard (`/etc/init.d/guard disable; stop`) —
  sem STA o ping `-I phy0-sta0` falha sempre. Desabilite a STA **antes** de
  plugar o cabo (loop L2).
- `relief.sh` faz `drop_caches` sob pressão — sem efeito colateral funcional,
  mas gera linhas `relief:` no log.
- `memprobe.sh` é forense (10 s). Em uso normal você pode desabilitá-lo
  (`/etc/init.d/memprobe disable; stop`) para reduzir ainda mais o ruído.
- A senha do Wi-Fi **não** está neste repositório; o arquivo de referência usa
  `REDACTED`.
