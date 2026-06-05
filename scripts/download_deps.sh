#!/bin/bash

echo "📦 Baixando dependências do projeto principal..."
cd ../  # Volta para a raiz do projeto
go mod tidy
go mod download

echo "📦 Baixando dependências do chaincode..."
cd chaincode
go mod init chaincode 2>/dev/null || true
go mod tidy
go mod download

echo "✅ Dependências instaladas com sucesso!"