#!/usr/bin/env bash
set -euo pipefail

DEB_REPO_URL="https://deb.download.chimere.eu"
RPM_REPO_URL="https://rpm.download.chimere.eu"
DEB_KEY_URL="https://deb.download.chimere.eu/chimere-repo.gpg.key"
RPM_KEY_URL="https://rpm.download.chimere.eu/chimere-repo.gpg.key"
PKG="chimere-agent"

APT_KEYRING="/etc/apt/keyrings/chimere.gpg"
APT_SOURCE="/etc/apt/sources.list.d/chimere.list"
RPM_KEYRING="/etc/pki/rpm-gpg/RPM-GPG-KEY-chimere"
RPM_REPO_FILE="/etc/yum.repos.d/chimere.repo"

tmp_dir=""

log() {
    printf '==> %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
        rm -rf -- "$tmp_dir"
    fi
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "This installer must be run as root. Try: curl -fsSL https://get.chimere.eu/chimere-agent.sh | sudo bash"
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

create_tmp_dir() {
    tmp_dir="$(mktemp -d)" || die "Failed to create temporary directory"
}

require_deb_arch() {
    local arch

    arch="$(dpkg --print-architecture)"
    [[ "$arch" == "amd64" ]] || die "Unsupported Debian architecture: $arch. Only amd64 is supported."
}

require_rpm_arch() {
    local arch

    arch="$(rpm --eval '%{_arch}')"
    [[ "$arch" == "x86_64" ]] || die "Unsupported RPM architecture: $arch. Only x86_64 is supported."
}

install_from_apt() {
    local cmd key_file keyring_file source_file

    log "Using Chimere apt repository"

    for cmd in apt-get dpkg curl gpg install mktemp; do
        require_cmd "$cmd"
    done
    require_deb_arch
    create_tmp_dir

    key_file="$tmp_dir/chimere-repo.gpg.key"
    keyring_file="$tmp_dir/chimere.gpg"
    source_file="$tmp_dir/chimere.list"

    log "Downloading Chimere apt signing key"
    curl -fsSL "$DEB_KEY_URL" -o "$key_file"
    gpg --dearmor --yes -o "$keyring_file" "$key_file"
    printf 'deb [arch=amd64 signed-by=%s] %s stable main\n' "$APT_KEYRING" "$DEB_REPO_URL" > "$source_file"

    install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
    install -m 0644 "$keyring_file" "$APT_KEYRING"
    install -m 0644 "$source_file" "$APT_SOURCE"

    log "Updating apt package lists"
    apt-get update

    log "Installing $PKG"
    apt-get install -y "$PKG"
}

install_from_rpm() {
    local cmd key_file package_manager repo_file

    log "Using Chimere yum/dnf repository"

    if command -v dnf >/dev/null 2>&1; then
        package_manager="dnf"
    else
        package_manager="yum"
    fi

    for cmd in "$package_manager" rpm curl install mktemp; do
        require_cmd "$cmd"
    done
    require_rpm_arch
    create_tmp_dir

    key_file="$tmp_dir/RPM-GPG-KEY-chimere"
    repo_file="$tmp_dir/chimere.repo"

    log "Downloading Chimere RPM signing key"
    curl -fsSL "$RPM_KEY_URL" -o "$key_file"

    cat > "$repo_file" <<EOF
[chimere]
name=Chimere Repository
baseurl=$RPM_REPO_URL
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$RPM_KEYRING
EOF

    install -d -m 0755 /etc/pki/rpm-gpg /etc/yum.repos.d
    install -m 0644 "$key_file" "$RPM_KEYRING"
    rpm --import "$RPM_KEYRING"
    install -m 0644 "$repo_file" "$RPM_REPO_FILE"

    log "Installing $PKG"
    "$package_manager" install -y "$PKG"
}

main() {
    trap cleanup EXIT

    require_root

    log "Detecting package manager"
    if command -v apt-get >/dev/null 2>&1; then
        install_from_apt
    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        install_from_rpm
    else
        die "Unsupported package manager. Only apt, dnf, and yum are supported."
    fi

    log "$PKG installed successfully"
}

main "$@"
