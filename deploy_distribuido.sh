#!/bin/bash

# Script de Deploy Distribuído - Versão Laboratório (Manual)
set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações - AJUSTADO PARA O SEU LAB
REPO_URL="https://github.com/welton-cerqueira/SISTEMA-DISTRIBUIDO-REDES2.git"
PROJECT_DIR="SISTEMA-DISTRIBUIDO-REDES2"
SSH_USER="tec502"  # Definido como padrão do lab
SSH_PORT="22"
PING_TIMEOUT=2
SSH_TIMEOUT=5

detectar_rede() {
    echo -e "${BLUE}🔍 Detectando rede local...${NC}"
    LOCAL_IP=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
    NETWORK_PREFIX=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    echo -e "${GREEN}✓ Rede: $NETWORK_PREFIX.0/24 | IP Local: $LOCAL_IP${NC}"
}

check_deps() {
    for cmd in ssh ping; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}❌ Falta: $cmd${NC}"; exit 1
        fi
    done
}

testar_ssh() {
    local ip=$1
    if ! ping -c 1 -W $PING_TIMEOUT $ip > /dev/null 2>&1; then return 1; fi
    if timeout $SSH_TIMEOUT bash -c "echo >/dev/tcp/$ip/$SSH_PORT" 2>/dev/null; then return 0; fi
    return 1
}

descobrir_maquinas() {
    echo -e "${BLUE}🔍 Escaneando IPs .1 a .20...${NC}"
    MAQUINAS_DISPONIVEIS=()
    for i in $(seq 1 20); do
        ip="${NETWORK_PREFIX}.$i"
        if [ "$ip" = "$LOCAL_IP" ]; then continue; fi
        printf "  Testando $ip...\r"
        if testar_ssh $ip; then
            echo -e "  ${GREEN}✓ $ip - SSH OK${NC}"
            MAQUINAS_DISPONIVEIS+=("$ip")
        fi
    done
}

selecionar_maquinas() {
    if [ ${#MAQUINAS_DISPONIVEIS[@]} -lt 4 ]; then
        echo -e "${RED}❌ Necessário 4 máquinas.${NC}"; exit 1
    fi
    echo -e "${YELLOW}Selecione 4 (ex: 0 1 2 3) ou ENTER para as primeiras:${NC}"
    read -r selecao
    if [ -z "$selecao" ]; then
        SELECIONADAS=("${MAQUINAS_DISPONIVEIS[@]:0:4}")
    else
        SELECIONADAS=()
        for num in $selecao; do SELECIONADAS+=("${MAQUINAS_DISPONIVEIS[$num]}"); done
    fi
    LAB_IPS_STRING="${SELECIONADAS[*]}"
    export LAB_IPS_STRING
}

# DEPLOY DO BROKER (1 por máquina)
deploy_broker() {
    local ip=$1
    local index=$2
    echo -e "${BLUE}🚀 [Broker $index] Fazendo REBUILD e Deploy em $ip...${NC}"
    
    ssh -t -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USER@$ip" \
    "docker rm -f broker 2>/dev/null || true; \
     rm -rf ~/$PROJECT_DIR; \
     git clone $REPO_URL $PROJECT_DIR && \
     cd $PROJECT_DIR && \
     echo '🔨 Iniciando build do Broker (sem cache)...' && \
     docker build --no-cache -t broker:latest -f Dockerfile . && \
     docker run -d --name broker --network host -e LAB_IPS='$LAB_IPS_STRING' broker:latest"
}

# DEPLOY DOS DRONES (2 por máquina)
deploy_drones() {
    local ip=$1
    local index=$2
    local base_port=$((9100 + index * 2))
    
    echo -e "${BLUE}🚁 [Drones] Fazendo REBUILD e Deploy em $ip...${NC}"
    
    ssh -t -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USER@$ip" \
    "cd ~/$PROJECT_DIR && \
     echo '🔨 Iniciando build dos Drones (sem cache)...' && \
     docker build --no-cache -t drone:latest -f Dockerfile.drone . && \
     echo '🚀 Subindo containers dos Drones...' && \
     docker rm -f drone-01 drone-02 2>/dev/null || true; \
     docker run -d --name drone-01 --network host drone:latest ./drone \
        -id=drone-$(printf "%02d" $((index*2+1))) \
        -port=:$((base_port+1)) && \
     docker run -d --name drone-02 --network host drone:latest ./drone \
        -id=drone-$(printf "%02d" $((index*2+2))) \
        -port=:$((base_port+2))"
}

# DEPLOY DOS SENSORES (2 por máquina)
deploy_sensores() {
    local ip=$1
    local index=$2
    local base_port=$((9300 + index * 2))
    
    echo -e "${BLUE}📡 [Sensores] Fazendo REBUILD e Deploy em $ip...${NC}"
    
    ssh -t -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USER@$ip" \
    "cd ~/$PROJECT_DIR && \
     echo '🔨 Iniciando build dos Sensores (sem cache)...' && \
     docker build --no-cache -t sensor:latest -f Dockerfile.sensor . && \
     echo '🚀 Subindo containers dos Sensores...' && \
     docker rm -f sensor-01 sensor-02 2>/dev/null || true; \
     docker run -d --name sensor-01 --network host sensor:latest ./sensor \
        -id=sensor-$(printf "%02d" $((index*2+1))) \
        -port=:$((base_port+1)) && \
     docker run -d --name sensor-02 --network host sensor:latest ./sensor \
        -id=sensor-$(printf "%02d" $((index*2+2))) \
        -port=:$((base_port+2))"
}

menu() {
    check_deps
    detectar_rede
    descobrir_maquinas
    selecionar_maquinas
    
    echo -e "${YELLOW}📋 Máquinas selecionadas:${NC}"
    for i in "${!SELECIONADAS[@]}"; do
        echo "  $i: ${SELECIONADAS[$i]} (Broker, 2 Drones, 2 Sensores)"
    done
    
    read -p "Confirmar Deploy? (s/n): " confirm
    [[ ! "$confirm" =~ ^[Ss]$ ]] && exit 0
    
    local idx=0
    for ip in "${SELECIONADAS[@]}"; do
        echo -e "\n${BLUE}=== Configurando máquina $((idx+1)): $ip ===${NC}"
        deploy_broker "$ip" "$((idx+1))"
        deploy_drones "$ip" "$idx"
        deploy_sensores "$ip" "$idx"
        idx=$((idx+1))
    done
    
    echo -e "\n${GREEN}✅ SISTEMA DISTRIBUÍDO NO AR!${NC}"
    echo -e "${BLUE}📊 Resumo do Deploy (4 máquinas):${NC}"
    echo "  - Brokers: 4 instâncias (1 por máquina)"
    echo "  - Drones: 8 instâncias (2 por máquina)"
    echo "  - Sensores: 8 instâncias (2 por máquina)"
    echo -e "${YELLOW}💡 Todos os brokers se comunicam entre si via LAB_IPS='$LAB_IPS_STRING'${NC}"
}

menu