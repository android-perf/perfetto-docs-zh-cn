#!/bin/bash
REPO_NAME="perfetto-docs-zh-cn"

# 修复 index.html
echo "修复 index.html..."
sed -i '' "s|href=\"/assets/|href=\"/$REPO_NAME/assets/|g" index.html
sed -i '' "s|src=\"/assets/|src=\"/$REPO_NAME/assets/|g" index.html
sed -i '' "s|href=\"/docs/|href=\"/$REPO_NAME/docs/|g" index.html
sed -i '' "s|src=\"/docs/|src=\"/$REPO_NAME/docs/|g" index.html
sed -i '' "s|data=\"/docs/|data=\"/$REPO_NAME/docs/|g" index.html
sed -i '' "s|href=\"/\"|href=\"/$REPO_NAME/\"|g" index.html

# 修复 docs/*.html
echo "修复 docs/*.html..."
for file in $(find docs -name "*.html"); do
    sed -i '' "s|href=\"/assets/|href=\"/$REPO_NAME/assets/|g" "$file"
    sed -i '' "s|src=\"/assets/|src=\"/$REPO_NAME/assets/|g" "$file"
    sed -i '' "s|href=\"/docs/|href=\"/$REPO_NAME/docs/|g" "$file"
    sed -i '' "s|src=\"/docs/|src=\"/$REPO_NAME/docs/|g" "$file"
    sed -i '' "s|data=\"/docs/|data=\"/$REPO_NAME/docs/|g" "$file"
    sed -i '' "s|href=\"/\"|href=\"/$REPO_NAME/\"|g" "$file"
done

# 修复 assets
echo "修复 assets..."
sed -i '' "s|\"\/assets\/mermaid.min.js\"|\"\/$REPO_NAME\/assets\/mermaid.min.js\"|g" assets/script.js
sed -i '' "s|\"\/assets\/sprite.png\"|\"\/$REPO_NAME\/assets\/sprite.png\"|g" assets/style.css

# 添加 .html 扩展名
echo "添加 .html 扩展名..."
for file in docs/*; do
    if [ -f "$file" ] && [[ ! "$file" =~ \. ]]; then
        mv "$file" "$file.html"
        echo "  重命名: $(basename "$file")"
    fi
done
find docs -type f ! -name "*.png" ! -name "*.jpg" ! -name "*.gif" ! -name "*.svg" ! -name "*.ico" ! -name "*.html" -exec sh -c 'mv "$1" "$1.html"' _ {} \; 2>/dev/null || true

# 为链接添加 .html 后缀
echo "为链接添加 .html 后缀..."
find . -name "*.html" ! -path "./.git/*" -exec sed -i '' "s|href=\"\/$REPO_NAME\/docs\/\([^\"]*\)\"|href=\"\/$REPO_NAME\/docs\/\1.html\"|g" {} \;

# 修复错误链接
find . -name "*.html" ! -path "./.git/*" -exec sed -i '' "s|href=\"\/$REPO_NAME\/docs\/.html\"|href=\"\/$REPO_NAME\/docs\/\"|g" {} \;

echo "修复完成！"
