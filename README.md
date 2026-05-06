# yunjitest_cicd

Minimal **Nginx** “Hello World / Hello K8s” demo plus a **Helm chart** and **GitHub Actions** CI.

Repository: [hellojamal/yunjitest_cicd](https://github.com/hellojamal/yunjitest_cicd)

## Layout

| Path | Purpose |
|------|---------|
| `app/` | Static page + `Dockerfile` (Nginx Alpine) |
| `helm/hellok8s/` | Helm chart (Deployment + Service) |
| `.github/workflows/ci.yml` | CI: `helm lint`, build image; on `main` push also **push to GHCR** |

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

## CI behaviour

- **Pull requests**: `helm lint`, render chart, **Docker build only** (no push).
- **Push to `main`**: same checks, then **build + push** to  
  `ghcr.io/hellojamal/yunjitest_cicd/hellok8s:latest` and `:SHA`.

### Self-hosted runners (ARC)

The workflow uses **`runs-on: arc-runners`** for the **ship** job (image build + optional Helm push to Harbor). The Actions Runner Controller scale set **`arc-runners`** lives in namespace **`cicd-runner`** (ARC controller + listener); **Argo CD** and **Harbor** run in **`cicd-system`**.

Helm validation still runs on **`ubuntu-latest`** so PRs do not require a free runner.

## License

MIT (or as you prefer — adjust if needed).
