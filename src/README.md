# src — código-fonte do port

Tudo o que é necessário para reproduzir o port sobre uma árvore limpa do
OpenWrt **v25.12.4** (commit `ba915c2`).

## Conteúdo

| Caminho | Descrição |
|---|---|
| `patches/0001-ipq60xx-add-Xiaomi-AX1800.patch` | patch `git am` com **todo** o port: DTS, `ipq60xx.mk`, `board.d`, `bootcount`, `platform.sh`, `uboot-envtools`, `ipq-wifi` (Makefile + BDF) e `11-ath11k-caldata` |
| `overlay/files/etc/uci-defaults/99-xiaomi-ax1800-lan` | overlay de build (não faz parte do patch): fixa o IP/máscara de gestão do firmware (`192.168.31.1/24`) no primeiro boot |
| `files/ipq6000-xiaomi-ax1800.dts` | cópia avulsa do DTS (referência/consulta) |
| `files/board-xiaomi_ax1800.ipq6018` | cópia avulsa do BDF (variant `Xiaomi-AX1800`) |

## Aplicação

```bash
cd openwrt                       # árvore limpa do OpenWrt
git checkout ba915c2             # v25.12.4
git am /caminho/ax1800-openwrt/src/patches/0001-ipq60xx-add-Xiaomi-AX1800.patch
cp -r /caminho/ax1800-openwrt/src/overlay/files .
cp /caminho/ax1800-openwrt/configs/ax1800.config .config
make defconfig
make -j$(nproc)
```

## Por que o overlay não está no patch?

O diretório `files/` na raiz da árvore do OpenWrt é **conteúdo local do
build** (não versionado pelo upstream). O arquivo
`99-xiaomi-ax1800-lan` corrige o clássico problema de o OpenWrt subir com
`192.168.1.1` — que colidiria com a rede do roteador principal no cenário de
repetidor — e define a máscara explicitamente (o bug do `/32` está descrito em
[docs/04](../docs/04-flash-and-recovery.md)).

Se você quiser transformar isso em parte do port “upstreamável”, mova o arquivo
para `target/linux/qualcommax/files/etc/uci-defaults/` — ele passará a ser
incluído na imagem pelo próprio target (é o que o patch do DTS já faz com
outros arquivos de `files/`).

## Notas de proveniência

- O **BDF** (`board-xiaomi_ax1800.ipq6018`, 65 640 bytes,
  sha256 `9f841a8d8582e1fd924e54767842dbf794f870cc37a36bf95065755faa4a85ba`)
  é a imagem de board-2 do AX1800 (variant `Xiaomi-AX1800`), sem MACs
  embutidos. É instalado como `/lib/firmware/ath11k/IPQ6018/hw1.0/board-2.bin`
  pelo pacote `ipq-wifi-xiaomi_ax1800`.
- A alteração no `ipq-wifi/Makefile` (além de adicionar o pacote) estende o
  wildcard do `install-overlay` para também aceitar BDFs presentes em
  `package/firmware/ipq-wifi/files/` — é o que permite manter o BDF dentro da
  árvore do port, sem depender do repositório oficial `ipq-wifi`.
- O patch **não** mexe em código compartilhado do target além dos pontos
  listados; ele foi aplicado sobre `ba915c2` e compilado duas vezes (árvore
  canônica e árvore de build), gerando exatamente as imagens publicadas nos
  checksums de [images/SHA256SUMS](../images/SHA256SUMS).
