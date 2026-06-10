cat > ~/stop_all.sh << 'EOF'
#!/bin/bash

echo "=== Parando todos os serviços ==="

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parar brokers
echo -e "${YELLOW}➤ Parando brokers...${NC}"
pkill -f "./broker" 2>/dev/null && echo "  Brokers parados" || echo "  Nenhum broker rodando"

# Parar drones
echo -e "${YELLOW}➤ Parando drones...${NC}"
pkill -f "./drone" 2>/dev/null && echo "  Drones parados" || echo "  Nenhum drone rodando"

# Parar sensores
echo -e "${YELLOW}➤ Parando sensores...${NC}"
pkill -f "./sensor" 2>/dev/null && echo "  Sensores parados" || echo "  Nenhum sensor rodando"

# Parar rede Fabric
echo -e "${YELLOW}➤ Parando Hyperledger Fabric...${NC}"
cd ~/fabric-samples/test-network
./network.sh down 2>/dev/null && echo "  Fabric parado" || echo "  Fabric não estava rodando"

# Remover containers órfãos
echo -e "${YELLOW}➤ Removendo containers órfãos...${NC}"
docker rm -f cli 2>/dev/null && echo "  CLI removido" || true
docker rm -f $(docker ps -aq --filter "status=exited") 2>/dev/null && echo "  Containers órfãos removidos" || true

echo ""
echo -e "${GREEN}✅ Todos os serviços parados!${NC}"
EOF

chmod +x ~/stop_all.sh