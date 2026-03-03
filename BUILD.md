# Build IPK From This Repository

This repository can build a fresh `ipk` directly from the checked-out source.
No OpenWrt SDK or buildroot is used here.

The build is intentionally simple:

- take the current contents of `luci-app-passwall2/`
- assemble a new `ipk`
- fully replace the contents of `dist/`
- leave only the fresh package and `dist/.gitignore`

Package metadata is read from [luci-app-passwall2/Makefile](/home/lexus/WORKSPACE/PROJECTS/passwall2/openwrt-passwall2/luci-app-passwall2/Makefile).

Current values:

- `PKG_NAME=luci-app-passwall2`
- `PKG_VERSION=26.3.1`
- `PKG_RELEASE=1`
- `LUCI_PKGARCH=all`

Expected output file:

```bash
dist/luci-app-passwall2_26.3.1-r1_all.ipk
```

## Build Command

Run from the repository root:

```bash
./build_ipk.sh
```

What this command does:

- stages files from `luci-app-passwall2/root/`
- maps `luasrc/` into `/usr/lib/lua/luci/`
- maps `htdocs/` into `/www/`
- generates `control`, `conffiles`, `postinst`, `prerm`, `postinst-pkg`
- builds `debian-binary`, `data.tar.gz`, `control.tar.gz`
- removes everything in `dist/` except `dist/.gitignore`
- writes the new `ipk` into `dist/`

## Result

After a successful build, `dist/` should contain:

- `dist/.gitignore`
- `dist/luci-app-passwall2_26.3.1-r1_all.ipk`

## Quick Verification

Check the package exists:

```bash
ls -1 dist/luci-app-passwall2_26.3.1-r1_all.ipk
```

Check the top-level package members:

```bash
tar -tf dist/luci-app-passwall2_26.3.1-r1_all.ipk
```

Expected entries:

- `./debian-binary`
- `./control.tar.gz`
- `./data.tar.gz`

Check the package format marker:

```bash
tar -xOf dist/luci-app-passwall2_26.3.1-r1_all.ipk ./debian-binary
```

Expected output:

```text
2.0
```

Check control metadata:

```bash
tar -xOf dist/luci-app-passwall2_26.3.1-r1_all.ipk ./control.tar.gz | tar -xzO ./control
```

Expected fields:

- `Package: luci-app-passwall2`
- `Version: 26.3.1-r1`
- `Architecture: all`

## Notes

- This is a local repack of the repository contents, not an OpenWrt feed build.
- `Architecture: all` is correct because this LuCI package is architecture-independent.
- Runtime dependencies still must exist on the router when installing with `opkg`.
