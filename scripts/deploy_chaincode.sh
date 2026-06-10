#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== Deploy Simplificado dos Chaincodes ==="

docker exec -it cli bash -c "
set -e

export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.ormuz.com/users/Admin@org1.ormuz.com/msp
export CORE_PEER_LOCALMSPID=OrmuzOrg1MSP
export CORE_PEER_ADDRESS=peer0.org1.ormuz.com:7051
export CORE_PEER_TLS_ENABLED=false

echo '=== Verificando peer ==='
peer channel list

echo '=== Criando canal ==='
peer channel create -o orderer.ormuz.com:7050 -c ormuz-channel -f /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/genesis.block --outputBlock /tmp/ormuz-channel.block 2>/dev/null || echo 'Canal pode já existir'
peer channel join -b /tmp/ormuz-channel.block 2>/dev/null || echo 'Já está no canal'

echo '=== Empacotando chaincode token ==='
cd /opt/gopath/src/chaincode/token
GO111MODULE=on go mod vendor
cd /opt/gopath/src/github.com/hyperledger/fabric/peer
peer lifecycle chaincode package token.tar.gz --path /opt/gopath/src/chaincode/token --lang golang --label token_1.0

echo '=== Empacotando chaincode mission ==='
peer lifecycle chaincode package mission.tar.gz --path /opt/gopath/src/chaincode/mission --lang golang --label mission_1.0

echo '=== Instalando chaincodes ==='
peer lifecycle chaincode install token.tar.gz
peer lifecycle chaincode install mission.tar.gz

echo '=== Query installed ==='
peer lifecycle chaincode queryinstalled

TOKEN_PKG_ID=\$(peer lifecycle chaincode queryinstalled 2>/dev/null | grep token_1.0 | head -1 | awk '{print \$3}' | tr -d ',')
MISSION_PKG_ID=\$(peer lifecycle chaincode queryinstalled 2>/dev/null | grep mission_1.0 | head -1 | awk '{print \$3}' | tr -d ',')

echo \"Token Package ID: \$TOKEN_PKG_ID\"
echo \"Mission Package ID: \$MISSION_PKG_ID\"

echo '=== Aprovando chaincodes ==='
peer lifecycle chaincode approveformyorg -o orderer.ormuz.com:7050 --channelID ormuz-channel --name token --version 1.0 --package-id \$TOKEN_PKG_ID --sequence 1 --tls false --signature-policy \"OR('OrmuzOrg1MSP.member')\"
peer lifecycle chaincode approveformyorg -o orderer.ormuz.com:7050 --channelID ormuz-channel --name mission --version 1.0 --package-id \$MISSION_PKG_ID --sequence 1 --tls false --signature-policy \"OR('OrmuzOrg1MSP.member')\"

echo '=== Commit chaincodes ==='
peer lifecycle chaincode commit -o orderer.ormuz.com:7050 --channelID ormuz-channel --name token --version 1.0 --sequence 1 --tls false --signature-policy \"OR('OrmuzOrg1MSP.member')\"
peer lifecycle chaincode commit -o orderer.ormuz.com:7050 --channelID ormuz-channel --name mission --version 1.0 --sequence 1 --tls false --signature-policy \"OR('OrmuzOrg1MSP.member')\"

echo '=== Verificando ==='
peer chaincode list --installed
peer chaincode list --instantiated -C ormuz-channel

echo '=== Testando token ==='
peer chaincode query -C ormuz-channel -n token -c '{\"Args\":[\"GetBalance\",\"companyA\"]}'

echo '=== Testando mission ==='
peer chaincode query -C ormuz-channel -n mission -c '{\"Args\":[\"GetMissionSummary\"]}'

log_success 'Deploy concluído!'
"
