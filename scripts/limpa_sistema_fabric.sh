#!/bin/bash
echo "=== LIMPEZA COMPLETA DO SISTEMA ==="


echo "1. Parando containers..."
docker stop $(docker ps -aq) 2>/dev/null
echo "2. Removendo containers..."
docker rm $(docker ps -aq) 2>/dev/null


echo "3. Removendo imagens do Fabric..."
docker rmi $(docker images -q hyperledger/fabric-peer) 2>/dev/null
docker rmi $(docker images -q hyperledger/fabric-orderer) 2>/dev/null
docker rmi $(docker images -q hyperledger/fabric-tools) 2>/dev/null
docker rmi $(docker images -q hyperledger/fabric-ccenv) 2>/dev/null
docker rmi $(docker images -q hyperledger/fabric-baseos) 2>/dev/null
docker rmi $(docker images -q hyperledger/fabric-ca) 2>/dev/null
docker rmi $(docker images -q ghcr.io/hyperledger/fabric-*) 2>/dev/null


echo "4. Removendo volumes..."
docker volume prune -f
docker volume rm $(docker volume ls -q) 2>/dev/null


echo "5. Removendo redes..."
docker network prune -f
docker network rm fabric_test 2>/dev/null


echo "6. Limpando sistema Docker..."
docker system prune -af --volumes


echo "7. Removendo arquivos do Fabric..."
cd ~/Redes-PBL3
rm -rf fabric-samples/
rm -rf organizations/
rm -rf channel-artifacts/
rm -f core.yaml genesis.block *.tar.gz install-fabric.sh


echo "8. Matando processos dos brokers..."
pkill -f "./broker" 2>/dev/null
pkill -f "./drone" 2>/dev/null
pkill -f "./sensor" 2>/dev/null


echo ""
echo "=== VERIFICAÇÃO ==="
echo "Containers: $(docker ps -aq | wc -l)"
echo "Imagens: $(docker images -q | wc -l)"
echo "Volumes: $(docker volume ls -q | wc -l)"


echo ""
echo "✅ LIMPEZA COMPLETA CONCLUÍDA!"

