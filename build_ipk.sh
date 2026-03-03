#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_DIR="$ROOT_DIR/luci-app-passwall2"
MAKEFILE="$PKG_DIR/Makefile"
DIST_DIR="$ROOT_DIR/dist"

require_file() {
	local path=$1
	[ -f "$path" ] || {
		echo "Missing required file: $path" >&2
		exit 1
	}
}

trim() {
	sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

parse_simple_var() {
	local name=$1
	awk -F ':=' -v key="$name" '$1 == key { print $2; exit }' "$MAKEFILE" | trim
}

parse_depends() {
	local raw token deps=()

	raw=$(
		awk '
			/^LUCI_DEPENDS:=/ { capture = 1 }
			capture {
				line = $0
				sub(/^LUCI_DEPENDS:=/, "", line)
				gsub(/\\/, "", line)
				gsub(/^[[:space:]]+/, "", line)
				if (length(line) > 0) {
					print line
				}
				if ($0 !~ /\\$/) {
					exit
				}
			}
		' "$MAKEFILE"
	)

	for token in $raw; do
		token=${token#+}
		case "$token" in
			*:* )
				continue
				;;
		esac
		deps+=("$token")
	done

	deps+=("luci-lua-runtime")
	printf '%s\n' "${deps[@]}" | awk '
		!seen[$0]++ {
			if (count > 0) {
				printf ", "
			}
			printf "%s", $0
			count++
		}
		END {
			printf "\n"
		}
	'
}

parse_conffiles() {
	awk '
		$0 ~ /^define Package\/.*\/conffiles$/ { capture = 1; next }
		capture && $0 ~ /^endef$/ { exit }
		capture && length($0) > 0 { print }
	' "$MAKEFILE"
}

build_control_scripts() {
	local control_dir=$1

	cat > "$control_dir/postinst" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@
EOF
	chmod 0755 "$control_dir/postinst"

	cat > "$control_dir/prerm" <<'EOF'
#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@
EOF
	chmod 0755 "$control_dir/prerm"

	cat > "$control_dir/postinst-pkg" <<'EOF'
[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
EOF
	chmod 0755 "$control_dir/postinst-pkg"
}

stage_data_tree() {
	local data_dir=$1

	mkdir -p "$data_dir/usr/lib/lua/luci" "$data_dir/www"

	if [ -d "$PKG_DIR/root" ]; then
		cp -a "$PKG_DIR/root/." "$data_dir/"
	fi
	if [ -d "$PKG_DIR/luasrc/controller" ]; then
		cp -a "$PKG_DIR/luasrc/controller" "$data_dir/usr/lib/lua/luci/"
	fi
	if [ -d "$PKG_DIR/luasrc/model" ]; then
		cp -a "$PKG_DIR/luasrc/model" "$data_dir/usr/lib/lua/luci/"
	fi
	if [ -d "$PKG_DIR/luasrc/passwall2" ]; then
		cp -a "$PKG_DIR/luasrc/passwall2" "$data_dir/usr/lib/lua/luci/"
	fi
	if [ -d "$PKG_DIR/luasrc/view" ]; then
		cp -a "$PKG_DIR/luasrc/view" "$data_dir/usr/lib/lua/luci/"
	fi
	if [ -d "$PKG_DIR/htdocs" ]; then
		cp -a "$PKG_DIR/htdocs/." "$data_dir/www/"
	fi
}

main() {
	local pkg_name pkg_version pkg_release pkg_arch luci_title depends
	local control_version package_file work_dir data_dir control_dir pkg_dir
	local installed_size

	require_file "$MAKEFILE"

	pkg_name=$(parse_simple_var "PKG_NAME")
	pkg_version=$(parse_simple_var "PKG_VERSION")
	pkg_release=$(parse_simple_var "PKG_RELEASE")
	pkg_arch=$(parse_simple_var "LUCI_PKGARCH")
	luci_title=$(parse_simple_var "LUCI_TITLE")
	depends=$(parse_depends)

	control_version="${pkg_version}-r${pkg_release}"
	package_file="${DIST_DIR}/${pkg_name}_${control_version}_${pkg_arch}.ipk"

	work_dir=$(mktemp -d "${TMPDIR:-/tmp}/passwall2-ipk.XXXXXX")
	trap "rm -rf '$work_dir'" EXIT

	data_dir="$work_dir/data"
	control_dir="$work_dir/control"
	pkg_dir="$work_dir/pkg"

	mkdir -p "$data_dir" "$control_dir" "$pkg_dir" "$DIST_DIR"

	stage_data_tree "$data_dir"
	build_control_scripts "$control_dir"

	parse_conffiles > "$control_dir/conffiles"

	installed_size=$(du -sk "$data_dir" | cut -f1)

	cat > "$control_dir/control" <<EOF
Package: ${pkg_name}
Version: ${control_version}
Depends: ${depends}
Source: local/${pkg_name}
SourceName: ${pkg_name}
Section: luci
URL: https://github.com/openwrt/luci
Maintainer: OpenWrt LuCI community
Architecture: ${pkg_arch}
Installed-Size: ${installed_size}
Description:  ${luci_title}
EOF

	printf '2.0\n' > "$pkg_dir/debian-binary"
	tar -C "$data_dir" -czf "$pkg_dir/data.tar.gz" .
	tar -C "$control_dir" -czf "$pkg_dir/control.tar.gz" .

	find "$DIST_DIR" -mindepth 1 ! -name '.gitignore' -exec rm -rf {} +
	[ -f "$DIST_DIR/.gitignore" ] || printf '*\n!.gitignore\n' > "$DIST_DIR/.gitignore"

	tar -C "$pkg_dir" -czf "$package_file" ./debian-binary ./data.tar.gz ./control.tar.gz

	echo "Built: $package_file"
}

main "$@"
