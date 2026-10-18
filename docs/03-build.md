# 03 — Build

## Base

| Item | Valor |
|---|---|
| OpenWrt | **v25.12.4** — commit `ba915c2` (release oficial) |
| Target | `qualcommax/ipq60xx` |
| Perfil | `xiaomi_ax1800` |
| Kernel | 6.12.87 |
| Toolchain | `aarch64_cortex-a53` (musl) |
| Revisão final | `r32933-4ccb782af7` |

Os feeds usados estão pinados em
[configs/feeds.buildinfo](../configs/feeds.buildinfo).

## Preparação da árvore

```bash
git clone https://git.openwrt.org/openwrt/openwrt.git
cd openwrt
git checkout ba915c2

# port (DTS, mk, board.d, bootcount, platform.sh, envtools, ipq-wifi, caldata)
git am /caminho/ax1800-openwrt/src/patches/0001-ipq60xx-add-Xiaomi-AX1800.patch

# overlay de build (IP/máscara de gestão no primeiro boot)
cp -r /caminho/ax1800-openwrt/src/overlay/files .

# configuração do build
cp /caminho/ax1800-openwrt/configs/ax1800.config .config
make defconfig
```

> Se você pretende usar o modo repetidor desde o primeiro boot, habilite o
> pacote do relayd antes do build (ver [configs/README](../configs/README.md)):
> `echo CONFIG_PACKAGE_relayd=y >> .config && make defconfig`.

## Build (ambiente usado: macOS + Docker)

O build do autor rodou em um container Linux (`owrt-build`), com a árvore
montada por volumes. Dois gotchas importantes do macOS:

1. **VirtioFS não suporta *punch-hole*** → `install(1)`/`cp` falham com
   `error deallocating`. Solução: manter `staging_dir/`, `build_dir/`, `tmp/`,
   `bin/` e `dl/` como **volumes Docker** (montados em `/vol-*`) e criar
   symlinks na árvore.
2. **Build como root** exige `FORCE_UNSAFE_CONFIGURE=1` (GNU tar/configure).

Comandos:

```bash
# subir/entrar no container
docker start owrt-build
docker exec -it owrt-build bash

# dentro do container (árvore em /build)
cd /build
export FORCE_UNSAFE_CONFIGURE=1
make -j"$(nproc)"
```

### Copiando as imagens (container → host)

```bash
docker exec owrt-build bash -c \
  'cd /build/bin/targets/qualcommax/ipq60xx && tar cf - openwrt-qualcommax-ipq60xx-xiaomi_ax1800-*' \
  | tar xf - -C ~/ax1800/images
```

## Artefatos

| Arquivo | Uso |
|---|---|
| `...initramfs-uImage.itb` | boot em RAM (UART+TFTP) |
| `...squashfs-factory.ubi` | instalação via `ubiformat` em um slot |
| `...squashfs-sysupgrade.bin` | `sysupgrade` (slot alternado) |

Checksums do build validado: [images/README](../images/README.md).

## Verificação pós-build (o que foi checado)

O script de verificação (executado **dentro** do container, na pasta `bin/`)
confere:

1. **Volumes UBI** no `factory.ubi` (`kernel`, `rootfs`) e o layout da VTBL.
2. **FIT do kernel**: `default = "config@cp03-c1"` (o mesmo config que o U-Boot
   stock usa), kernel 6.12.87 gzip.
3. **DTB embutido no FIT**: `bootargs-append = " root=/dev/ubiblock0_1"`,
   `model = "Xiaomi Redmi AX1800"`, 16 partições, bmps `0x1c/0x20`, reset do
   MDIO `<0x4b 0x01>`, `KEY_RESTART` e `label-mac-device`.
4. **rootfs**: `bootcount`, `02_network`, `platform.sh`,
   `30_uboot-envtools`, `fw_printenv/fw_setenv` presentes.
5. **BDF**: `board-2.bin` da imagem com **sha256 idêntico** ao
   `src/files/board-xiaomi_ax1800.ipq6018`.
6. **sysupgrade.bin**: tar `sysupgrade-xiaomi_ax1800/{CONTROL,kernel,root}`.
7. **Scripts**: `dash -n`/`sh -n` sem erros; pacote
   `ipq-wifi-xiaomi_ax1800` no manifest.

## Reproducibilidade

- Use `configs/ax1800.config` (ou `config.buildinfo` sobre o defconfig).
- Feeds pinados (commit exato em `feeds.buildinfo`).
- O `images/SHA256SUMS` permite comparar um rebuild com o build validado.
  Diferenças de toolchain do host podem mudar bytes do squashfs mesmo com
  configuração idêntica — nesse caso compare o conteúdo (`manifest.txt`) e o
  comportamento em hardware.

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| `error deallocating` no build | VirtioFS/punch-hole | usar volumes Docker para `staging_dir`, `build_dir`, `tmp`, `bin`, `dl` |
| `configure: error: you should not run configure as root` | build como root | `export FORCE_UNSAFE_CONFIGURE=1` |
| `ipq-wifi` não encontra o BDF | pacote sem o arquivo local | confirme o patch do Makefile (wildcard `$(CURDIR)/files/`) |
| `fw_printenv` sem config no device | primeiro boot incompleto | `bootcount` recria `/etc/fw_env.config`; ver [10-troubleshooting](10-troubleshooting.md) |
