# images — artefatos gerados

As imagens **não são versionadas** neste repositório (tamanho). Os checksums
abaixo identificam exatamente o build validado em hardware; qualquer rebuild
com [configs/ax1800.config](../configs/ax1800.config) e os feeds pinados em
[configs/feeds.buildinfo](../configs/feeds.buildinfo) deve reproduzi-las.

## Arquivos do build validado

| Arquivo | Tamanho (bytes) | SHA256 |
|---|---|---|
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-initramfs-uImage.itb` | 13 229 160 | `60beda1937d55067e30603921bbd1c0995a87de1a1de304ec848000a6fd519ba` |
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-factory.ubi` | 13 500 416 | `806cf38a0d51e28c5ee18cc95adfd902ae10d1b9bb9f64d29052b74d9747139c` |
| `openwrt-qualcommax-ipq60xx-xiaomi_ax1800-squashfs-sysupgrade.bin` | 12 769 564 | `31c1aecbce202b1dc2d5fa77f1fbab5e13aa5f81d53773e38f166c1c02c97971` |

Outros metadados versionados aqui:

- `SHA256SUMS` — checksums oficiais do build (inclui config/feeds/manifest).
- `manifest.txt` — lista de pacotes/versões instalados na imagem.
- `profiles.json` — metadados do perfil `xiaomi_ax1800` (pacotes de device,
  imagens e SHA256).

## Para que serve cada imagem

- **`initramfs-uImage.itb`** — boot **em RAM** via UART+TFTP
  (`tftpboot` + `bootm`). Não toca na NAND; ideal para testar/validar e para
  recuperação.
- **`factory.ubi`** — gravação “crua” em um slot UBI via `ubiformat`
  (`/dev/mtd12` = `rootfs`, `/dev/mtd13` = `rootfs_1`). Foi o método usado na
  instalação inicial (slot 1).
- **`sysupgrade.bin`** — atualização normal pelo OpenWrt (`sysupgrade`),
  gravando no **slot alternado** (A/B) automaticamente.

## Verificação rápida

```bash
sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS
```
