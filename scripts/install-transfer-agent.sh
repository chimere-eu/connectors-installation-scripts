#!/usr/bin/env bash
set -euo pipefail

DEB_REPO_URL="https://deb.download.chimere.eu"
RPM_REPO_URL="https://rpm.download.chimere.eu"
DEB_KEY_URL="https://deb.download.chimere.eu/chimere-repo.gpg.key"
RPM_KEY_URL="https://rpm.download.chimere.eu/chimere-repo.gpg.key"
PKG="chimere-transfer-agent"

echo "Detecting operating system..."

# Detect OS and version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    DISTRO_VER=${VERSION_ID%%.*}
else
    echo "Could not detect OS via /etc/os-release"
    exit 1
fi

echo "Detected: $NAME $VERSION_ID"

# --- Debian/Ubuntu based ---
if command -v apt-get >/dev/null 2>&1; then
    CODENAME=$VERSION_CODENAME
    SUPPORTED_DEBIAN=(focal jammy noble bookworm bullseye)

    if [[ " ${SUPPORTED_DEBIAN[*]} " == *" $CODENAME "* ]]; then
        echo "Using repo for codename: $CODENAME"
    else
        echo "Unsupported Debian/Ubuntu codename ($CODENAME), defaulting to 'jammy'"
        CODENAME="jammy"
    fi

    # Prepare keyrings
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL "$DEB_KEY_URL" | gpg --dearmor -o /etc/apt/keyrings/chimere.gpg

    # Add repo
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/chimere.gpg] $DEB_REPO_URL $CODENAME main" \
        | tee /etc/apt/sources.list.d/chimere.list > /dev/null

    apt-get update
    apt-get install -y "$PKG"

# --- RHEL/CentOS/OracleLinux based ---
elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    MAJOR_VER=${DISTRO_VER}
    SUPPORTED_RHEL=(8 9)

    if [[ " ${SUPPORTED_RHEL[*]} " == *" $MAJOR_VER "* ]]; then
        echo "Using repo for EL$MAJOR_VER"
    else
        echo "Unsupported RHEL-based version ($DISTRO_ID $MAJOR_VER), defaulting to 9"
        MAJOR_VER=9
    fi

    # Create repo file
    cat > /etc/yum.repos.d/chimere.repo <<EOF
[chimere-el$MAJOR_VER]
name=Chimere Repository
baseurl=$RPM_REPO_URL/rhel$MAJOR_VER
enabled=1
gpgcheck=1
gpgkey=$RPM_KEY_URL
EOF

    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$PKG"
    else
        yum install -y "$PKG"
    fi

else
    echo "Unsupported package manager. Only apt, dnf, and yum are supported."
    exit 1
fi

echo "$PKG installed successfully"
