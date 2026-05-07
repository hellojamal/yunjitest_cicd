# yunjitest_cicd

Minimal **Nginx** “Hello World / Hello K8s” demo plus a **Helm chart** and **GitHub Actions** CI.

Repository: [hellojamal/yunjitest_cicd](https://github.com/hellojamal/yunjitest_cicd)

## Layout

| Path | Purpose |
|------|---------|
| `app/` | Static page + `Dockerfile` (Nginx Alpine) |
| `helm/hellok8s/` | Helm chart (Deployment + Service) |
| `.github/workflows/ci.yml` | `validate` on GitHub-hosted; **`ship` on `arc-runners`**: push to **GHCR + Harbor**, bump Helm chart, **Helm OCI push** (Argo pulls from Harbor) |
| `argocd/` | Argo `Application` targeting **`cicd-system`** |

## Local checks

```bash
helm lint ./helm/hellok8s
helm template demo ./helm/hellok8s
docker build -t hellok8s:dev ./app
```

## Install on Kubernetes (example)

Default image is **GHCR** (built by CI on `main`):

```bash
helm upgrade --install my-hello ./helm/hellok8s \
  --namespace default \
  --set image.repository=ghcr.io/hellojamal/yunjitest_cicd/hellok8s \
  --set image.tag=latest
kubectl port-forward svc/my-hello-hellok8s 8080:80
# open http://127.0.0.1:8080
```

Use your own registry by overriding `image.repository` / `image.tag`.

## CI / CD behaviour

- **Pull requests**: `helm lint`, render chart, **Docker build only** (no push).
- **Push to `main`**: `ship` on **`arc-runners`** pushes image to **GHCR** and **`192.168.10.121:30003/library/hellok8s`**, bumps **`helm/hellok8s`**, pushes **Helm OCI** to Harbor → **Argo CD** syncs **`cicd-system`** (chart `targetRevision: *`).

### Harbor + Argo prerequisites

1. **Repo Secrets** (Settings → Secrets and variables → Actions): `HARBOR_OCI_REGISTRY` (e.g. `192.168.10.121:30003`), `HARBOR_OCI_USERNAME`, `HARBOR_OCI_PASSWORD`.  
2. **Harbor push is ON by default.** Set repo Variable **`HARBOR_HELM_PUSH_ENABLED=false`** only if you want **GHCR-only** (no Harbor image / no Helm OCI / Argo will not see new chart versions from CI).  
3. **Self-signed Harbor TLS**: the workflow configures **Buildx** with `insecure = true` for `192.168.10.121:30003` so **docker push** succeeds. The Helm chart **defaults `image.repository` to GHCR** so pods schedule on every node; after **all** worker nodes have containerd `insecure_skip_verify` (and `systemctl restart containerd`), you may switch `helm/hellok8s/values.yaml` to `192.168.10.121:30003/library/hellok8s` for runtime pull from Harbor only.

On **nodes**, example (`/etc/containerd/config.toml` snippet):

```toml
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.10.121:30003".tls]
  insecure_skip_verify = true
```

4. If the Harbor **`library`** project is **private**, create a pull secret in `cicd-system` and set `imagePullSecrets` in `helm/hellok8s/values.yaml`.

### Self-hosted runners (ARC)

The workflow uses **`runs-on: arc-runners`** for the **ship** job (image build + optional Helm push to Harbor). The Actions Runner Controller scale set **`arc-runners`** lives in namespace **`cicd-runner`** (ARC controller + listener); **Argo CD** and **Harbor** run in **`cicd-system`**.

Helm validation still runs on **`ubuntu-latest`** so PRs do not require a free runner.

## External access（部署在 `cicd-system` 时）

| 方式 | URL / 命令 |
|------|------------|
| **域名（HTTPRoute + Envoy Gateway）** | `http://yunjitest-hello.yunjisoft.com/` — DNS 指向网关；或 `curl -H "Host: yunjitest-hello.yunjisoft.com" http://<节点IP>:31080/`（Envoy 常见 NodePort **31080**） |
| **NodePort（直连 IP）** | `http://<任意 Ready 节点内网IP>:30888/` — 由 Helm `Service` 暴露，**无需** `Host` 头 |

在 Gateway `yunji-gateway` 上需存在 listener **`yunjitest-hello-http`**，且 `hostname` 与 `httproute.hostname` 一致；若改域名，请同步 patch Gateway 或增加 listener。Helm 中可设置 `httproute.hostnames: ["a.example.com","b.example.com"]`（须与网关 listener 策略匹配）。

## License

MIT (or as you prefer — adjust if needed).
