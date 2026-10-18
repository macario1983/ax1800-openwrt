# 06 — Modo repetidor/AP com relayd

Cenário validado: o AX1800 é **AP da mesma rede do roteador principal**,
usando a **própria Wi-Fi como uplink** (repetidor), pronto para migrar para
cabo.

## Topologia

```
                 ┌───────────── AX1800 (OpenWrt) ─────────────┐
                 │  phy0-ap0 (5 GHz)  ─┐                      │
   clientes ─────┼─  phy1-ap0 (2,4 GHz)─┴─ br-lan 192.168.1.2 │
                 │       10.31.1 (backdoor na porta LAN)      │
                 │  phy0-sta0 (STA 5 GHz) ── wwan ── relayd    │
                 └───────────────────┬────────────────────────┘
                                     │ ar (2 travessias)
                              ┌──────┴──────┐
                              │  AX9000     │  192.168.1.1 (DHCP/DNS)
                              │  HomeNet    │
                              └─────────────┘
```

- O AX1800 **não** roda DHCP/DNS: `dnsmasq` e `odhcpd` ficam **desabilitados**;
  os clientes recebem DHCP/DNS do roteador principal via relay.
- O próprio roteador usa `nameserver 192.168.1.1` em `/etc/resolv.conf`.

## Como o relayd funciona (de verdade)

**Importante:** não existe um handler `proto relay` no netifd. O pacote
`relayd` fornece:
- o binário `/usr/sbin/relayd`;
- o init `/etc/init.d/relayd`, que **implementa** o relay: ele varre
  `config_foreach start_relay interface`, seleciona interfaces com
  `option proto 'relay'`, resolve `network` e `ifname` e inicia o daemon com
  procd. O `service_triggers` recarrega quando `interface.*` muda.

Consequências práticas:
- `ubus call network.interface.wwan status` mostra `"proto": "none"` — é o
  esperado (o netifd só cuida do dispositivo `phy0-sta0`; o relay é do daemon).
- O pacote **não estava na imagem** validada; foi instalado depois e habilitado
  (`/etc/rc.d/S80relayd`). Para build reprodutível, use
  `CONFIG_PACKAGE_relayd=y` (ver [configs/README](../configs/README.md)).

Cmdline observada no equipamento:

```
/usr/sbin/relayd -I br-lan -I phy0-sta0 -L 192.168.1.2 -B -D
```

- `-I br-lan` e `-I phy0-sta0` vêm dos nomes resolvidos (`network` da wwan =
  `lan` → `br-lan`; `ifname` = `phy0-sta0`).
- **`-L 192.168.1.2`** vem de `option ipaddr` e é essencial: faz o relayd
  responder ARP pelo IP do roteador na rede de cima. Sem isso, a gestão pelo
  caminho relay não funciona.
- `-B`/`-D`: forward de broadcast/DHCP.

## Configuração (UCI)

`/etc/config/network` (trechos):

```
config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'lan1'
	list ports 'lan2'
	list ports 'lan3'

config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ip6assign '60'
	list ipaddr '192.168.1.2/24'
	list ipaddr '192.168.31.1/24'
	option dns '192.168.1.1'

config interface 'wwan'
	option proto 'relay'
	list network 'lan'
	option ipaddr '192.168.1.2'
```

`/etc/config/wireless` (trecho):

```
config wifi-device 'radio0'        # 5 GHz
	option band '5g'
	option htmode 'HE80'
	option country 'BR'

config wifi-iface 'default_radio0' # AP 5 GHz → lan
	option mode 'ap'
	option ssid 'HomeNet'
	option encryption 'psk2'
	option network 'lan'

config wifi-iface 'zarasta'        # STA → wwan
	option device 'radio0'
	option mode 'sta'
	option ssid 'HomeNet'
	option encryption 'psk2'
	option network 'wwan'
	option bssid 'AA:BB:CC:DD:EE:FF'   # BSSID do AP principal (opcional/pinado)
```

> ⚠️ Não use `option gateway '192.168.1.1'` na interface `lan` — o netifd
> reinstala `default via ... dev br-lan` e briga com a rota correta (ver
> abaixo). O default é aplicado pelo `fixsrc`/`guard`.

## O quirk do ARP/rotas do host (e o `fixsrc`)

O relayd **não proxia o próprio host**: tráfego com origem local (`iif lo`) não
passa pelo relay. Resultado:

- ARP do roteador para `192.168.1.1` **via br-lan** falha (`FAILED`) — o ping
  para o gateway e a rota default “normal” não sobem;
- ARP para IPs do lado do roteador principal que **não sejam clientes dos
  nossos APs** também falha pelo br-lan.

Correções aplicadas em
[`router/etc/hotplug.d/iface/99-fixsrc`](../router/etc/hotplug.d/iface/99-fixsrc)
(no ifup de `wwan`/`lan`, com 3 s de atraso):

```sh
ip rule add to 192.168.31.0/24 lookup main pref 1   # força src 192.168.31.1
ip route del default via 192.168.1.1 dev br-lan     # remove default errada
ip route replace default via 192.168.1.1 dev phy0-sta0
ip route replace <IP-do-cliente>/32 dev phy0-sta0   # cliente de teste, se houver
```

- A rota default **pela STA** funciona mesmo sendo um “port de bridge”
  (`phy0-sta0` está na bridge) — o kernel aceita.
- A regra `to 192.168.31.0/24 lookup main` garante que as respostas da rede de
  gestão saiam pelo `br-lan`.
- `option gateway` removido da `lan` (ver acima) para o netifd não reinstalar a
  default pelo br-lan (o `guard v5` também apaga resíduos).

## Guard v5 — auto-recuperação

[`router/usr/local/bin/guard.sh`](../router/usr/local/bin/guard.sh) roda como
serviço procd (`/etc/init.d/guard`), com duas instâncias: `guard` e `bait`.

| Função | Comportamento |
|---|---|
| `protect()` | força `oom_score_adj=-1000` nos daemons críticos (wpa_supplicant, hostapd, netifd, relayd, dropbear, uhttpd, rpcd, logd, syslogd, ubusd, ntpd, ubihealthd, crond, dnsmasq, odhcpd, mon.sh, guard.sh, memprobe, relief) e no procd (PID 1) |
| `fixroute()` | garante a regra `31.x`, o `default via phy0-sta0` e a rota `/32` do cliente de teste (com `ip route del` da default residual no br-lan) |
| watchdog de uplink | `ping -c2 -W3 -I phy0-sta0 192.168.1.1` a cada ~55 s; **6 falhas (~5,5 min)** → reboot gracioso; máx. **3 reboots/hora**; graça de 5 min pós-boot; registros em `/etc/guard/reboots` |
| isca (`bait.sh`) | processo inofensivo com `oom_score_adj=+1000`, supervisionado pelo procd: o OOM killer sempre tem uma vítima inofensiva primeiro |

> ⚠️ O `-I phy0-sta0` no ping é **obrigatório**: sem ele, o ping usa a rota
> default e o guard dá reboot falso com o relay 100% funcional.
>
> ⚠️ **Em modo cabeado, desabilite o guard** (`/etc/init.d/guard disable;
> /etc/init.d/guard stop`) — sem a STA, o ping falha sempre.

### Teste E2E do guard (realizado)

1. `wifi down` às 00:35:50 (uplink morto).
2. O guard contou 6 falhas (~5,5 min).
3. **Reboot automático às ~00:41:20** (uptime 857 → 26; entrada em
   `/etc/guard/reboots`).
4. Recuperação completa em ~1 min: STA re-associada, relayd no ar, rotas
   restauradas, ping/wget pelo relay OK.

Evidence: [tests/results/guardtest.log](../tests/results/guardtest.log).

## Migração para modo cabeado (roteador AP com uplink Ethernet)

1. **Primeiro** desabilite a STA (evita loop L2):
   ```sh
   uci set wireless.zarasta.disabled='1'
   uci commit wireless
   wifi reload
   ```
2. Desabilite o guard:
   ```sh
   /etc/init.d/guard disable
   /etc/init.d/guard stop
   ```
3. Plugue o cabo na porta **WAN** (modo router, `wan` já está em DHCP) ou em
   uma LAN (modo AP/bridge) conforme o desenho desejado.

## Notas do lado do cliente de teste (macOS)

- Interface USB-C (en7) do Mac: **estático `192.168.31.100/24`** — com DHCP ela
  pegava IP da rede 1.x via relay e criava dual-homing na mesma L2.
- Cuidado com **ARP estático venenoso**: `192.168.1.2 → <MAC local>` causou
  stalls de 25 s; limpar com `sudo arp -d 192.168.1.2`.
- Rotas: `192.168.31.0/24 → en7` e (opcional) `192.168.1.2/32 → en7`.
