# 投标报价计算器

投标报价模拟计算工具，纯前端静态应用（HTML + TailwindCSS + Alpine.js），由 nginx 托管。

## 目录结构（静态文件单一来源）

```
frontend-user/
├── public/                 # 静态源文件（唯一来源，本地开发与容器构建共用）
│   ├── index.html
│   ├── css/
│   └── js/
├── dist/                   # 构建产物（git 忽略），布局与容器内 web root 完全一致
│   ├── index.html          #   构建期注入 VERSION / BUILD_TIME
│   ├── css/ js/
│   ├── vendor/             #   构建期固化的第三方依赖（Tailwind/Alpine，带 SHA256 校验）
│   └── version.json
├── dependencies.txt        # 第三方依赖清单（URL + 版本 + SHA256）
├── scripts/
│   ├── build.sh            # 统一构建脚本（本机与 Dockerfile 内都调用它）
│   └── fetch-deps.sh       # 依赖拉取（超时/重试/哈希校验/内容寻址缓存）
├── docker/
│   ├── nginx.conf          # 本机与容器共用的站点配置
│   └── nginx-includes/
└── Dockerfile              # 多阶段构建，基础镜像按多架构 digest 固定
scripts/build-image.sh      # 镜像构建封装（单架构 / ARM64+X86_64 跨平台）
docker-compose.yml          # 生产/交付
docker-compose.dev.yml      # 本机开发 override（bind mount 同一份 dist）
Makefile                    # 统一入口
```

## 快速开始

```bash
# 本机开发：与生产同一个 nginx 镜像、同一份配置、同一 8082 端口
make dev-build          # 本机执行 build.sh 产出 dist/
make dev                # 启动后访问 http://localhost:8082

# 生产方式构建并启动
make up                 # 自动推导 VERSION（git）与 BUILD_TIME（UTC）
# 或显式指定（复现同一镜像时必须传入相同值）
make up VERSION=1.0.0 BUILD_TIME=2026-09-21T08:00:00Z

make down
```

> 直接执行 `docker compose up --build` 而不提供 `VERSION/BUILD_TIME` 会立即报错停止；
> 请始终通过 `make` 目标或 `scripts/build-image.sh` 调用。

## 构建参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `VERSION` | 是 | 版本号，如 `1.0.0`；缺失时构建立即失败并给出明确提示 |
| `BUILD_TIME` | 是 | 构建时间，UTC RFC3339（`YYYY-MM-DDThh:mm:ssZ`） |
| `REVISION` | 否 | 源码版本标识（git sha），默认 `unknown` |

版本与构建时间注入三处，重启容器不变化：

- 页面页脚：`版本 x.y.z · 构建于 ...`
- `GET /version.json`：`{name, version, revision, buildTime}`
- 镜像 OCI labels：`org.opencontainers.image.version/created/revision`

## 跨平台镜像（ARM64 / X86_64）

基础镜像固定为 `nginx:alpine` 的多架构 OCI index digest
（`sha256:62ff2089...`，nginx 1.31.6），两架构拉到的内容确定一致。

```bash
# 需要先 docker login 到目标仓库（多架构清单无法 load 到本机，必须推送）
make image-multi REGISTRY=registry.example.com/app VERSION=1.0.0
# 等价：
scripts/build-image.sh --platforms linux/arm64,linux/amd64 --push \
  --tag registry.example.com/app/bid-calculator-frontend:1.0.0

# 仅本机当前架构
make image VERSION=1.0.0
```

可重复构建：相同源码 + 相同 `VERSION/BUILD_TIME` + 固定的基础镜像 digest
→ 相同的镜像内容。依赖下载结果按 SHA256 内容寻址缓存（本机 `frontend-user/.cache`，
Docker 内 BuildKit cache mount），不会因重跑而改变产物。

## 依赖拉取与故障行为

- 第三方依赖在**构建期**下载、SHA256 校验后固化到 `dist/vendor/`；
  页面运行时不访问任何外网 CDN（断网环境与容器内行为一致）。
- 拉取超时（默认 30s）自动重试（默认 3 次），耗尽后明确报错并停止构建：
  可通过 `FETCH_TIMEOUT` / `FETCH_RETRIES` 调整。
- 哈希不符立即失败，不会把错误内容写入产物或缓存。

## 运行约定（本机与容器一致）

| 项目 | 值 |
|------|------|
| 端口 | 宿主机 `8082` → 容器 `80` |
| 启动 | 官方 entrypoint + `nginx -g 'daemon off;'`（不覆盖） |
| 健康检查 | `GET /healthz`（compose 与 Dockerfile HEALTHCHECK 一致） |
| 版本信息 | `GET /version.json` |
| 根文件系统 | 只读；可写目录 `/tmp`、`/run`、`/var/cache/nginx` 均为 tmpfs，无状态卷 |
| 重启策略 | `unless-stopped`；重启后版本、页面行为完全一致 |

## 测试账号

无需登录，纯前端静态应用。

## 题目内容

> 新建一个 html 应用，用于模拟计算投标报价计算，支持单低和双低模式，比例、限价及分数都可以自定义，且可以任意添加多家报价。并计算显示报价是否有效和报价得分。
