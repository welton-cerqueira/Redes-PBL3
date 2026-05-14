#!/bin/bash
echo "# ESTRUTURA DO PROJETO"
echo "\`\`\`"
tree -L 3 --dirsfirst
echo "\`\`\`"
echo ""
echo "# CONTEÚDO DOS ARQUIVOS"
echo ""

find . -type f \( \
    -name "*.go" -o \
    -name "*.mod" -o \
    -name "*.sum" -o \
    -name "*.sh" -o \
    -name "Dockerfile*" -o \
    -name "*.md" -o \
    -name "*.yaml" -o \
    -name "*.yml" -o \
    -name "*.json" \
    ! -path "*/\.*" \
\) | sort | while read file; do
    echo "## \`$file\`"
    echo "\`\`\`$(echo $file | grep -o '\.[^.]*$' | sed 's/\.//')"
    cat "$file"
    echo "\`\`\`"
    echo ""
done
