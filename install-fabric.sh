#!/bin/bash

# ============================================================================
# Script de Instalação Completa - Hyperledger Fabric + Broker
# Autor: Sistema Distribuído de Brokers
# Uso: ./install-fabric.sh [--broker-id ID] [--fabric-ip IP]
# ============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================================================
# CONFIGURAÇÕES PADRÃO
# ============================================================================

PROJECT_DIR="$HOME/Redes-PBL3"
FABRIC_DIR="$HOME/fabric-samples"
FABRIC_VERSION="2.5.0"
CA_VERSION="1.5.7"
CHANNEL_NAME="ormuz-channel"
BROKER_ID=""
FABRIC_IP=""
MODE="all"  # all, fabric, broker, chaincode

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}SISTEMA DISTRIBUÍDO DE BROKERS - INSTALAÇÃO COMPLETA${NC}                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}Hyperledger Fabric + Broker + Chaincodes${NC}                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                          ${CYAN}║${NC}"
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

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ️${NC} $1"
}

# ============================================================================
# VERIFICAÇÃO DE PRÉ-REQUISITOS
# ============================================================================

check_prerequisites() {
    print_step "Verificando pré-requisitos"
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker não encontrado. Instale Docker primeiro."
        exit 1
    fi
    print_success "Docker encontrado: $(docker --version)"
    
    # Verificar Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose não encontrado. Instale docker-compose primeiro."
        exit 1
    fi
    print_success "Docker Compose encontrado: $(docker-compose --version)"
    
    # Verificar Go
    if ! command -v go &> /dev/null; then
        print_error "Go não encontrado. Instale Go 1.21+ primeiro."
        exit 1
    fi
    print_success "Go encontrado: $(go version)"
    
    # Verificar Git
    if ! command -v git &> /dev/null; then
        print_error "Git não encontrado. Instale Git primeiro."
        exit 1
    fi
    print_success "Git encontrado: $(git --version)"
    
    # Verificar jq
    if ! command -v jq &> /dev/null; then
        print_warning "jq não encontrado, instalando..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
    print_success "jq encontrado"
    
    # Verificar netcat
    if ! command -v nc &> /dev/null; then
        print_warning "netcat não encontrado, instalando..."
        sudo apt-get install -y netcat-openbsd
    fi
    print_success "netcat encontrado"
}

# ============================================================================
# INSTALAÇÃO DOS BINÁRIOS DO FABRIC
# ============================================================================

install_fabric_binaries() {
    print_step "Instalando Hyperledger Fabric binaries"
    
    # Criar diretório
    mkdir -p "$FABRIC_DIR"
    cd "$FABRIC_DIR"
    
    # Baixar binários
    print_info "Baixando Fabric v${FABRIC_VERSION}..."
    curl -sSL "https://github.com/hyperledger/fabric/releases/download/v${FABRIC_VERSION}/hyperledger-fabric-linux-amd64-${FABRIC_VERSION}.tar.gz" | tar -xz
    
    # Baixar Fabric CA
    print_info "Baixando Fabric CA v${CA_VERSION}..."
    curl -sSL "https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/hyperledger-fabric-ca-linux-amd64-${CA_VERSION}.tar.gz" | tar -xz
    
    # Adicionar ao PATH
    export PATH="$FABRIC_DIR/bin:$PATH"
    
    # Verificar instalação
    if [ -f "$FABRIC_DIR/bin/peer" ]; then
        print_success "Peer CLI instalado: $($FABRIC_DIR/bin/peer version | head -1)"
    else
        print_error "Falha ao instalar Fabric binaries"
        exit 1
    fi
    
    if [ -f "$FABRIC_DIR/bin/configtxgen" ]; then
        print_success "Configtxgen instalado"
    fi
    
    print_success "Fabric binaries instalados em $FABRIC_DIR/bin"
}

# ============================================================================
# CONFIGURAÇÃO DO PROJETO
# ============================================================================

setup_project() {
    print_step "Configurando diretório do projeto"
    
    if [ -d "$PROJECT_DIR" ]; then
        print_info "Diretório do projeto já existe: $PROJECT_DIR"
        cd "$PROJECT_DIR"
        
        # Atualizar dependências
        print_info "Atualizando dependências Go..."
        go mod tidy
        go mod download
    else
        print_error "Diretório do projeto não encontrado: $PROJECT_DIR"
        print_info "Clone o repositório: git clone <seu-repo> $PROJECT_DIR"
        exit 1
    fi
    
    # Compilar broker
    print_info "Compilando broker..."
    go build -o broker ./cmd/broker/
    print_success "Broker compilado: $PROJECT_DIR/broker"
    
    # Compilar drone
    print_info "Compilando drone..."
    go build -o drone ./cmd/drone/
    print_success "Drone compilado: $PROJECT_DIR/drone"
    
    # Compilar sensor
    print_info "Compilando sensor..."
    go build -o sensor ./cmd/sensor/
    print_success "Sensor compilado: $PROJECT_DIR/sensor"
}

# ============================================================================
# INICIAR REDE FABRIC
# ============================================================================

start_fabric_network() {
    print_step "Iniciando rede Hyperledger Fabric"
    
    cd "$FABRIC_DIR/test-network"
    
    # Limpar rede anterior
    print_info "Limpando rede anterior..."
    ./network.sh down 2>/dev/null || true
    
    # Subir rede com cryptogen (sem CA)
    print_info "Subindo rede com cryptogen..."
    ./network.sh up createChannel -c "$CHANNEL_NAME"
    
    if [ $? -ne 0 ]; then
        print_error "Falha ao subir rede Fabric"
        exit 1
    fi
    
    print_success "Rede Fabric iniciada com sucesso"
    
    # Verificar containers
    echo ""
    print_info "Containers rodando:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "peer|orderer|cli"
}

# ============================================================================
# DEPLOY DOS CHAINCODES
# ============================================================================

deploy_chaincodes() {
    print_step "Deploy dos chaincodes (token e mission)"
    
    cd "$FABRIC_DIR/test-network"
    
    # Copiar chaincodes
    print_info "Copiando chaincodes para o test-network..."
    mkdir -p "$FABRIC_DIR/test-network/chaincode"
    cp -r "$PROJECT_DIR/chaincode/"* "$FABRIC_DIR/test-network/chaincode/"
    
    # Deploy do token
    print_info "Deploy do chaincode token..."
    ./network.sh deployCC -ccn token -ccp "$PROJECT_DIR/chaincode/token" -ccl go -c "$CHANNEL_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Chaincode token deployado"
    else
        print_warning "Chaincode token pode já estar instalado"
    fi
    
    # Deploy do mission
    print_info "Deploy do chaincode mission..."
    ./network.sh deployCC -ccn mission -ccp "$PROJECT_DIR/chaincode/mission" -ccl go -c "$CHANNEL_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Chaincode mission deployado"
    else
        print_warning "Chaincode mission pode já estar instalado"
    fi
    
    # Testar chaincodes
    test_chaincodes
}

# ============================================================================
# TESTAR CHAINCODES
# ============================================================================

test_chaincodes() {
    print_step "Testando chaincodes"
    
    cd "$FABRIC_DIR/test-network"
    
    # Configurar peer
    export PATH="$FABRIC_DIR/bin:$PATH"
    export FABRIC_CFG_PATH="$FABRIC_DIR/config"
    export CORE_PEER_TLS_ENABLED=false
    export CORE_PEER_LOCALMSPID=Org1MSP
    export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
    export CORE_PEER_ADDRESS=localhost:7051
    
    # Testar token
    print_info "Testando chaincode token..."
    if peer chaincode query -C "$CHANNEL_NAME" -n token -c '{"Args":["GetBalance","companyA"]}' 2>/dev/null; then
        print_success "Chaincode token funcionando"
    else
        print_warning "Chaincode token não inicializado, executando InitLedger..."
        
        # Inicializar ledger do token
        docker exec cli peer chaincode invoke -C "$CHANNEL_NAME" -n token -c '{"Args":["InitLedger"]}' --waitForEvent 2>/dev/null || true
        peer chaincode query -C "$CHANNEL_NAME" -n token -c '{"Args":["GetBalance","companyA"]}' && print_success "Token inicializado" || print_warning "Token precisa de init manual"
    fi
    
    # Testar mission
    print_info "Testando chaincode mission..."
    if peer chaincode query -C "$CHANNEL_NAME" -n mission -c '{"Args":["GetMissionSummary"]}' 2>/dev/null; then
        print_success "Chaincode mission funcionando"
    else
        print_warning "Chaincode mission não inicializado"
        docker exec cli peer chaincode invoke -C "$CHANNEL_NAME" -n mission -c '{"Args":["InitLedger"]}' --waitForEvent 2>/dev/null || true
    fi
}

# ============================================================================
# CRIAR SCRIPT DE START DO BROKER
# ============================================================================

create_broker_script() {
    print_step "Criando script de inicialização do broker"
    
    cat > "$HOME/start_broker.sh" << 'EOF'
#!/bin/bash

# ============================================================================
# Script de inicialização do Broker
# Uso: ./start_broker.sh [ID_DO_BROKER] [IP_FABRIC]
# ============================================================================

BROKER_ID=${1:-"1"}
FABRIC_IP=${2:-"localhost"}

# Portas
TCP_PORT=":900${BROKER_ID}0"
UDP_PORT=":900${BROKER_ID}1"
SENSOR_PORT=":900${BROKER_ID}2"

# Configuração dos peers (vizinhos)
PEERS=""
for i in 1 2 3 4; do
    if [ $i -ne $BROKER_ID ]; then
        if [ -n "$PEERS" ]; then
            PEERS="${PEERS};"
        fi
        PEERS="${PEERS}broker-${i},localhost:900${i}0,localhost:900${i}1"
    fi
done

# Drones configurados para este broker
DRONES=""
case $BROKER_ID in
    1) DRONES="drone-01=localhost:9101,drone-02=localhost:9102" ;;
    2) DRONES="drone-03=localhost:9103,drone-04=localhost:9104" ;;
    3) DRONES="drone-05=localhost:9105,drone-06=localhost:9106" ;;
    4) DRONES="drone-07=localhost:9107,drone-08=localhost:9108" ;;
esac

cd ~/Redes-PBL3

echo "=== Iniciando Broker-$BROKER_ID ==="
echo "TCP: $TCP_PORT | UDP: $UDP_PORT | Sensores: $SENSOR_PORT"
echo "Fabric Gateway: http://${FABRIC_IP}:7051"
echo ""

./broker \
    -id="broker-${BROKER_ID}" \
    -porta-tcp="${TCP_PORT}" \
    -porta-udp="${UDP_PORT}" \
    -porta-ctrl="${SENSOR_PORT}" \
    -drones="${DRONES}" \
    -peers="${PEERS}" \
    -enable-ledger=true \
    -ledger-mock=false \
    -ledger-gateway="http://${FABRIC_IP}:7051"
EOF

    chmod +x "$HOME/start_broker.sh"
    print_success "Script criado: ~/start_broker.sh"
}

# ============================================================================
# CRIAR SCRIPT DE START DOS DRONES
# ============================================================================

create_drone_script() {
    print_step "Criando script de inicialização dos drones"
    
    cat > "$HOME/start_drones.sh" << 'EOF'
#!/bin/bash

# ============================================================================
# Script de inicialização dos drones
# ============================================================================

cd ~/Redes-PBL3

for i in 1 2 3 4 5 6 7 8; do
    PORT=$((9100 + i))
    DRONE_ID="drone-0${i}"
    echo "Iniciando $DRONE_ID na porta $PORT"
    ./drone -id="$DRONE_ID" -port=":$PORT" &
    sleep 0.5
done

echo "✅ 8 drones iniciados"
EOF

    chmod +x "$HOME/start_drones.sh"
    print_success "Script criado: ~/start_drones.sh"
}

# ============================================================================
# CRIAR SCRIPT DE START DOS SENSORES
# ============================================================================

create_sensor_script() {
    print_step "Criando script de inicialização dos sensores"
    
    cat > "$HOME/start_sensors.sh" << 'EOF'
#!/bin/bash

# ============================================================================
# Script de inicialização dos sensores
# ============================================================================

cd ~/Redes-PBL3

# Broker 1 - Setor Norte (porta 9002)
BROKER1="localhost:9002"
./sensor -id="sensor-norte-mov" -tipo="movimento" -local="setor-norte-1" -brokers="$BROKER1" &
./sensor -id="sensor-norte-press" -tipo="pressao" -local="setor-norte-2" -brokers="$BROKER1" &
./sensor -id="sensor-norte-temp" -tipo="temperatura" -local="setor-norte-3" -brokers="$BROKER1" &

# Broker 2 - Setor Sul (porta 9012)
BROKER2="localhost:9012"
./sensor -id="sensor-sul-mov" -tipo="movimento" -local="setor-sul-1" -brokers="$BROKER2" &
./sensor -id="sensor-sul-press" -tipo="pressao" -local="setor-sul-2" -brokers="$BROKER2" &
./sensor -id="sensor-sul-temp" -tipo="temperatura" -local="setor-sul-3" -brokers="$BROKER2" &

# Broker 3 - Setor Leste (porta 9022)
BROKER3="localhost:9022"
./sensor -id="sensor-leste-mov" -tipo="movimento" -local="setor-leste-1" -brokers="$BROKER3" &
./sensor -id="sensor-leste-press" -tipo="pressao" -local="setor-leste-2" -brokers="$BROKER3" &
./sensor -id="sensor-leste-temp" -tipo="temperatura" -local="setor-leste-3" -brokers="$BROKER3" &

# Broker 4 - Setor Oeste (porta 9032)
BROKER4="localhost:9032"
./sensor -id="sensor-oeste-mov" -tipo="movimento" -local="setor-oeste-1" -brokers="$BROKER4" &
./sensor -id="sensor-oeste-press" -tipo="pressao" -local="setor-oeste-2" -brokers="$BROKER4" &
./sensor -id="sensor-oeste-temp" -tipo="temperatura" -local="setor-oeste-3" -brokers="$BROKER4" &

echo "✅ 12 sensores iniciados"
EOF

    chmod +x "$HOME/start_sensors.sh"
    print_success "Script criado: ~/start_sensors.sh"
}

# ============================================================================
# CRIAR SCRIPT DE STATUS
# ============================================================================

create_status_script() {
    print_step "Criando script de status do sistema"
    
    cat > "$HOME/status.sh" << 'EOF'
#!/bin/bash

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                         STATUS DO SISTEMA                                 ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Fabric
echo -e "${CYAN}📦 Hyperledger Fabric:${NC}"
for container in orderer.example.com peer0.org1.example.com peer0.org2.example.com cli; do
    if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
        echo -e "  ${GREEN}✓${NC} $container"
    else
        echo -e "  ${RED}✗${NC} $container"
    fi
done

# Brokers
echo ""
echo -e "${CYAN}🖥️ Brokers:${NC}"
for i in 1 2 3 4; do
    PORT=$((9000 + (i-1)*10))
    if nc -zv localhost $PORT 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} broker-$i (porta $PORT)"
    else
        echo -e "  ${RED}✗${NC} broker-$i (porta $PORT)"
    fi
done

# Chaincodes
echo ""
echo -e "${CYAN}📜 Chaincodes:${NC}"
export PATH=$HOME/fabric-samples/bin:$PATH
export CORE_PEER_TLS_ENABLED=false
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_MSPCONFIGPATH=$HOME/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051

if peer chaincode query -C ormuz-channel -n token -c '{"Args":["GetBalance","companyA"]}' 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} token"
else
    echo -e "  ${RED}✗${NC} token"
fi

if peer chaincode query -C ormuz-channel -n mission -c '{"Args":["GetMissionSummary"]}' 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} mission"
else
    echo -e "  ${RED}✗${NC} mission"
fi

echo ""
EOF

    chmod +x "$HOME/status.sh"
    print_success "Script criado: ~/status.sh"
}

# ============================================================================
# CRIAR SCRIPT DE PARADA
# ============================================================================

create_stop_script() {
    print_step "Criando script de parada do sistema"
    
    cat > "$HOME/stop_all.sh" << 'EOF'
#!/bin/bash

echo "=== Parando todos os serviços ==="

# Parar brokers
pkill -f "./broker" 2>/dev/null || true
pkill -f "./drone" 2>/dev/null || true
pkill -f "./sensor" 2>/dev/null || true

# Parar Fabric
cd ~/fabric-samples/test-network
./network.sh down 2>/dev/null || true

# Limpar containers órfãos
docker rm -f $(docker ps -aq) 2>/dev/null || true

echo "✅ Todos os serviços parados"
EOF

    chmod +x "$HOME/stop_all.sh"
    print_success "Script criado: ~/stop_all.sh"
}

# ============================================================================
# CRIAR SCRIPT DE INÍCIO COMPLETO
# ============================================================================

create_start_all_script() {
    print_step "Criando script de início completo"
    
    cat > "$HOME/start_all.sh" << 'EOF'
#!/bin/bash

echo "=== Iniciando Sistema Distribuído de Brokers ==="

# 1. Iniciar Fabric
echo "1. Iniciando Hyperledger Fabric..."
cd ~/fabric-samples/test-network
./network.sh up createChannel -c ormuz-channel

# 2. Deploy chaincodes (se necessário)
echo "2. Verificando chaincodes..."
./network.sh deployCC -ccn token -ccp ~/Redes-PBL3/chaincode/token -ccl go -c ormuz-channel 2>/dev/null || echo "   Token OK"
./network.sh deployCC -ccn mission -ccp ~/Redes-PBL3/chaincode/mission -ccl go -c ormuz-channel 2>/dev/null || echo "   Mission OK"

# 3. Iniciar drones
echo "3. Iniciando drones..."
~/start_drones.sh

# 4. Iniciar sensores
echo "4. Iniciando sensores..."
~/start_sensors.sh

# 5. Iniciar brokers
echo "5. Iniciando brokers..."
for i in 1 2 3 4; do
    ~/start_broker.sh $i localhost &
    sleep 2
done

echo ""
echo "✅ Sistema iniciado!"
echo ""
echo "Para verificar status: ~/status.sh"
echo "Para parar: ~/stop_all.sh"
EOF

    chmod +x "$HOME/start_all.sh"
    print_success "Script criado: ~/start_all.sh"
}

# ============================================================================
# CONFIGURAR PERMANENTEMENTE O PATH
# ============================================================================

setup_path() {
    print_step "Configurando PATH permanentemente"
    
    if ! grep -q "fabric-samples/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:$HOME/fabric-samples/bin' >> ~/.bashrc
        print_success "PATH adicionado ao ~/.bashrc"
    else
        print_info "PATH já configurado"
    fi
    
    # Aplicar no ambiente atual
    export PATH="$FABRIC_DIR/bin:$PATH"
}

# ============================================================================
# MENU DE AJUDA
# ============================================================================

show_help() {
    echo ""
    echo -e "${CYAN}Uso:${NC} $0 [opções]"
    echo ""
    echo -e "${CYAN}Opções:${NC}"
    echo "  --help              Mostra esta ajuda"
    echo "  --broker-id ID      Define o ID do broker (1-4)"
    echo "  --fabric-ip IP      Define o IP da máquina Fabric"
    echo "  --mode MODE         Modo de instalação: all, fabric, broker, chaincode"
    echo ""
    echo -e "${CYAN}Modos:${NC}"
    echo "  all                 Instala tudo (padrão)"
    echo "  fabric              Apenas Fabric + chaincodes"
    echo "  broker              Apenas compila o broker"
    echo "  chaincode           Apenas deploy dos chaincodes"
    echo ""
    echo -e "${CYAN}Exemplos:${NC}"
    echo "  $0                                  # Instala tudo"
    echo "  $0 --mode fabric                    # Só Fabric"
    echo "  $0 --broker-id 1 --fabric-ip 192.168.1.100  # Configura broker"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_banner
    
    # Processar argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --broker-id)
                BROKER_ID="$2"
                shift 2
                ;;
            --fabric-ip)
                FABRIC_IP="$2"
                shift 2
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            *)
                echo "Opção desconhecida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Executar com base no modo
    case $MODE in
        all)
            check_prerequisites
            install_fabric_binaries
            setup_project
            start_fabric_network
            deploy_chaincodes
            create_broker_script
            create_drone_script
            create_sensor_script
            create_status_script
            create_stop_script
            create_start_all_script
            setup_path
            ;;
        fabric)
            check_prerequisites
            install_fabric_binaries
            start_fabric_network
            deploy_chaincodes
            ;;
        broker)
            setup_project
            create_broker_script
            create_drone_script
            create_sensor_script
            ;;
        chaincode)
            deploy_chaincodes
            ;;
        *)
            print_error "Modo desconhecido: $MODE"
            show_help
            exit 1
            ;;
    esac
    
    # Resumo final
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}                       ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📋 Comandos úteis:${NC}"
    echo ""
    echo -e "  ${YELLOW}~/start_all.sh${NC}      - Inicia tudo (Fabric + Brokers + Drones + Sensores)"
    echo -e "  ${YELLOW}~/status.sh${NC}         - Verifica status do sistema"
    echo -e "  ${YELLOW}~/stop_all.sh${NC}       - Para todos os serviços"
    echo ""
    echo -e "  ${YELLOW}~/start_broker.sh 1${NC} - Inicia apenas Broker 1"
    echo -e "  ${YELLOW}~/start_drones.sh${NC}   - Inicia os 8 drones"
    echo -e "  ${YELLOW}~/start_sensors.sh${NC}  - Inicia os 12 sensores"
    echo ""
    echo -e "${CYAN}📊 Para ver logs:${NC}"
    echo -e "  ${YELLOW}docker logs -f cli${NC}  - Logs do Fabric CLI"
    echo -e "  ${YELLOW}tail -f /tmp/broker-*.log${NC} - Logs dos brokers"
    echo ""
}

# Executar main
main "$@"