#!/usr/bin/env bash
# =============================================================================
#  setup.sh — Install all DevOps tools on Ubuntu/Debian
#  Run once on a fresh machine or CI agent.
#  Usage: sudo ./scripts/setup.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${RESET}"; }
info() { echo -e "${CYAN}▶  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }

# ── Versions ──────────────────────────────────────────────────────────────────
NODE_VERSION="18"
KUBECTL_VERSION="1.28.0"
HELM_VERSION="3.12.0"
DOCKER_COMPOSE_VERSION="2.21.0"
TRIVY_VERSION="0.45.0"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║  DevOps Tools Setup — Ubuntu/Debian      ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${RESET}"

# ── System update ─────────────────────────────────────────────────────────────
info "Updating system packages..."
apt-get update -qq
apt-get install -y -qq \
  curl wget git unzip jq ca-certificates gnupg lsb-release \
  apt-transport-https software-properties-common netcat-openbsd
ok "System packages updated"

# ── Docker ────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Installing Docker..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io
  systemctl enable --now docker
  ok "Docker $(docker --version) installed"
else
  ok "Docker already installed: $(docker --version)"
fi

# ── Docker Compose ────────────────────────────────────────────────────────────
if ! command -v docker-compose &>/dev/null; then
  info "Installing Docker Compose v${DOCKER_COMPOSE_VERSION}..."
  curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ok "Docker Compose $(docker-compose --version) installed"
else
  ok "Docker Compose already installed"
fi

# ── Node.js ───────────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  info "Installing Node.js ${NODE_VERSION}..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
  apt-get install -y -qq nodejs
  ok "Node.js $(node --version) + npm $(npm --version) installed"
else
  ok "Node.js already installed: $(node --version)"
fi

# ── kubectl ───────────────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  info "Installing kubectl v${KUBECTL_VERSION}..."
  curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
  ok "kubectl $(kubectl version --client --short 2>/dev/null || true) installed"
else
  ok "kubectl already installed: $(kubectl version --client --short 2>/dev/null || true)"
fi

# ── Helm ──────────────────────────────────────────────────────────────────────
if ! command -v helm &>/dev/null; then
  info "Installing Helm v${HELM_VERSION}..."
  curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar xz -C /tmp
  mv /tmp/linux-amd64/helm /usr/local/bin/helm
  ok "Helm $(helm version --short) installed"
else
  ok "Helm already installed: $(helm version --short)"
fi

# ── AWS CLI ───────────────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
  info "Installing AWS CLI v2..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/aws-cli
  /tmp/aws-cli/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws-cli
  ok "AWS CLI $(aws --version) installed"
else
  ok "AWS CLI already installed: $(aws --version)"
fi

# ── Trivy (security scanner) ──────────────────────────────────────────────────
if ! command -v trivy &>/dev/null; then
  info "Installing Trivy v${TRIVY_VERSION}..."
  wget -qO- "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
    | tar xz -C /usr/local/bin trivy
  ok "Trivy $(trivy --version) installed"
else
  ok "Trivy already installed"
fi

# ── MySQL client ──────────────────────────────────────────────────────────────
if ! command -v mysql &>/dev/null; then
  info "Installing MySQL client..."
  apt-get install -y -qq mysql-client
  ok "MySQL client installed"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════ All Tools Installed ════${RESET}"
for cmd in docker docker-compose node npm kubectl helm aws trivy mysql; do
  if command -v "$cmd" &>/dev/null; then
    printf "  ${GREEN}✅ %-16s${RESET} %s\n" "$cmd" "$($cmd --version 2>&1 | head -1)"
  else
    printf "  ${YELLOW}⚠️  %-16s${RESET} not found\n" "$cmd"
  fi
done

echo ""
info "Next steps:"
echo "  1. Configure AWS credentials:  aws configure"
echo "  2. Configure kubeconfig:       aws eks update-kubeconfig --name <cluster> --region <region>"
echo "  3. Add your user to docker:    usermod -aG docker \$USER && newgrp docker"
echo "  4. Run local stack:            ./scripts/build.sh compose-up"
echo "  5. Full pipeline:              ./scripts/build.sh all --env staging"
