# 07 — Memória, OOM e o watchdog (anatomia e estabilidade)

Este é o documento mais importante para entender o comportamento do board.
Todo o conteúdo abaixo foi obtido de **medições no equipamento real**:
`/proc/meminfo`, `/proc/buddyinfo`, `/proc/zoneinfo`, dumps de OOM do kernel,
`dmesg`, syslog remoto contínuo (UDP) e a série de testes da noite de
2026-10-18.

## 1. Onde a memória vai (256 MB físicos)

```
Física                 262 144 kB (256 MB)
Reservado (nomap)      ~102 980 kB
  ├─ q6_region  55 MB  firmware do Q6/WCSS (Wi-Fi) — `remoteproc@cd00000`
  ├─ 16 MB @0x40000000 (Q6/secure)
  ├─ bootloader/SBL/etc ~11 MB
  └─ 24 KB misc
MemTotal (Linux)       160 124 kB (~156 MB)
```

O `dmesg` do equipamento:

```
remoteproc0: powering up cd00000.remoteproc
remoteproc0: Booting fw image IPQ6018/q6_fw.mdt, size 7340
ath11k c000000.wifi: FW memory mode: 1
Memory: 157440K/262144K available (102980K reserved)
```

> ⚠️ **Correção importante:** a região de 55 MB **não é “reserva do NSS”** —
> é o `q6_region`, memória do firmware do Q6/WCSS que executa o Wi-Fi. Ela é
> referenciada pelo remoteproc `q6v5_wcss` e **não pode ser simplesmente
> removida** (o firmware não sobe sem ela). Qualquer tentativa de reduzi-la é
> experimental e exige rebuild + reflash.

## 2. Dentro dos ~156 MB gerenciáveis

Valores típicos medidos (idle, após ~20 min de uptime):

| Categoria | Tamanho | Reclaimable? |
|---|---|---|
| `AnonPages` (processos) | ~5 MB | não (mas processos são minúsculos) |
| `Cached` (page cache) | 3–18 MB | **sim** |
| `Slab` total | ~31 MB | — |
| ├ `SUnreclaim` | **~24,7–25 MB** | **não** — e **constante** (baseline do kernel vendor) |
| └ `SReclaimable`/`KReclaimable` | ~6–7 MB | sim |
| `KernelStack` | ~1,6–1,9 MB | não |
| `PageTables` | ~0,9 MB | não |
| `VmallocUsed` | ~12 MB | não |
| `Percpu` | ~0,5 MB | não |
| **“Invisível” (DMA/coherent/page_pool dos drivers)** | **~90–100 MB** | **não** |

O kernel vendor **não expõe `/proc/slabinfo`** nem `page_owner`, e não há
contador para as alocações DMA/coherent/pools do datapath (ath11k em
`FW memory mode: 1`, anéis do EDMA/SSDK etc.). O valor “invisível” é obtido
por aritmética: `MemTotal − (free + categorias visíveis)`.

**Consequências práticas:**

- `MemFree` ocioso típico: **6–20 MB** (cai para ~6–8 MB após o “warm-up” de
  ~20 min de cada boot).
- `MemAvailable`: frequentemente **< 5 MB** na banda baixa.
- O board vive numa **faca**: qualquer burst transiente de alguns MB pode
  encostar no watermark e entrar em reclaim direto.

## 3. O que dispara o OOM (e o que não dispara)

- O OOM **não** é disparado pelo tráfego dos clientes: eles são *bridged*; no
  máximo há drops de `GFP_ATOMIC` no datapath (sem matar processos).
- Quem dispara são **alocações de processos locais** (`wget`, `apk`, `iw`,
  forks de shell, daemons) — máscaras observadas nos relatórios:

```
gfp_mask=0x140cca (GFP_HIGHUSER_MOVABLE|__GFP_COMP), order=0   ← page fault
gfp_mask=0x140dca (GFP_HIGHUSER_MOVABLE|__GFP_COMP|__GFP_ZERO)
gfp_mask=0x140cc0 (GFP_USER|__GFP_COMP)                        ← ~GFP_KERNEL
```

- **Anomalia registrada**: o OOM foi invocado por *faults ordem-0 comuns*
  (`do_wp_page`) com **~7–8 MB livres** e blocos de todas as ordens no
  `buddyinfo` — algo que, em teoria, não deveria falhar. O kernel é vendor
  (`6.12.87 #0`, taint `O` = módulo out-of-tree); a explicação exata
  (watermark/`pcp`/migratetype) não é observável sem console serial e sem
  instrumentação adicional. **Não é THP** (o kernel não tem
  `/sys/kernel/mm/transparent_hugepage`).

## 4. Evidência de que não é vazamento

Medições ao longo de horas e entre boots:

| Contador | Comportamento |
|---|---|
| `SUnreclaim` | ~24 732 → 25 296 kB (oscila <2,5%) |
| `Slab` | ~30,8–31,8 MB (estável) |
| `KernelStack` | 1,6–1,9 MB |
| `PageTables` | 0,85–1,08 MB |
| `VmallocUsed` | ~12,1–12,3 MB |
| `Committed_AS` | ~13 MB |
| `AnonPages` | ~4,6–5,4 MB |

Nenhum cresce de forma monotônica. O que “cai” após o boot é o `Cached`
(reclaimable), consumido pelo warm-up dos pools dos drivers.

## 5. A cadeia: tempestade de OOM → watchdog → reset silencioso

Observação-chave da noite: **cada reboot veio 30–60 s depois de uma rajada de
OOM**, e **sem nenhum rastro de pânico**:

- O watchdog de hardware é o **`qcom_wdt`**: `timeout=30s`, `pretimeout=1s`,
  `nowayout=0`, `state=active`.
- O `procd` (PID 1) é quem “alimenta” o watchdog. Numa tempestade de OOM
  (reclaim direto + impressão de dumps enormes + kills em cascata), o sistema
  fica **>30 s sem escalonar o `procd`** → o watchdog dispara → **reset duro,
  sem log**.
- `panic=10` foi ativado justamente para distinguir pânico de reset duro: no
  reboot das 07:58 (com a flag ativa), **não houve nenhuma linha de pânico** no
  syslog remoto — as últimas mensagens foram a invocação do OOM, e ~30 s depois
  o boot novo. ✅ reset duro (watchdog), não pânico.
- O timeout do watchdog **não é ajustável em runtime**:
  `echo 60 > /sys/class/watchdog/watchdog0/timeout` → *Permission denied*.

### Cadência observada (noite de 18/10)

- Primeira tempestade ~35 min após o boot; depois ~a cada **20–35 min**.
- 18 reboots no total (o monitor detectou 16; a reconstrução pelo syslog achou
  também o de 00:26 e o de 08:28).
- Lista (horários do Mac; o roteador estava em UTC/+3h):
  `00:26:49, 01:18:30, 01:36:57, 01:55:18, 02:17:17, 02:40:50, 03:08:29,
  03:40:14, 04:05:51, 04:32:35, 04:50:25, 05:20:16, 05:53:58, 06:23:28,
  07:01:19, 07:25:43, 07:58:15, 08:28:11`.
- Cada reboot é seguido de **recuperação automática completa** (~1–2 min) —
  nenhum exigiu intervenção manual.

## 6. Experimentos com `vm.min_free_kbytes` (e o que aprendemos)

| Valor | Resultado |
|---|---|
| **16384** (default da imagem) | free ocioso flutua *no* piso → qualquer pico entra em reclaim → OOM em cascata sob carga |
| **8192** (teste diurno, carga) | ainda OOMava sob transferência |
| **4096** (escolhido) | melhor compromisso: os mergulhos normais ficam acima do low watermark → zero OOM nos testes de throughput |
| **8192** (teste da manhã seguinte, idle) | **pior**: com o box vivendo em ~10–12 MB, o piso de 8 MB fez o kswapd entrar em guerra permanente → OOM a cada ~3 min, SSH/probe famintos → **revertido para 4096** |

Interpretação: o watermark mínimo é **piso**, não “reserva de folga”. Numa
caixa que naturalmente vive perto dele, aumentá-lo transforma cada alocação em
reclaim direto.

## 7. Mitigações em produção (kit do repositório)

| Mitigação | O que faz | Onde |
|---|---|---|
| Caps de TCP (rmem/wmem 512 KB) + conntrack 8192 | limita picos por conexão/tabela | [router/etc/sysctl.conf](../router/etc/sysctl.conf) |
| `netdev_budget=600`, `dev_weight=128` | drena RX mais rápido em rajada | idem |
| `dnsmasq`/`odhcpd` desligados | −3 daemons e −DHCP local (modo relay) | [router/etc/config/dhcp](../router/etc/config/dhcp) |
| Blindagem `oom_score_adj=-1000` | OOM não mata rede/gestão | [guard.sh](../router/usr/local/bin/guard.sh) |
| Isca `bait.sh` (+1000) | vítima inofensiva preferencial | idem + init `guard` |
| `relief.sh` | `drop_caches` quando free<6 MB ou avail<5 MB (quebra a escalada) | [relief.sh](../router/usr/local/bin/relief.sh) |
| Scripts periódicos enxutos | menos bursts (`iw` 1×/2,5 min; 1 `ps`/ciclo) | [mon.sh](../router/usr/local/bin/mon.sh), [check.sh](../router/usr/local/bin/check.sh), guard |
| `panic=10` + syslog remoto | forense: qualquer pânico chega ao coletor antes do reset | sysctl + `/etc/config/system` |
| Probe `memprobe.sh` (10 s) | meminfo/top-RSS/buddy/zone contínuos | [memprobe.sh](../router/usr/local/bin/memprobe.sh) |

**O que funcionou de fato:**

- A blindagem + isca mantiveram **Wi-Fi/relay/gestão vivos em todos os
  eventos** — os kills passaram a atingir só isca/processos de teste.
- A recuperação automática **sempre** funcionou (rede volta em ~1–2 min).
- O `relief` e os scripts enxutos reduziram o tamanho/número das tempestades,
  mas **não eliminaram** a causa raiz.

## 8. Hipóteses descartadas (com evidência)

| Hipótese | Evidência contrária |
|---|---|
| Vazamento de memória | todos os contadores planos (tabela §4) |
| Problema térmico | 48–49 °C em todos os sensores, inclusive antes dos resets |
| Transparent Huge Pages | recurso ausente no kernel (sem sysfs) |
| Bug do guard/isca | arquivo `/etc/guard/reboots` intacto; scripts revisados |
| Pânico de kernel | `panic=10` + syslog remoto: reboot sem rastro de pânico |
| Scripts do teste (monitor) como única causa | o ciclo continuou mesmo com o monitor parado; mas os bursts do monitor *aceleravam* o gatilho |

## 9. Caminhos possíveis (não aplicados ainda)

1. **Reduzir o `q6_region`** (ex.: 47 MB) — *experimental*: exige rebuild do
   FIT + reflash e validação de que o firmware do Q6 sobe. Se o firmware
   couber, devolve memória real ao Linux. **Não testado.**
2. **zram/swap** — o kernel atual não tem zram; exigiria rebuild com
   `CONFIG_ZRAM`/`CONFIG_ZSMALLOC`; troca comprimida na RAM ajuda pouco num
   board de 160 MB, mas alivia picos.
3. **Console serial** durante um evento para capturar o exato ponto de
   falha/watcher (melhor evidência possível).
4. **Kernel/ath11k mais novos** (quando o vendor tree avançar) — pode corrigir
   a anomalia de watermark/alocação.

> Enquanto nada disso é feito, o equipamento é **utilizável** (rede sempre
> volta; throughput validado), mas com **reboots periódicos** em cenários de
> pressão de memória. A recomendação honesta: não usar como ponto único de
> rede em produção até resolver isso.

## 10. Experimentos de estabilidade (2026-10-18, sessão 2) — resultados

Imagens A/B de teste foram preparadas para eliminar os resets. Resumo do que
foi testado, tudo em hardware real:

| Experimento | Resultado |
|---|---|
| `initcall_blacklist=qcom_watchdog_driver_init` no bootargs (via DTS/FIT) | ✅ funciona (kernel loga `blacklisting initcall ...`; `/dev/watchdog` ausente). **Porém os resets continuam**: existe um **segundo mecanismo de reset (~2,5–3 min)** de nível inferior (SBL/PMIC — hipótese). Sem o watchdog de 30 s, um travamento deixa a rede fora ~3 min em vez de ~30 s → **pior disponibilidade**. Revertido. |
| `kernel.panic_on_oops=0` | Sem efeito nos eventos observados (não são oops-pânicos). Mantido por ser inócuo. |
| `pstore/ramoops` (`memmap=256K$...` + module params) | ❌ falhou: o `memmap` **não reservou** a região (`/proc/iomem` sem `0x4e300000`); o alocador reutilizou a área → registros corrompidos (`ramoops: failed to allocate buffer`) e caixa-preta vazia. Correção futura: reserva via `reserved-memory` no DTS. |
| `netconsole` builtin via cmdline | ❌ falhou no boot: `netpoll: netconsole: lan1 doesn't exist, aborting` (a porta DSA ainda não existe aos 1,6 s). Correção futura: `CONFIG_NETCONSOLE=m` + `modprobe` por script após a rede. |
| Backup/restore de config (`sysupgrade -b` / `-r`) | ✅ fluxo robusto e repetível (backup de 10 KB; imagem de 13,5 MB transferida via canal SSH em ~0,5 s). |
| Tracer de uptime/memória a 2 s (procd + TCP/UDP direto) | ✅ fundamental: capturou os últimos instantes antes de cada evento (independe do `logd`). |

**Aprendizado-chave:** o `qcom_wdt` (30 s) **não é a causa** dos resets — é o
**mecanismo de recuperação mais rápido**. O problema real está a montante: o
afundamento de memória (até ~5–6 MB livres) que precede o travamento. Com o
watchdog ativo, o equipamento se recupera em ~30 s; sem ele, em ~2,5–3 min
(mecanismo de nível inferior). **A imagem final mantém o watchdog ativo.**
