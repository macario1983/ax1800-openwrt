# 10 — Troubleshooting (sintoma → causa → correção)

## Wi-Fi não sobe depois do flash

**Sintoma:** rádios no `dmesg`, nenhuma interface `phy0-ap0`/`phy1-ap0`.
**Causa:** calibração ausente/ inválida (script sem case ou tamanho 128 KB).
**Correção:** aplicar o fix do `11-ath11k-caldata` (64 KB) e o band-aid
`20-xiaomi-ax1800-cal`; conferir:

```sh
ls -l /lib/firmware/ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin   # 65536
ls -l /lib/firmware/ath11k/IPQ6018/hw1.0/board-2.bin                # 65640
```

## “Roteador travado”: responde ARP mas não pinga/abre LuCI (IPv4)

**Sintoma:** kernel responde ARP; ICMP/TCP v4 não; `ip route` vazio; IPv6
link-local funciona.
**Causa:** `network.lan.ipaddr` definido **sem máscara** → `br-lan` em `/32`.
**Correção:**

```sh
uci set network.lan.netmask='255.255.255.0'
uci commit network
ifup lan
/etc/init.d/dnsmasq restart
```

No build, o overlay `99-xiaomi-ax1800-lan` já inclui a máscara.

## O roteador (repetidor) não tem internet própria

**Sintoma:** STA associada, clientes navegam, mas `ping 192.168.1.1` do
roteador falha; NTP/wget do próprio roteador não funcionam.
**Causa:** o relayd **não proxia o host** (origem `iif lo`); a default/ARP via
`br-lan` não funciona.
**Correção:** garantir no `fixsrc`/guard:

```sh
ip route replace default via 192.168.1.1 dev phy0-sta0
ip rule add to 192.168.31.0/24 lookup main pref 1
```

E **remover** `option gateway '192.168.1.1'` da interface `lan` (o netifd
reinstala a default pelo br-lan e briga com a rota correta).

## Gestão pelo caminho relay não responde (1.2)

**Sintoma:** `ping/SSH/LuCI` em `192.168.1.2` falha vindo do lado do roteador
principal, embora os clientes Wi-Fi funcionem.
**Causa:** ARP do host para IPs que **não são clientes** dos APs falha via
`br-lan`; sem rota `/32`, a resposta sai pelo br-lan e morre.
**Correção:**

1. `option ipaddr '192.168.1.2'` na `wwan` (vira `relayd -L 192.168.1.2`).
2. rota `/32` do cliente de teste via `phy0-sta0` (fixsrc/guard).

## Stalls de ~25 s no navegador/cliente

**Sintoma:** transferências param ~25 s e voltam.
**Causa:** **ARP estático venenoso** no cliente (ex.: `192.168.1.2` mapeado
para o próprio MAC do cliente).
**Correção:** `sudo arp -d 192.168.1.2` no macOS; remover entrada permanente.

## Guard reinicia o roteador sem necessidade (modo cabeado)

**Sintoma:** reboots periódicos após plugar cabo/desligar Wi-Fi.
**Causa:** em modo cabeado, `ping -I phy0-sta0` falha sempre.
**Correção:**

```sh
/etc/init.d/guard disable
/etc/init.d/guard stop
```

E desabilitar a STA **antes** de plugar o cabo (evita loop L2):

```sh
uci set wireless.sta_uplink.disabled='1'; uci commit wireless; wifi reload
```

## Guard não reinicia quando o uplink morre

**Verificar:**

```sh
ps w | grep '[g]uard.sh'                  # processo vivo
logread | grep guard                      # contagem de falhas
cat /etc/guard/reboots                    # histórico de reboots do guard
ping -c2 -W3 -I phy0-sta0 192.168.1.1     # teste manual
```

Se o ping manual funciona e o guard não conta falhas, confira se
`phy0-sta0` existe (STA habilitada) e se o alvo `192.168.1.1` está certo.

## Caixa “congela”: ping responde, SSH/LuCI não completam

**Sintoma clássico:** ICMP 0,8 ms, TCP aceita, mas dropbear/uhttpd não
terminam o handshake; às vezes reboot em ~30–60 s.
**Causa:** tempestade de OOM (reclaim direto + dumps do kernel); o `procd` fica
>30 s sem alimentar o `qcom_wdt` → reset duro.
**Mitigação:** kit completo ([07](07-memory-and-oom.md)): blindagem `-1000`,
isca, `relief`, scripts enxutos, `panic=10`. **Não** aumente
`vm.min_free_kbytes` neste board (piora — ver doc 07).

## Rebooting a cada ~20–35 min (mesmo ocioso)

**Causa:** pressão de memória estrutural do board (156 MB gerenciáveis, pools
de driver, anomalia de alocação do kernel vendor) + watchdog de 30 s.
**O que ajuda:** mitigação do kit; reduzir cargas periódicas (monitor/probe);
**o que não ajuda:** `min_free_kbytes` maior (testado e revertido).
**Caminho real:** ver [07 §9](07-memory-and-oom.md) (experimentos de kernel).

## `fw_printenv: Error: environment not found` / flags não persistem

**Causa:** `/etc/fw_env.config` ausente/errado.
**Correção:**

```sh
# índice do MTD da APPSBLENV (no AX1800: mtd6)
find_mtd_index 0:APPSBLENV
cat /etc/fw_env.config          # deve conter: /dev/mtd6 0x0 0x10000 0x20000
fw_printenv | grep flag_
```

O init `bootcount` recria o arquivo no boot se ele faltar.

## Relógio errado após o boot

**Causa:** o RTC parte de um valor salvo e o NTP só sincroniza alguns segundos
depois (o roteador deste projeto estava em **UTC**, ~+3 h do horário local).
**Correção:** aguardar o NTP; ou ajustar `system.timezone`/`zonename`.

## `sysupgrade` falha ou cai no slot errado

**Verificar:** `CI_UBIPART` resolvido por `xiaomi_get_boot_part`; volume OEM
`ubi_rootfs` removido (ID 1 livre); `ubiblock0_1` no bootargs.
**Console:** U-Boot alterna de slot em caso de falha (failover do stock).

## `ip` (busybox) não aceita tabela numérica / `route replace` falha

**Causa:** limitações do busybox `ip` (não lê tabela 16800; `replace` de
default com `dev` diferente pode falhar silenciosamente).
**Correção:** apagar a default antiga antes (`ip route del default via ... dev
br-lan`) — é o que o `guard v5`/`fixsrc` fazem. Para diagnóstico avançado,
instale `ip-full`.

## LuCI responde 000 durante os testes

**Causa:** box sob pressão de memória/reclaim no momento da medição.
**Ação:** repetir; se persistir, ver [07](07-memory-and-oom.md).

## Mac: interface USB-C pegando IP da rede errada (dual-homing)

**Causa:** DHCP na en7 via relay entrega IP `192.168.1.x` (mesma L2 da Wi-Fi).
**Correção:** IP **estático** só na rede de gestão:

```sh
networksetup -setmanual "Lenovo USB-C Hub" 192.168.31.100 255.255.255.0
ipconfig set en7 MANUAL 192.168.31.100 255.255.255.0
```

Rotas: `192.168.31.0/24 → en7` e (opcional) `192.168.1.2/32 → en7`.
