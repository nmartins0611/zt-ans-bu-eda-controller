#!/bin/bash

nmcli connection add type ethernet con-name enp2s0 ifname enp2s0 ipv4.addresses 192.168.1.12/24 ipv4.method manual connection.autoconnect yes
nmcli connection up enp2s0
echo "192.168.1.10 control.lab control" >> /etc/hosts
echo "192.168.1.11 podman.lab podman" >> /etc/hosts
echo "192.168.1.12 rhel-1.lab rhel-1" >> /etc/hosts
echo "192.168.1.13 rhel-2.lab rhel-2" >> /etc/hosts

retry() {
    for i in {1..3}; do
        echo "Attempt $i: $2"
        if $1; then
            return 0
        fi
        [ $i -lt 3 ] && sleep 5
    done
    echo "Failed after 3 attempts: $2"
    exit 1
}

retry "curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt"
retry "update-ca-trust"
retry "rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm"
retry "subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}"

echo "Registered and Ready"

echo "### Starting RHEL Node Setup Script ###"

# -----------------------------------------------------------------------------
## 1. Install System Packages and Dependencies
# -----------------------------------------------------------------------------

echo "--> Installing the EPEL repository... 📦"
# The --nogpgcheck flag is equivalent to Ansible's disable_gpg_check: true
sudo dnf install -y --nogpgcheck https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

echo "--> Ensuring 'crun' is updated to the latest version..."
sudo dnf update -y crun

echo "--> Installing required packages..."
PACKAGES=(
    "git"
    "tmux"
    "python3-pip"
    "podman-compose"
    "python3-dotenv"
)
sudo dnf install -y "${PACKAGES[@]}"

# -----------------------------------------------------------------------------
## 2. Clone the Project Repository
# -----------------------------------------------------------------------------

DEST_DIR="/tmp/eda-alertmanager"
REPO_URL="http://gitea:3000/student/eda-alertmanager.git"

echo "--> Cloning repository from ${REPO_URL}... 📥"

# For idempotency, remove the destination directory if it already exists
# to ensure a fresh clone every time the script runs.
if [ -d "$DEST_DIR" ]; then
    echo "  - Destination ${DEST_DIR} exists. Removing it first."
    rm -rf "$DEST_DIR"
fi
git clone "${REPO_URL}" "${DEST_DIR}"

# -----------------------------------------------------------------------------
## 3. Configure System and Start Services
# -----------------------------------------------------------------------------

echo "--> Enabling user lingering for 'rhel' to allow long-running services..."
sudo loginctl enable-linger rhel

echo "--> Starting node_exporter service with podman-compose... 🚀"
SERVICE_DIR="/tmp/eda-alertmanager/node_exporter"

# Change to the service directory and start the containers in detached mode.
# Using a subshell `(...)` ensures we return to the original directory afterward.
(cd "${SERVICE_DIR}" && podman-compose up -d)

echo ""
echo "✅ ### RHEL node setup complete! ###"

exit 0
