# Empty 官网

静态落地页，部署到 Cloudflare Pages。

## 本地预览

```bash
cd website
python3 -m http.server 8787
# open http://localhost:8787
```

## 更新下载链接

编辑 `main.js` 中的 `DOWNLOADS`：

| 键 | 用途 |
|----|------|
| `mac` | Mac 版下载（默认 GitHub Releases） |
| `appStore` | App Store 正式版链接 |
| `testFlight` | TestFlight 内测邀请链接 |

## 部署

```bash
wrangler pages deploy . --project-name=empty --branch=main
```

部署后生产域名：`https://empty-78c.pages.dev`（可在 Cloudflare 控制台绑定自定义域，例如 `empty.davirain.xyz`）。