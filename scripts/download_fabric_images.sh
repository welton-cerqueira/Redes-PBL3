#!/bin/bash

echo "🐳 Baixando imagens Docker do Hyperledger Fabric..."

# Define versões
FABRIC_VERSION="2.5.0"
CA_VERSION="1.5.7"

# Lista de imagens necessárias
IMAGES=(
    "hyperledger/fabric-orderer:${FABRIC_VERSION}"
    "hyperledger/fabric-peer:${FABRIC_VERSION}"
    "hyperledger/fabric-tools:${FABRIC_VERSION}"
    "hyperledger/fabric-ca:${CA_VERSION}"
    "hyperledger/fabric-ccenv:${FABRIC_VERSION}"
    "hyperledger/fabric-baseos:2.5.0"
)

for image in "${IMAGES[@]}"; do
    echo "Baixando $image..."
    docker pull "$image"
done

# Imagem para testes (opcional)
docker pull hyperledger/fabric-sample-cc:latest

echo "✅ Imagens Docker baixadas com sucesso!"

# Verifica imagens
echo ""
echo "📋 Imagens disponíveis:"
docker images | grep hyperledger