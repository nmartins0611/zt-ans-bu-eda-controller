#!/bin/bash

nmcli connection add type ethernet con-name eth1 ifname eth1 ipv4.addresses 192.168.1.11/24 ipv4.method manual connection.autoconnect yes
nmcli connection up eth1
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


echo "### Starting Podman Setup Script ###"

# -----------------------------------------------------------------------------
## 1. Install System Packages
# -----------------------------------------------------------------------------
echo "--> Installing EPEL repository..."
# The --nogpgcheck flag is equivalent to disable_gpg_check: true
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
## 2. Configure Gitea Repositories
# -----------------------------------------------------------------------------
REPOS=("eda-project" "eda-alertmanager")
echo "--> Setting default branch to 'aap25' in Gitea for repositories..."
for repo in "${REPOS[@]}"; do
    echo "  - Updating ${repo}"
    # Use curl to send a PATCH request to the Gitea API
    # The --insecure flag is equivalent to validate_certs: no
    curl --insecure --user gitea:gitea --request PATCH \
         --header "Content-Type: application/json" \
         --data '{"default_branch": "aap25"}' \
         "http://gitea:3000/api/v1/repos/student/${repo}"
done
# Add a newline for cleaner output
echo ""

# -----------------------------------------------------------------------------
## 3. Clone Git Repositories
# -----------------------------------------------------------------------------
echo "--> Cloning repositories from Gitea..."
for repo in "${REPOS[@]}"; do
    DEST_DIR="/tmp/${repo}"
    REPO_URL="http://gitea:3000/student/${repo}.git"

    echo "  - Cloning branch 'aap25' from ${REPO_URL} to ${DEST_DIR}"
    
    # Remove the destination directory if it exists to mimic 'force: true'
    if [ -d "$DEST_DIR" ]; then
        echo "    - Destination ${DEST_DIR} exists. Removing it first."
        rm -rf "$DEST_DIR"
    fi

    git clone --branch aap25 "${REPO_URL}" "${DEST_DIR}"
done

# -----------------------------------------------------------------------------
## 4. Start Podman Services
# -----------------------------------------------------------------------------
echo "--> Starting node_exporter service with podman-compose..."
# Use a subshell to change directory temporarily
(cd "/tmp/eda-alertmanager/node_exporter" && podman-compose up -d)

# The webhook service was commented out in the playbook and is omitted here.

echo "--> Starting prometheus service with podman-compose..."
(cd "/tmp/eda-alertmanager/prometheus" && podman-compose up -d)

echo ""
echo "### Setup complete! ###"


exit 0
