# 05 — Calibração Wi-Fi (ART) — causa raiz e correção

## Sintoma

Após o primeiro boot, os rádios apareciam no kernel (`c000000.wifi`,
`c000000.wifi+1`), mas **nenhuma interface wireless** era criada e o firmware
ath11k não inicializava.

## Causa raiz (dupla)

### 1. O script de cal não conhecia o AX1800

`target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata`
não tinha `case` para `xiaomi,ax1800` → a calibração **nunca era extraída** da
partição `0:ART` no boot.

### 2. O tamanho padrão (128 KB) está errado para este aparelho

Mesmo extraindo à mão, o firmware ath11k morria ao carregar. A análise do dump
da ART (`mtd8_0_ART.bin`, 512 KB) mostrou:

```
0x1000  .. 0x11000: 65 536 bytes — apenas 185 são 0xFF   ← cal válida (64 KB)
0x11000 .. 0x21000: 65 536 bytes — 65 536 são 0xFF       ← região NÃO gravada
```

O script genérico da família usa `0x20000` (**128 KB**). Os 64 KB extras são
lixo (`0xFF`) e derrubam o parser do firmware.

## Correção definitiva (no build)

`target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata`:

```sh
xiaomi,ax1800|\
redmi,ax1800)
	caldata_extract "0:ART" 0x1000 0x10000
	;;
```

- A label `0:ART` (maiúscula) é exatamente a do DTS.
- `0x10000` = **64 KB** (não 128 KB).

## Band-aid no roteador (runtime)

Para equipamentos já gravados (e como cinto de segurança), o kit inclui
[`router/etc/hotplug.d/firmware/20-xiaomi-ax1800-cal`](../router/etc/hotplug.d/firmware/20-xiaomi-ax1800-cal):

- escuta o hotplug de `ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin`;
- se o arquivo **não existir ou estiver vazio**, extrai da ART com
  `0x1000/0x10000`;
- é **no-op** quando o script de build já gerou a cal.

## BDF (board-2.bin)

- Arquivo: `board-xiaomi_ax1800.ipq6018` (65 640 B), variant
  **`Xiaomi-AX1800`**, sem MACs embutidos.
- Empacotado como `ipq-wifi-xiaomi_ax1800` e instalado em
  `/lib/firmware/ath11k/IPQ6018/hw1.0/board-2.bin`.
- sha256: `9f841a8d8582e1fd924e54767842dbf794f870cc37a36bf95065755faa4a85ba`
  (idêntico ao embedado na imagem validada).

## Validação no equipamento

```sh
ls -l /lib/firmware/ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin   # 65536
ls -l /lib/firmware/ath11k/IPQ6018/hw1.0/board-2.bin                # 65640
iw dev                                                              # radio0/radio1 + ifaces
```

Resultado observado:

- STA associado ao AP principal (60 GHz? não — **5 GHz**, `HE80`, canal 149,
  sinal ≈ −35 dBm);
- APs `HomeNet` no ar em 2,4 GHz e 5 GHz;
- throughput e estabilidade conforme [08-validation](08-validation-2026-10-18.md).

## Lição

Em boards IPQ60xx cujo ART é parcialmente gravada, **o tamanho da cal deve ser
o do bloco realmente escrito** — o `0x20000` “padrão da família” é uma
armadilha silenciosa: o arquivo existe, tem o tamanho esperado e mesmo assim o
firmware falha.
