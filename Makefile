# 本地与 GitHub Actions「validate」对齐的检查（helm + docker build）
.PHONY: ci-local helm-check docker-smoke
SHELL := /bin/bash

helm-check:
	@command -v helm >/dev/null || { echo "请安装 Helm: https://helm.sh"; exit 1; }
	helm lint ./helm/hellok8s
	helm template demo ./helm/hellok8s --set image.tag=local >/dev/null
	@echo "[OK] helm lint + template"

docker-smoke:
	@if ! command -v docker >/dev/null 2>&1; then \
	  echo "[WARN] 未安装 docker，跳过镜像构建"; \
	elif ! docker info >/dev/null 2>&1; then \
	  echo "[WARN] docker 无权限或未启动，跳过镜像构建（可将用户加入 docker 组或启动 Docker）"; \
	else \
	  docker build -t hellok8s:local ./app && echo "[OK] docker build"; \
	fi

ci-local: helm-check docker-smoke
	@echo "[OK] ci-local — 可 git commit / push；云端 ship 仍需 Secrets、Runner、Harbor、Argo。"
