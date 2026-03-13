# ⚡ DevOps Practice Project

> Full-stack DevOps project: **Node.js + MySQL** app deployed via **Jenkins CI/CD → Docker → Kubernetes (EKS) → AWS ALB** with Helm, Prometheus/Grafana monitoring, and automated backups.

---

## 📁 Project Structure

```
devops-project/
├── app/                        # Node.js Express application
│   ├── src/index.js            # Main app (REST API + health checks)
│   ├── public/index.html       # Frontend dashboard
│   ├── package.json
│   └── Dockerfile              # Multi-stage production image
│
├── docker/
│   └── docker-compose.yml      # Local dev: app + mysql + nginx + adminer
│
├── jenkins/
│   ├── Jenkinsfile             # Main CI/CD pipeline
│   ├── pipelines/
│   │   ├── Jenkinsfile.backup  # MySQL backup pipeline (cron)
│   │   └── Jenkinsfile.rollback # Manual rollback pipeline
│
├── k8s/
│   ├── namespaces/             # Namespace definitions
│   ├── base/                   # Core manifests
│   │   ├── configmap.yaml
│   │   ├── secrets.yaml
│   │   ├── deployment.yaml     # 3-replica deployment + probes + security
│   │   ├── service.yaml        # ClusterIP + NodePort services
│   │   ├── mysql-statefulset.yaml  # MySQL StatefulSet + headless service
│   │   ├── hpa.yaml            # Horizontal Pod Autoscaler
│   │   ├── pdb.yaml            # PodDisruptionBudget
│   │   ├── rbac.yaml           # ServiceAccount + Role + RoleBinding
│   │   └── network-policy.yaml # Network isolation policies
│   ├── storage/                # StorageClass + PVC
│   └── monitoring/             # Prometheus + Grafana
│
├── alb/
│   └── ingress.yaml            # AWS ALB Ingress with full annotations
│
├── helm/                       # Helm chart (wraps all K8s resources)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       └── service-ingress.yaml
│
├── mysql/
│   ├── init/01-init.sql        # DB init script
│   └── mysql.cnf               # MySQL tuning config
│
├── nginx/
│   └── nginx.conf              # Reverse proxy config
│
└── scripts/
    ├── build.sh                # 🔧 Master build script (all-in-one)
    └── setup.sh                # 🛠️ Tool installer (Docker, kubectl, Helm, AWS CLI...)
```

---

## 🚀 Quick Start

### 1. Install all tools (fresh machine)
```bash
sudo ./scripts/setup.sh
```

### 2. Run locally with Docker Compose
```bash
./scripts/build.sh compose-up
# App:     http://localhost:3000
# Nginx:   http://localhost:80
# Adminer: http://localhost:8080
```

### 3. Full pipeline (build → test → docker → push → deploy)
```bash
# Set your registry details
export REGISTRY=docker.io
export REGISTRY_USER=youruser

./scripts/build.sh all --env staging
```

---

## 🔧 Build Script Reference

```bash
./scripts/build.sh <command> [options]

Commands:
  all             Full pipeline: deps→lint→test→docker→push→deploy
  deps            Install Node.js dependencies
  lint            Run ESLint
  test            Run unit tests with coverage
  docker-build    Build Docker image
  docker-push     Push to registry (ECR or DockerHub)
  k8s-deploy      Apply all K8s manifests
  helm-deploy     Deploy via Helm
  db-init         Initialize MySQL database
  db-backup       Backup MySQL → S3
  rollback        Roll back Helm release
  status          Show pods/services/ingress/Helm status
  compose-up      Start local Docker Compose stack
  compose-down    Stop local Docker Compose stack
  clean           Remove artifacts and images
  help            Show full help

Options:
  --env dev|staging|prod    Target environment
  --tag <tag>               Override image tag
  --namespace <ns>          Override K8s namespace
  --dry-run                 Print commands, don't execute
  --skip-tests              Skip unit tests
  --skip-push               Build image but don't push
  --verbose                 Extra output
```

---

## 🏗️ Infrastructure Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| App | Node.js + Express | REST API + frontend |
| Database | MySQL 8 (StatefulSet) | Persistent data store |
| Container | Docker (multi-stage) | Immutable images |
| Registry | AWS ECR / DockerHub | Image storage |
| Orchestration | Kubernetes (EKS) | Container management |
| Load Balancer | AWS ALB | Ingress + SSL termination |
| CI/CD | Jenkins | Build, test, deploy |
| Packaging | Helm 3 | K8s release management |
| Monitoring | Prometheus + Grafana | Metrics + dashboards |
| Proxy | NGINX | Reverse proxy (local) |

---

## ☸️ Kubernetes Components

- **Deployment** — 3 replicas, rolling update, init container (wait-for-DB)
- **StatefulSet** — MySQL with persistent volume (gp2, 20Gi)
- **Service** — ClusterIP (app) + headless (MySQL)
- **Ingress** — AWS ALB with SSL, health checks, WAF-ready
- **HPA** — Autoscale 2–10 pods on CPU/memory
- **PDB** — Minimum 2 app pods, 1 MySQL pod available during disruptions
- **ConfigMap / Secret** — Environment config and credentials
- **RBAC** — Least-privilege ServiceAccounts for app and Jenkins
- **NetworkPolicy** — MySQL only accessible from production namespace
- **StorageClass** — AWS EBS gp2 with encryption
- **Namespaces** — production, staging, database, monitoring, ingress-nginx

---

## 🔄 Jenkins Pipelines

| Pipeline | File | Trigger |
|----------|------|---------|
| Main CI/CD | `jenkins/Jenkinsfile` | Git push (all branches) |
| MySQL Backup | `jenkins/pipelines/Jenkinsfile.backup` | Cron: daily 02:00 UTC |
| Rollback | `jenkins/pipelines/Jenkinsfile.rollback` | Manual (parameterized) |

---

## 🌐 API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Frontend dashboard |
| GET | `/health` | Health check (liveness probe) |
| GET | `/ready` | Readiness probe |
| GET | `/metrics` | Prometheus metrics |
| GET | `/api/v1/users` | List users |
| POST | `/api/v1/users` | Create user |
| GET | `/api/v1/users/:id` | Get user by ID |
| DELETE | `/api/v1/users/:id` | Delete user |
