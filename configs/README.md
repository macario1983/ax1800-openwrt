# configs — configuração de build

| Arquivo | O que é |
|---|---|
| `ax1800.config` | **snapshot completo** do `.config` usado no build (284 KB). Reproduz exatamente o conjunto de pacotes/opções. |
| `config.buildinfo` | **diff mínimo** em relação ao defconfig do target — o jeito recomendado de descrever o build (1 KB). |
| `feeds.buildinfo` | revisões **pinadas** dos feeds usados (packages, luci, routing, telephony, video). |
| `version.buildinfo` | versão/revisão do OpenWrt (`r32933-4ccb782af7`). |

## Como usar

O caminho mais confiável é copiar o snapshot completo antes do `make defconfig`:

```bash
cp configs/ax1800.config .config
make defconfig
```

> **Nota:** `ax1800.config` contém o estado final da árvore do autor. O
> `config.buildinfo` é a fonte de verdade do que é **diferente** do padrão do
> target e serve para revisar/portar a configuração para versões futuras.

## Conteúdo relevante do build

- Target: `qualcommax` / `ipq60xx`
- Device: `xiaomi_ax1800`
- LuCI completo (`luci`, `luci-mod-admin-full`, `luci-proto-ipv6`, …)
- `uboot-envtools`, `ipq-wifi-xiaomi_ax1800`
- `wpad-basic-mbedtls`, `dropbear`, `dnsmasq`, `odhcpd-ipv6only`, `firewall4`
- Sem `dnsmasq`/`odhcpd` habilitados em runtime (modo repetidor) — mas os
  pacotes continuam na imagem para permitir modo router no futuro.

> ⚠️ **Achado da revisão:** o pacote **`relayd` NÃO está na imagem** validada
> (`# CONFIG_PACKAGE_relayd is not set`, ausente do manifest). Ele foi
> **instalado no roteador após o flash** e habilitado como serviço próprio
> (`/etc/rc.d/S80relayd`). O `proto 'relay'` no UCI não cria um handler no
> netifd — quem inicia o daemon é o init do pacote `relayd`, que lê os
> `config interface` com `proto=relay` e resolve `network`/`ifname`
> (detalhes em [docs/06](../docs/06-repeater-relay.md) e
> [docs/09](../docs/09-code-review.md)). Para um build reprodutível do modo
> repetidor **desde o primeiro boot**, habilite no `.config`:
>
> ```
> CONFIG_PACKAGE_relayd=y
> ```
>
> Isso não altera o restante da configuração; o service trigger do init
> recarrega o relayd quando a rede muda.
