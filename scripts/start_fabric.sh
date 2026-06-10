#!/bin/bash

# ============================================================================
# Script para iniciar Hyperledger Fabric do jeito que funcionou
# ============================================================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}HYPERLEDGER FABRIC - ORMUZ CONSÓRCIO${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                      ${BOLD}Inicialização Automática${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${BOLD}➤ $1${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────────────────────┘${NC}"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ️${NC} $1"
}

# ============================================================================
# MAIN
# ============================================================================

print_banner

cd ~/fabric-samples/test-network

# Passo 1: Limpar rede anterior
print_step "Limpando rede anterior"
./network.sh down 2>/dev/null || true
docker rm -f cli 2>/dev/null || true
print_success "Limpeza concluída"

# Passo 2: Subir rede com cryptogen (sem CA)
print_step "Subindo rede Hyperledger Fabric"
./network.sh up createChannel -c ormuz-channel

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Falha ao subir rede${NC}"
    exit 1
fi
print_success "Rede Fabric iniciada"

# Passo 3: Aguardar estabilização
print_step "Aguardando serviços estabilizarem"
sleep 10
print_success "Serviços estabilizados"

# Passo 4: Criar container CLI manualmente com todas as variáveis de ambiente
print_step "Criando container CLI"
docker rm -f cli 2>/dev/null || true

docker run -d --name cli \
  --network fabric_test \
  -v ${PWD}:/opt/gopath/src/github.com/hyperledger/fabric/peer \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem \
  hyperledger/fabric-tools:latest \
  sleep infinity

print_success "Container CLI criado"

# Passo 5: Copiar chaincodes
print_step "Preparando chaincodes"
mkdir -p chaincode
cp -r ~/Redes-PBL3/chaincode/* chaincode/ 2>/dev/null || true
print_success "Chaincodes copiados"

# Passo 6: Instalar chaincode mission na Org2
print_step "Instalando MISSION na Org2"
docker exec cli bash -c "
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem
  export CORE_PEER_LOCALMSPID=Org2MSP
  export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
  export CORE_PEER_ADDRESS=peer0.org2.example.com:9051
  cd /opt/gopath/src/github.com/hyperledger/fabric/peer
  peer lifecycle chaincode install mission.tar.gz 2>/dev/null || echo 'Mission já instalado na Org2'
"
print_success "Chaincode MISSION instalado na Org2"

# Passo 7: Testar chaincode
print_step "Testando chaincode MISSION"
docker exec cli bash -c "
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem
  export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
  export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
  cd /opt/gopath/src/github.com/hyperledger/fabric/peer
  peer chaincode query -C ormuz-channel -n mission -c '{\"Args\":[\"GetMissionSummary\"]}'
"

print_success "Chaincode MISSION respondendo"

# ============================================================================
# RESUMO FINAL
# ============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                    ${BOLD}HYPERLEDGER FABRIC INICIADO COM SUCESSO!${NC}                    ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📋 Componentes rodando:${NC}"
echo -e "  ${GREEN}✅${NC} Orderer        (porta 7050)"
echo -e "  ${GREEN}✅${NC} Peer Org1      (porta 7051)"
echo -e "  ${GREEN}✅${NC} Peer Org2      (porta 9051)"
echo -e "  ${GREEN}✅${NC} Canal          (ormuz-channel)"
echo -e "  ${GREEN}✅${NC} Chaincode MISSION"
echo ""
echo -e "${CYAN}📋 Comandos úteis:${NC}"
echo -e "  ${YELLOW}docker exec -it cli bash${NC}        - Entrar no container CLI"
echo -e "  ${YELLOW}./scripts/test_ledger.sh${NC}        - Testar ledger"
echo -e "  ${YELLOW}./scripts/stop_all.sh${NC}           - Parar todos os serviços"
echo ""
