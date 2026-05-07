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

#### Buildx 与 Docker socket（`failed to connect to docker API at unix:///var/run/docker.sock`）

K8s 里的 **ARC runner Pod** 往往**没有** **`/var/run/docker.sock`**。`ship` 会先 **自动选择 Buildx 驱动**：

1. **`SHIP_RUNS_ON=ubuntu-latest`** → **`docker-container`**（GitHub 托管机自带 Docker）。  
2. 否则若设置了仓库 Variable **`BUILDX_DRIVER`** → 使用该值（如 **`kubernetes`** / **`docker-container`**）。  
3. 否则若存在 **`/var/run/docker.sock`** → **`docker-container`**。  
4. 否则 → **`kubernetes`**（在集群内起 BuildKit，不依赖本机 Docker）。

**`driver=kubernetes` 时**：不再使用 **`docker/setup-buildx-action`** 创建 builder（该 action 会先连 **`docker.sock`**，在无 Docker 的 ARC Pod 里必挂）。工作流会改为下载官方 **`buildx`** 到 **`$HOME/bin/buildx`**，并在脚本内 **`export PATH`** 或使用 **`$HOME/bin/buildx`** 调用（**`GITHUB_PATH` 只影响后续 step**，同一 `run` 里不能直接当 PATH 用）。再用 **`buildx build --push`** 推镜像。有 **`docker.sock`** 时仍用 **`setup-buildx-action@v3`** + **`docker/build-push-action`**。

可选仓库 Variable **`BUILDX_K8S_NAMESPACE`**：覆盖 BuildKit 所在命名空间；**不填时默认为 `cicd-system`**（与 Argo 应用命名空间一致）。

**RBAC：** 模板见 **`deploy/k8s/arc-buildx-kubernetes-rbac.yaml`**。详见 [Buildx Kubernetes driver](https://docs.docker.com/build/builders/drivers/kubernetes/)。

#### 直接改仓库代码

编辑 **`.github/workflows/ci.yml`** 中 **`ship`** 的 **`runs-on:`** 行（例如改为 `runs-on: [self-hosted, linux, x64, my-label]` 多标签形式，需与 ARC 文档一致）。

Helm 校验 **`validate`** 仍使用 **`ubuntu-latest`**，不依赖自建 Runner。

### 全流程没跑起来：Harbor / Helm OCI / commit 全是 Skipped

**（历史）** 在合并本分支之前，GitHub 上曾使用单 job **`build-and-helm`**，且 Harbor 相关步骤的条件是 **`vars.HARBOR_HELM_PUSH_ENABLED == 'true'`**：变量**未设置**或不是精确小写 **`true`** 时，**所有** Harbor / Helm OCI 步骤都会跳过——这是多数人「改了配置仍不跑全流程」的原因。

当前 **`.github/workflows/ci.yml`** 使用 **`!= 'false'`**（默认走 Harbor 全流程，仅显式 **`false`** 时改为 GHCR-only）。只要仓库（或组织）里 **`HARBOR_HELM_PUSH_ENABLED`** 的值是**字符串** **`false`**，才会只跑 **「Build and push image (GHCR only)」** 并跳过其余步骤。

**处理：** **Settings** → **Secrets and variables** → **Actions** → **Variables** → 找到 **`HARBOR_HELM_PUSH_ENABLED`** → **Remove**；或改成 **`true`** / 任意非 `false` 的值。保存后重新 **push 到 `main`/`master`**，或在 **Actions → CI → Run workflow** 手动触发（`ship` 仅在 **push / workflow_dispatch** 且分支为 **`main`/`master`** 时运行）。

**确认：** 打开 **`ship`** 运行日志里的 **`Deployment mode (Harbor + Helm OCI)`** 步骤，会打印当前变量并给出 `notice`。

**其它：** **`SHIP_RUNS_ON`** 只决定跑在哪类 Runner 上，**不会**单独关掉 Harbor 步骤；关掉全流程的是 **`HARBOR_HELM_PUSH_ENABLED=false`**。

### 把本地改动同步到 GitHub（`hellojamal`）

自动化助手**不能使用你的 GitHub 密码**，也无法在未授权环境中替你 `git push`。要在你账号下 **push 后自动联动** Actions → Harbor → Argo，需要你在本机或 CI 里完成**一次性** Git 授权，任选其一：

1. **SSH（推荐）**  
   - 将本机公钥（如 `~/.ssh/id_ed25519.pub`）添加到 GitHub：**Settings → SSH and GPG keys → New SSH key**。  
   - 首次连接需信任主机：`ssh-keyscan github.com >> ~/.ssh/known_hosts`。  
   - 推送：`git remote set-url origin git@github.com:hellojamal/yunjitest_cicd.git` 然后 `git push origin main`。

2. **HTTPS + Personal Access Token**  
   - GitHub 创建 **fine-grained 或 classic PAT**，至少包含对该仓库的 **contents: write**、**workflows**（若改 workflow）、以及 **packages: write**（推 GHCR）。  
   - `git push` 时用户名填 **`hellojamal`**，密码填 **PAT**。

推送成功后：**push 到 `main`** 会触发 **`validate` → `ship`**；也可在仓库 **Actions** 页打开 **CI** 工作流，用 **Run workflow** 手动跑同一套流程（无需新 commit）。

## External access（部署在 `cicd-system` 时）

| 方式 | URL / 命令 |
|------|------------|
| **域名（HTTPRoute + Envoy Gateway）** | `http://yunjitest-hello.yunjisoft.com/` — DNS 指向网关；或 `curl -H "Host: yunjitest-hello.yunjisoft.com" http://<节点IP>:31080/`（Envoy 常见 NodePort **31080**） |
| **NodePort（直连 IP）** | `http://<任意 Ready 节点内网IP>:30888/` — 由 Helm `Service` 暴露，**无需** `Host` 头 |

在 Gateway `yunji-gateway` 上需存在 listener **`yunjitest-hello-http`**，且 `hostname` 与 `httproute.hostname` 一致；若改域名，请同步 patch Gateway 或增加 listener。Helm 中可设置 `httproute.hostnames: ["a.example.com","b.example.com"]`（须与网关 listener 策略匹配）。

## License

MIT (or as you prefer — adjust if needed).
