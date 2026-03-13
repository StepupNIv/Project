#!/usr/bin/env bash
# =============================================================================
#  DevOps Practice Project — Master Build Script
#  Usage: ./scripts/build.sh [COMMAND] [OPTIONS]
#
#  Commands:
#    all           Full build: deps → lint → test → docker → push → deploy
#    deps          Install Node.js dependencies
#    lint          Run ESLint
#    test          Run unit tests with coverage
#    docker-build  Build Docker image
#    docker-push   Push image to registry (ECR or DockerHub)
#    k8s-deploy    Apply all Kubernetes manifests
#    helm-deploy   Deploy via Helm
#    db-init       Initialize MySQL database
#    db-backup     Backup MySQL database to S3
#    rollback      Roll back Helm release
#    status        Show cluster/pod/service status
#    clean         Remove build artifacts and containers
#    help          Show this help
#
#  Options:
#    --env         Environment: dev | staging | prod  (default: dev)
#    --tag         Docker image tag                   (default: git SHA)
#    --namespace   Kubernetes namespace               (default: from env)
#    --dry-run     Print commands without running them
#    --skip-tests  Skip test stage
#    --skip-push   Build image but don't push
#    --verbose     Extra output
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m';  RESET='\033[0m'

log()     { echo -e "${BOLD}[$(date +%T)]${RESET} $*"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${RESET}"; }
error()   { echo -e "${RED}❌ $*${RESET}" >&2; exit 1; }
info()    { echo -e "${CYAN}ℹ️  $*${RESET}"; }
section() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }
run()     {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
  else
    [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${CYAN}▶ $*${RESET}"
    eval "$@"
  fi
}

# ── Script location ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
ENV="${ENV:-dev}"
GIT_SHA="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'no-git')"
BUILD_TS="$(date +%Y%m%d%H%M%S)"
IMAGE_TAG="${IMAGE_TAG:-${GIT_SHA}-${BUILD_TS}}"
SKIP_TESTS="${SKIP_TESTS:-false}"
SKIP_PUSH="${SKIP_PUSH:-false}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Registry — override via env vars
REGISTRY="${REGISTRY:-docker.io}"
REGISTRY_USER="${REGISTRY_USER:-youruser}"
APP_NAME="${APP_NAME:-devops-practice-app}"
FULL_IMAGE="${REGISTRY}/${REGISTRY_USER}/${APP_NAME}:${IMAGE_TAG}"
LATEST_IMAGE="${REGISTRY}/${REGISTRY_USER}/${APP_NAME}:latest"

# Kubernetes
case "${ENV}" in
  prod|production)   K8S_NS="production";  HELM_ENV="prod"  ;;
  staging|stage)     K8S_NS="staging";     HELM_ENV="staging" ;;
  *)                 K8S_NS="development";  HELM_ENV="dev"   ;;
esac
K8S_NS="${NAMESPACE:-${K8S_NS}}"
HELM_RELEASE="${HELM_RELEASE:-devops-app}"

# ── Parse CLI args ────────────────────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)        ENV="$2";             shift 2 ;;
    --tag)        IMAGE_TAG="$2";       shift 2 ;;
    --namespace)  K8S_NS="$2";          shift 2 ;;
    --dry-run)    DRY_RUN=true;         shift ;;
    --skip-tests) SKIP_TESTS=true;      shift ;;
    --skip-push)  SKIP_PUSH=true;       shift ;;
    --verbose)    VERBOSE=true;         shift ;;
    -h|--help)    COMMAND=help;         shift ;;
    *)            warn "Unknown option: $1"; shift ;;
  esac
done

# ── Prereq checks ─────────────────────────────────────────────────────────────
check_prereqs() {
  section "Checking Prerequisites"
  local missing=()
  for cmd in docker node npm kubectl helm git; do
    if command -v "$cmd" &>/dev/null; then
      success "$cmd $(${cmd} --version 2>&1 | head -1)"
    else
      warn "$cmd not found"
      missing+=("$cmd")
    fi
  done
  [[ ${#missing[@]} -gt 0 ]] && warn "Missing tools: ${missing[*]} — some stages may fail"
}

# ── Print build banner ────────────────────────────────────────────────────────
print_banner() {
  echo -e "${BOLD}${BLUE}"
  cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════╗
  ║        DevOps Practice Project — Build Script            ║
  ║   Jenkins · Docker · Kubernetes · ALB · MySQL · Helm     ║
  ╚═══════════════════════════════════════════════════════════╝
EOF
  echo -e "${RESET}"
  info "Command    : ${COMMAND}"
  info "Environment: ${ENV}  →  Namespace: ${K8S_NS}"
  info "Image      : ${FULL_IMAGE}"
  info "Git SHA    : ${GIT_SHA}"
  info "Skip Tests : ${SKIP_TESTS}"
  info "Dry Run    : ${DRY_RUN}"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  STAGES
# ─────────────────────────────────────────────────────────────────────────────

# ── 1. Install dependencies ───────────────────────────────────────────────────
stage_deps() {
  section "Install Node.js Dependencies"
  run "cd '${PROJECT_ROOT}/app' && npm ci"
  success "Dependencies installed"
}

# ── 2. Lint ───────────────────────────────────────────────────────────────────
stage_lint() {
  section "ESLint"
  run "cd '${PROJECT_ROOT}/app' && npm run lint || true"
  success "Lint complete"
}

# ── 3. Tests ──────────────────────────────────────────────────────────────────
stage_test() {
  if [[ "${SKIP_TESTS}" == "true" ]]; then
    warn "Tests SKIPPED (--skip-tests)"
    return 0
  fi
  section "Unit Tests"
  run "cd '${PROJECT_ROOT}/app' && npm test -- --ci --coverage"
  success "Tests passed"
}

# ── 4. Docker Build ───────────────────────────────────────────────────────────
stage_docker_build() {
  section "Docker Build"
  run "docker build \
    --build-arg SKIP_TESTS=${SKIP_TESTS} \
    --tag '${FULL_IMAGE}' \
    --tag '${LATEST_IMAGE}' \
    --label git-commit=${GIT_SHA} \
    --label build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --label env=${ENV} \
    --file '${PROJECT_ROOT}/app/Dockerfile' \
    '${PROJECT_ROOT}/app'"
  success "Docker image built: ${FULL_IMAGE}"
}

# ── 5. Security scan ──────────────────────────────────────────────────────────
stage_scan() {
  section "Security Scan (Trivy)"
  if command -v trivy &>/dev/null; then
    run "trivy image --severity HIGH,CRITICAL --no-progress '${FULL_IMAGE}' || true"
  else
    warn "Trivy not found — skipping vulnerability scan"
  fi
}

# ── 6. Docker Push ────────────────────────────────────────────────────────────
stage_docker_push() {
  if [[ "${SKIP_PUSH}" == "true" ]]; then
    warn "Push SKIPPED (--skip-push)"
    return 0
  fi
  section "Docker Push → ${REGISTRY}"

  # ECR login if using AWS
  if [[ "${REGISTRY}" == *"amazonaws.com"* ]]; then
    info "Logging into AWS ECR..."
    run "aws ecr get-login-password --region '${AWS_REGION:-us-east-1}' \
      | docker login --username AWS --password-stdin '${REGISTRY}'"
  fi

  run "docker push '${FULL_IMAGE}'"
  run "docker push '${LATEST_IMAGE}'"
  success "Pushed: ${FULL_IMAGE}"
}

# ── 7. Apply K8s Namespaces ───────────────────────────────────────────────────
stage_k8s_namespaces() {
  section "K8s — Apply Namespaces"
  run "kubectl apply -f '${PROJECT_ROOT}/k8s/namespaces/namespaces.yaml'"
  run "kubectl get namespaces"
  success "Namespaces applied"
}

# ── 8. Apply K8s Storage ──────────────────────────────────────────────────────
stage_k8s_storage() {
  section "K8s — Apply Storage"
  run "kubectl apply -f '${PROJECT_ROOT}/k8s/storage/storage.yaml'"
  success "Storage applied"
}

# ── 9. Apply K8s Base Manifests ───────────────────────────────────────────────
stage_k8s_base() {
  section "K8s — Apply Base Manifests"
  local base_dir="${PROJECT_ROOT}/k8s/base"
  for manifest in rbac configmap secrets mysql-statefulset deployment service hpa pdb network-policy; do
    local file="${base_dir}/${manifest}.yaml"
    if [[ -f "${file}" ]]; then
      run "kubectl apply -f '${file}' --namespace '${K8S_NS}'"
      success "Applied: ${manifest}.yaml"
    else
      warn "Not found: ${file}"
    fi
  done
}

# ── 10. Apply ALB Ingress ─────────────────────────────────────────────────────
stage_k8s_ingress() {
  section "K8s — Apply ALB Ingress"
  run "kubectl apply -f '${PROJECT_ROOT}/alb/ingress.yaml' --namespace '${K8S_NS}'"
  run "kubectl get ingress -n '${K8S_NS}'"
  success "Ingress applied"
}

# ── 11. Apply Monitoring ──────────────────────────────────────────────────────
stage_k8s_monitoring() {
  section "K8s — Apply Monitoring Stack"
  run "kubectl apply -f '${PROJECT_ROOT}/k8s/monitoring/monitoring.yaml'"
  success "Monitoring applied"
}

# ── 12. K8s Full Deploy ───────────────────────────────────────────────────────
stage_k8s_deploy() {
  stage_k8s_namespaces
  stage_k8s_storage
  stage_k8s_base
  stage_k8s_ingress
  stage_k8s_monitoring

  section "K8s — Update Image Tag"
  run "kubectl set image deployment/devops-app \
    app='${FULL_IMAGE}' \
    --namespace '${K8S_NS}'"

  section "K8s — Rollout Status"
  run "kubectl rollout status deployment/devops-app \
    --namespace '${K8S_NS}' --timeout=5m"
  success "K8s deployment complete"
}

# ── 13. Helm Deploy ───────────────────────────────────────────────────────────
stage_helm_deploy() {
  section "Helm Deploy → ${K8S_NS}"
  run "helm upgrade --install '${HELM_RELEASE}' '${PROJECT_ROOT}/helm' \
    --namespace '${K8S_NS}' \
    --create-namespace \
    --set image.repository='${REGISTRY}/${REGISTRY_USER}/${APP_NAME}' \
    --set image.tag='${IMAGE_TAG}' \
    --set env='${ENV}' \
    --values '${PROJECT_ROOT}/helm/values.yaml' \
    --wait --timeout 10m"
  run "helm status '${HELM_RELEASE}' --namespace '${K8S_NS}'"
  success "Helm deploy complete"
}

# ── 14. DB Init ───────────────────────────────────────────────────────────────
stage_db_init() {
  section "MySQL — Initialize Database"
  local mysql_pod
  mysql_pod=$(kubectl get pods -n database -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "${mysql_pod}" ]]; then
    warn "No MySQL pod found in 'database' namespace — using Docker Compose"
    run "docker-compose -f '${PROJECT_ROOT}/docker/docker-compose.yml' up -d mysql"
    sleep 15
    run "docker exec devops-mysql mysql -u root -prootpassword \
      < '${PROJECT_ROOT}/mysql/init/01-init.sql'"
  else
    info "MySQL pod: ${mysql_pod}"
    run "kubectl exec -n database '${mysql_pod}' -- \
      mysql -u root -prootpassword < '${PROJECT_ROOT}/mysql/init/01-init.sql'"
  fi
  success "Database initialized"
}

# ── 15. DB Backup ─────────────────────────────────────────────────────────────
stage_db_backup() {
  section "MySQL — Backup"
  local backup_file="backup_$(date +%Y%m%d_%H%M%S).sql.gz"
  local mysql_pod
  mysql_pod=$(kubectl get pods -n database -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "${mysql_pod}" ]]; then
    warn "No MySQL pod found — trying local Docker"
    run "docker exec devops-mysql mysqldump \
      -u appuser -papppassword devopsdb \
      | gzip > '${PROJECT_ROOT}/mysql/backup/${backup_file}'"
  else
    run "kubectl exec -n database '${mysql_pod}' -- \
      mysqldump -u appuser -papppassword --single-transaction devopsdb \
      | gzip > '${PROJECT_ROOT}/mysql/backup/${backup_file}'"
  fi

  if [[ -n "${S3_BUCKET:-}" ]]; then
    run "aws s3 cp '${PROJECT_ROOT}/mysql/backup/${backup_file}' \
      s3://${S3_BUCKET}/backups/${backup_file}"
    success "Uploaded to S3: s3://${S3_BUCKET}/backups/${backup_file}"
  fi
  success "Backup saved: ${backup_file}"
}

# ── 16. Rollback ──────────────────────────────────────────────────────────────
stage_rollback() {
  section "Helm Rollback"
  info "Current history:"
  run "helm history '${HELM_RELEASE}' --namespace '${K8S_NS}' --max 10"
  run "helm rollback '${HELM_RELEASE}' 0 --namespace '${K8S_NS}' --wait"
  success "Rollback complete"
}

# ── 17. Status ────────────────────────────────────────────────────────────────
stage_status() {
  section "Cluster Status"
  info "=== Nodes ==="
  run "kubectl get nodes -o wide 2>/dev/null || warn 'kubectl not configured'"

  info "=== Namespaces ==="
  run "kubectl get namespaces 2>/dev/null || true"

  info "=== Pods (${K8S_NS}) ==="
  run "kubectl get pods -n '${K8S_NS}' -o wide 2>/dev/null || true"

  info "=== Services (${K8S_NS}) ==="
  run "kubectl get services -n '${K8S_NS}' 2>/dev/null || true"

  info "=== Ingress (${K8S_NS}) ==="
  run "kubectl get ingress -n '${K8S_NS}' 2>/dev/null || true"

  info "=== HPA (${K8S_NS}) ==="
  run "kubectl get hpa -n '${K8S_NS}' 2>/dev/null || true"

  info "=== Helm Releases ==="
  run "helm list --all-namespaces 2>/dev/null || true"

  info "=== Docker Images ==="
  run "docker images | grep '${APP_NAME}' || true"
}

# ── 18. Clean ─────────────────────────────────────────────────────────────────
stage_clean() {
  section "Clean Build Artifacts"
  run "rm -rf '${PROJECT_ROOT}/app/node_modules' '${PROJECT_ROOT}/app/coverage'"
  run "docker rmi '${FULL_IMAGE}' '${LATEST_IMAGE}' 2>/dev/null || true"
  run "docker system prune -f"
  success "Clean complete"
}

# ── 19. Local dev via Docker Compose ─────────────────────────────────────────
stage_compose_up() {
  section "Docker Compose — Start Local Stack"
  run "docker-compose -f '${PROJECT_ROOT}/docker/docker-compose.yml' up -d --build"
  info "Services started. Waiting for health checks..."
  sleep 10
  run "docker-compose -f '${PROJECT_ROOT}/docker/docker-compose.yml' ps"
  success "Local stack running:"
  info "  App:     http://localhost:3000"
  info "  NGINX:   http://localhost:80"
  info "  Adminer: http://localhost:8080"
}

stage_compose_down() {
  section "Docker Compose — Stop Local Stack"
  run "docker-compose -f '${PROJECT_ROOT}/docker/docker-compose.yml' down -v"
  success "Stack stopped"
}

# ── HELP ──────────────────────────────────────────────────────────────────────
show_help() {
  echo -e "${BOLD}${BLUE}DevOps Practice Build Script${RESET}"
  echo ""
  echo -e "${BOLD}Usage:${RESET}  ./scripts/build.sh <command> [options]"
  echo ""
  echo -e "${BOLD}Commands:${RESET}"
  printf "  %-20s %s\n" "all"           "Full pipeline: deps→lint→test→docker→push→deploy"
  printf "  %-20s %s\n" "deps"          "Install Node.js dependencies"
  printf "  %-20s %s\n" "lint"          "Run ESLint"
  printf "  %-20s %s\n" "test"          "Run unit tests with coverage"
  printf "  %-20s %s\n" "docker-build"  "Build Docker image"
  printf "  %-20s %s\n" "docker-push"   "Push Docker image to registry"
  printf "  %-20s %s\n" "k8s-deploy"    "Apply all K8s manifests + update image"
  printf "  %-20s %s\n" "helm-deploy"   "Deploy via Helm chart"
  printf "  %-20s %s\n" "db-init"       "Initialize MySQL database"
  printf "  %-20s %s\n" "db-backup"     "Backup MySQL to file (+ S3 if configured)"
  printf "  %-20s %s\n" "rollback"      "Roll back Helm release to previous version"
  printf "  %-20s %s\n" "status"        "Show pods, services, ingress, Helm status"
  printf "  %-20s %s\n" "compose-up"    "Start local dev stack via Docker Compose"
  printf "  %-20s %s\n" "compose-down"  "Stop local dev stack"
  printf "  %-20s %s\n" "clean"         "Remove artifacts and Docker images"
  printf "  %-20s %s\n" "help"          "Show this help message"
  echo ""
  echo -e "${BOLD}Options:${RESET}"
  printf "  %-22s %s\n" "--env <dev|staging|prod>"  "Target environment  (default: dev)"
  printf "  %-22s %s\n" "--tag <tag>"               "Override image tag  (default: git-sha-ts)"
  printf "  %-22s %s\n" "--namespace <ns>"          "Override K8s namespace"
  printf "  %-22s %s\n" "--dry-run"                 "Print commands without executing"
  printf "  %-22s %s\n" "--skip-tests"              "Skip unit test stage"
  printf "  %-22s %s\n" "--skip-push"               "Build image but don't push"
  printf "  %-22s %s\n" "--verbose"                 "Extra command output"
  echo ""
  echo -e "${BOLD}Environment Variables:${RESET}"
  printf "  %-22s %s\n" "REGISTRY"        "Docker registry (default: docker.io)"
  printf "  %-22s %s\n" "REGISTRY_USER"   "Registry username"
  printf "  %-22s %s\n" "APP_NAME"        "Application name (default: devops-practice-app)"
  printf "  %-22s %s\n" "IMAGE_TAG"       "Override image tag"
  printf "  %-22s %s\n" "S3_BUCKET"       "S3 bucket for DB backups"
  printf "  %-22s %s\n" "AWS_REGION"      "AWS region (default: us-east-1)"
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo "  ./scripts/build.sh all --env staging"
  echo "  ./scripts/build.sh docker-build --tag v1.2.3 --skip-tests"
  echo "  ./scripts/build.sh helm-deploy --env prod --namespace production"
  echo "  ./scripts/build.sh db-backup"
  echo "  ./scripts/build.sh status --env prod"
  echo "  ./scripts/build.sh compose-up"
  echo "  REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com \\"
  echo "    ./scripts/build.sh all --env prod --skip-tests"
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN — Route to command
# ─────────────────────────────────────────────────────────────────────────────
main() {
  print_banner

  case "${COMMAND}" in
    all)
      check_prereqs
      stage_deps
      stage_lint
      stage_test
      stage_docker_build
      stage_scan
      stage_docker_push
      stage_helm_deploy
      stage_status
      ;;
    deps)          stage_deps ;;
    lint)          stage_lint ;;
    test)          stage_test ;;
    docker-build)  stage_docker_build ;;
    docker-push)   stage_docker_push ;;
    k8s-deploy)    stage_k8s_deploy ;;
    helm-deploy)   stage_helm_deploy ;;
    db-init)       stage_db_init ;;
    db-backup)     stage_db_backup ;;
    rollback)      stage_rollback ;;
    status)        stage_status ;;
    compose-up)    stage_compose_up ;;
    compose-down)  stage_compose_down ;;
    clean)         stage_clean ;;
    help|-h|--help) show_help ;;
    *)
      error "Unknown command: '${COMMAND}'. Run './scripts/build.sh help' for usage."
      ;;
  esac

  echo ""
  success "Done! Command '${COMMAND}' completed successfully."
}

main
