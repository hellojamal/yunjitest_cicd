#!/usr/bin/env bash
# 在你已配置好 KUBECONFIG 的机器上运行，核对与本仓库约定一致的 CI/CD 组件。
# 用法: ./scripts/verify-cicd-cluster.sh
#      HARBOR_HOST=192.168.10.121:30003 ./scripts/verify-cicd-cluster.sh
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-192.168.10.121:30003}"

echo "== kubectl 集群连接 =="
kubectl cluster-info
echo

echo "== 命名空间（本仓库 README / 工作流约定）=="
echo "  - cicd-system : Argo Application 清单、Helm 部署的工作负载（见 argocd/application-hellok8s.yaml）"
echo "  - cicd-runner : ARC runner Pod（GitHub Actions 自建 Runner，非 GitHub 公司服务）"
echo "  - Harbor / Argo CD 控制器 : 常见为独立命名空间（如 harbor、argocd），以你集群实际为准"
echo

for ns in cicd-system cicd-runner; do
  if kubectl get ns "$ns" &>/dev/null; then
    echo "[OK] namespace $ns exists"
  else
    echo "[!!] namespace $ns MISSING (按需创建或检查 ARC/应用是否装在其他 ns)"
  fi
done
echo

echo "== cicd-system: Argo Application（本仓库 metadata.namespace: cicd-system）=="
if kubectl get ns cicd-system &>/dev/null; then
  kubectl get applications.argoproj.io -n cicd-system 2>/dev/null || kubectl get application -n cicd-system 2>/dev/null || echo "(无 applications.argoproj.io 或未安装 Argo CRD)"
  echo
  echo "-- Application yunjitest-hellok8s（若存在）--"
  kubectl get application.argoproj.io yunjitest-hellok8s -n cicd-system -o wide 2>/dev/null || true
  kubectl describe application.argoproj.io yunjitest-hellok8s -n cicd-system 2>/dev/null | tail -n 25 || true
  echo
  echo "== cicd-system: 与 Helm release 相关的 Deployment/Service（releaseName: yunjitest-hello）=="
  kubectl get deploy,svc -n cicd-system -l 'app.kubernetes.io/instance=yunjitest-hello' 2>/dev/null || kubectl get deploy,svc -n cicd-system | grep -E 'yunjitest|hellok8s' || kubectl get deploy,svc -n cicd-system
  echo
  echo "== cicd-system: HTTPRoute（若装 Gateway API）=="
  kubectl get httproute -n cicd-system 2>/dev/null || echo "(无 HTTPRoute CRD 或未创建)"
else
  echo "(跳过 cicd-system 内资源：命名空间不存在)"
fi
echo

echo "== cicd-runner: ARC / runner 相关 Pod（标签因安装方式而异，以下为常见查询）=="
if kubectl get ns cicd-runner &>/dev/null; then
  kubectl get pods -n cicd-runner -o wide 2>/dev/null || true
  kubectl get autoscalingrunnersets -n cicd-runner 2>/dev/null || kubectl get runner -n cicd-runner 2>/dev/null || true
else
  echo "(跳过：cicd-runner 不存在)"
fi
echo

echo "== Harbor 存活（仅 HTTP ping，需网络可达）=="
if curl -fsSL -m 8 -k "https://${HARBOR_HOST}/api/v2.0/ping" 2>/dev/null | head -c 80; then
  echo
  echo "[OK] Harbor ping"
else
  echo
  echo "[!!] 无法访问 https://${HARBOR_HOST}/api/v2.0/ping（从本机到 Harbor 网络/TLS 问题）"
fi
echo

echo "== 提示 =="
echo "1) GitHub（github.com）不在集群命名空间里；与集群联动的是 GitHub Actions + Webhook/Runner 注册。"
echo "2) 本仓库 Argo 源为 OCI: oci://${HARBOR_HOST}/library/hellok8s ，需 Harbor 项目 library 中已有 chart。"
echo "3) Buildx kubernetes 默认在 cicd-system 起 BuildKit；RBAC 见 deploy/k8s/arc-buildx-kubernetes-rbac.yaml"
echo "完成。"
