# yunjitest_cicd

Minimal **Nginx** “Hello World / Hello K8s” demo plus a **Helm chart** and **GitHub Actions** CI.

Repository: [hellojamal/yunjitest_cicd](https://github.com/hellojamal/yunjitest_cicd)

## Layout

| Path | Purpose |
|------|---------|
| `app/` | Static page + `Dockerfile` (Nginx Alpine) |
| `helm/hellok8s/` | Helm chart (Deployment + Service) |
| `.github/workflows/ci.yml` | `validate` on GitHub-hosted; **`ship`** on **`arc-runners`** (or repo Variable **`SHIP_RUNS_ON`**): push to **GHCR + Harbor**, bump Helm chart, **Helm OCI push** (Argo pulls from Harbor) |
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
- **Push to `main`**: `ship` runs on **`arc-runners`** by default (override with Variable **`SHIP_RUNS_ON`**), pushes image to **GHCR** and **`192.168.10.121:30003/library/hellok8s`**, bumps **`helm/hellok8s`**, pushes **Helm OCI** to Harbor → **Argo CD** syncs **`cicd-system`** (chart `targetRevision: *`).

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

### Self-hosted runners（`ship` 的 `runs-on`）

**`ship` 默认**在 **`arc-runners`** 上执行（与集群里 **ARC AutoscalingRunnerSet** 的名称一致）。Runner 实际装在命名空间 **`cicd-runner`**；**Argo / Harbor** 在 **`cicd-system`**。

#### 在 GitHub 上改 `runs-on`（不改代码）

用的是 **Repository variables（仓库变量 / Actions 配置变量）**，不是 **Settings → Environments** 里的「Environment variables」，也不是 workflow 里 `env:` 给步骤用的那种 shell 环境变量。

- **`vars.SHIP_RUNS_ON`** 读的是：**Settings** → **Secrets and variables** → **Actions** → **Variables** 标签页里的 **Repository variables**（同一页也可管理 **Organization variables**，若组织下发了同名变量会按 GitHub 优先级合并）。  
- 当前 **`ship` job 没有写 `environment: xxx`**，因此 **不会**读取「部署环境」里单独配置的 Environment variables；若你坚持只用 Environment 变量，需要给 `ship` 加上 `environment: 你的环境名` 并在该环境下建同名变量（另需改文档与 workflow）。

**新建：** **Variables** → **New repository variable** → Name：`SHIP_RUNS_ON`，Value：Runner 标签（如 `arc-runners`）。  
**更新：** 同一列表里找到 **`SHIP_RUNS_ON`** → 右侧 **Update**（铅笔）→ 改 Value → **Save**。  
**恢复默认 `arc-runners`：** 在变量列表里对该变量执行 **Remove**（删除仓库变量）。删除后表达式里 `vars.SHIP_RUNS_ON` 为空，会使用默认 **`arc-runners`**。保存后 **下一次**触发的 workflow 生效。

#### 在集群里保证标签是 `arc-runners`

- 安装 **Actions Runner Controller（ARC）** 与 **Runner scale set** 时，**scale set 名称 / GitHub 里注册的 runner 标签** 要与 `SHIP_RUNS_ON` 或默认值一致。  
- 若你安装时用的名字是 **`my-runners`**，则要么把 GitHub Variable 设为 **`my-runners`**，要么把集群里 scale set 改成 **`arc-runners`**，或把工作流默认值改成你的名称。

#### 直接改仓库代码

编辑 **`.github/workflows/ci.yml`** 中 **`ship`** 的 **`runs-on:`** 行（例如改为 `runs-on: [self-hosted, linux, x64, my-label]` 多标签形式，需与 ARC 文档一致）。

Helm 校验 **`validate`** 仍使用 **`ubuntu-latest`**，不依赖自建 Runner。

### 全流程没跑起来：Harbor / Helm OCI / commit 全是 Skipped

工作流里这些步骤都带 **`if: vars.HARBOR_HELM_PUSH_ENABLED != 'false'`**。只要仓库（或组织）里 **Configuration variable** **`HARBOR_HELM_PUSH_ENABLED`** 的值是**字符串** **`false`**，就会只执行 **「Build and push image (GHCR only)」**，其余 Harbor、yq、bump chart、Helm OCI、git push **会全部跳过**——看起来像「CI 没生效」。

**处理：** **Settings** → **Secrets and variables** → **Actions** → **Variables** → 找到 **`HARBOR_HELM_PUSH_ENABLED`** → **Remove**；或改成 **`true`** / 任意非 `false` 的值。保存后重新 **push 到 `main`/`master`**（`ship` 仅在这些分支的 push 上运行）。

**确认：** 打开 **`ship`** 运行日志里的 **`Deployment mode (Harbor + Helm OCI)`** 步骤，会打印当前变量并给出 `notice`。

**其它：** **`SHIP_RUNS_ON`** 只决定跑在哪类 Runner 上，**不会**单独关掉 Harbor 步骤；关掉全流程的是 **`HARBOR_HELM_PUSH_ENABLED=false`**。

## External access（部署在 `cicd-system` 时）

| 方式 | URL / 命令 |
|------|------------|
| **域名（HTTPRoute + Envoy Gateway）** | `http://yunjitest-hello.yunjisoft.com/` — DNS 指向网关；或 `curl -H "Host: yunjitest-hello.yunjisoft.com" http://<节点IP>:31080/`（Envoy 常见 NodePort **31080**） |
| **NodePort（直连 IP）** | `http://<任意 Ready 节点内网IP>:30888/` — 由 Helm `Service` 暴露，**无需** `Host` 头 |

在 Gateway `yunji-gateway` 上需存在 listener **`yunjitest-hello-http`**，且 `hostname` 与 `httproute.hostname` 一致；若改域名，请同步 patch Gateway 或增加 listener。Helm 中可设置 `httproute.hostnames: ["a.example.com","b.example.com"]`（须与网关 listener 策略匹配）。

## License

MIT (or as you prefer — adjust if needed).
