#!/bin/bash

TARGET_URL="$1"

if [ -z "$TARGET_URL" ]; then
    echo "Usage: $0 <http://target-site>"
    exit 1
fi

# Detect package manager
detect_pkg_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
    else
        PKG_MANAGER="unknown"
    fi
}

# Check if docker is installed
if command -v docker >/dev/null 2>&1; then
    echo "Docker detected. Running WPScan container..."
    
    docker run --rm -it wpscanteam/wpscan \
    --url "$TARGET_URL" \
    --enumerate p,u
    
    exit 0
fi

echo "Docker is not installed on this system."
echo
echo "Running WPScan via Docker is the recommended approach."
echo "Installing WPScan via Ruby gems can cause dependency conflicts."
echo

read -p "Would you like to install WPScan via Ruby gems instead? (y/N): " choice

if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo "Exiting without installing WPScan."
    exit 0
fi

detect_pkg_manager

echo "Detected package manager: $PKG_MANAGER"
echo "Installing Ruby dependencies..."

case "$PKG_MANAGER" in
    apt)
        sudo apt update
        sudo apt install -y ruby-full build-essential libcurl4-openssl-dev git
        ;;
    dnf)
        sudo dnf install -y ruby ruby-devel gcc make curl-devel git
        ;;
    yum)
        sudo yum install -y ruby ruby-devel gcc make libcurl-devel git
        ;;
    pacman)
        sudo pacman -Sy --noconfirm ruby base-devel git
        ;;
    zypper)
        sudo zypper install -y ruby ruby-devel gcc make libcurl-devel git
        ;;
    *)
        echo "Unsupported package manager. Install Ruby manually."
        exit 1
        ;;
esac

echo "Installing WPScan via Ruby gems..."
gem install wpscan --user-install

echo
echo "WPScan installed via gem."
echo "You may need to add the gem binary path to your PATH environment variable."

echo
echo "Example usage:"
echo "wpscan --url $TARGET_URL --enumerate p,u"
