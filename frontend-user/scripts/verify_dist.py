#!/usr/bin/env python3
"""校验 dist/index.html 中所有同源 /assets 引用在产物目录中真实存在。

容器内 web 根 /app 与本地 dist/ 结构一致：
  HTML 里的 /assets/js/app.js  →  dist/assets/js/app.js  →  容器 /app/assets/js/app.js
"""
import pathlib
import re
import sys

DIST = pathlib.Path(__file__).resolve().parent.parent / "dist"
HTML = DIST / "index.html"

# 匹配 src="/assets/.." 与 href="/assets/.."
REF_RE = re.compile(r"""(?:src|href)=["'](/assets/[^"']+)["']""")


def main() -> int:
    if not HTML.is_file():
        print("ERROR: dist/index.html 不存在，请先执行 make build-local")
        return 1

    html = HTML.read_text(encoding="utf-8")
    refs = sorted(set(REF_RE.findall(html)))
    if not refs:
        print("ERROR: index.html 中未找到任何 /assets 引用")
        return 1

    failed = False
    for ref in refs:
        target = DIST / ref.lstrip("/")
        if target.is_file():
            print(f"  OK   {ref}")
        else:
            print(f"  MISS {ref} （期望文件 {target}）")
            failed = True

    # 版本注入检查：模板占位符不允许残留
    for placeholder in ("@@APP_VERSION@@", "@@BUILD_TIME@@"):
        if placeholder in html:
            print(f"  MISS 模板占位符未被替换: {placeholder}")
            failed = True

    if failed:
        print("ERROR: 产物路径校验失败：HTML 引用与目录结构不一致")
        return 1

    print(f"==> {len(refs)} 个同源资源引用全部存在，版本占位符已注入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
