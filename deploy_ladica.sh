#!/bin/bash

# Script de Deploy para Laboratório LADICA
# Uso: ./deploy_ladica.sh --ips "172.16.201.1 172.16.201.2 172.16.201.3 172.16.201.4"

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configurações padrão
SSH_USER="${SSH_USER:-tec502}"
SSH_PASS="${SSH_PASS:-}"
PROJECT_DIR="SISTEMA-DISTRIBUIDO-REDES2"
REPO_URL="https://github.com/welton-cerqueira/SISTEMA-DISTRIBUIDO-REDES2.git"
BASE_PORTS=(9000 9010 9020 9030)  # TCP ports para cada broker
BASE_UDP_PORTS=(9001 9011 9021 9031)  # UDP ports
BASE_SENSOR_PORTS=(9002 9012 9022 9032)  # Sensor ports
DRONE_PORTS=(9101 9102 9103 9104 9105 9106 9107 9108)  # Drones

# Arrays para armazenar IPs
declare -a IPS_LIST=()

# Função para mostrar ajuda
show_help() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}DEPLOY DISTRIBUÍDO - LABORATÓRIO LADICA${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Uso:${NC} $0 --ips \"IP1 IP2 IP3 IP4\" [OPÇÕES]"
    echo ""
    echo -e "${BLUE}Opções:${NC}"
    echo "  --ips \"IP1 IP2 IP3 IP4\"   Lista de IPs das máquinas (obrigatório)"
    echo "  --user USER               Usuário SSH (padrão: tec502)"
    echo "  --pass PASS               Senha SSH"
    echo "  --help                    Mostra esta ajuda"
    echo ""
    echo -e "${BLUE}Exemplo:${NC}"
    echo "  $0 --ips \"172.16.201.1 172.16.201.2 172.16.201.3 172.16.201.4\""
    echo "  $0 --ips \"192.168.1.101 192.168.1.102 192.168.1.103 192.168.1.104\" --user aluno --pass 123456"
    echo ""
    echo -e "${BLUE}O que o script faz:${NC}"
    echo "  1. Constrói imagens Docker (broker, drone, sensor) em cada máquina"
    echo "  2. Inicia 1 broker por máquina"
    echo "  3. Inicia 2 drones por máquina (total 8 drones)"
    echo "  4. Inicia 2 sensores por máquina (total 8 sensores)"
    echo "  5. Configura LAB_IPS automaticamente entre as máquinas"
    echo ""
}

# Função para verificar dependências
check_dependencies() {
    local deps_ok=true
    
    for cmd in ssh ping; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}❌ Comando não encontrado: $cmd${NC}"
            deps_ok=false
        fi
    done
    
    if [ "$deps_ok" = false ]; then
        exit 1
    fi
}

# Função para testar conexão SSH
testar_conexao() {
    local ip=$1
    
    if ! ping -c 1 -W 1 $ip &> /dev/null; then
        return 1
    fi
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=3 $SSH_USER@$ip 'echo "OK"' &> /dev/null
    else
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
            $SSH_USER@$ip 'echo "OK"' &> /dev/null
    fi
}

# Função para construir imagens em uma máquina
build_images() {
    local ip=$1
    local index=$2
    
    echo -e "${BLUE}[$ip] Construindo imagens Docker...${NC}"
    
    local cmd="
        cd ~/$PROJECT_DIR && \
        echo '  → Broker...' && \
        docker build -t broker:latest -f Dockerfile . && \
        echo '  → Drone...' && \
        docker build -t drone:latest -f Dockerfile.drone . && \
        echo '  → Sensor...' && \
        docker build -t sensor:latest -f Dockerfile.sensor .
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função para deploy do broker
deploy_broker() {
    local ip=$1
    local index=$2
    local lab_ips_str="$3"
    
    echo -e "${BLUE}[$ip] Deployando broker-$((index+1))...${NC}"
    
    local cmd="
        docker rm -f broker 2>/dev/null || true && \
        docker run -d --name broker --network host \
            -e LAB_IPS='$lab_ips_str' \
            broker:latest
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função para deploy dos drones
deploy_drones() {
    local ip=$1
    local index=$2
    local drone_offset=$((index * 2))
    local drone1_id=$((drone_offset + 1))
    local drone2_id=$((drone_offset + 2))
    local drone1_port=${DRONE_PORTS[$drone_offset]}
    local drone2_port=${DRONE_PORTS[$((drone_offset + 1))]}
    
    echo -e "${BLUE}[$ip] Deployando drones (drone-$(printf "%02d" $drone1_id) e drone-$(printf "%02d" $drone2_id))...${NC}"
    
    local cmd="
        docker rm -f drone-01 drone-02 2>/dev/null || true && \
        docker run -d --name drone-01 --network host drone:latest ./drone -id=drone-$(printf "%02d" $drone1_id) -port=:$drone1_port && \
        docker run -d --name drone-02 --network host drone:latest ./drone -id=drone-$(printf "%02d" $drone2_id) -port=:$drone2_port
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função para deploy dos sensores
deploy_sensores() {
    local ip=$1
    local index=$2
    local sensor_port=${BASE_SENSOR_PORTS[$index]}
    local sensor_offset=$((index * 2))
    local sensor1_id=$((sensor_offset + 1))
    local sensor2_id=$((sensor_offset + 2))
    
    echo -e "${BLUE}[$ip] Deployando sensores (sensor-$(printf "%02d" $sensor1_id) e sensor-$(printf "%02d" $sensor2_id))...${NC}"
    
    # Define tipos e localizações baseados no índice
    case $index in
        0)
            local tipo1="movimento"
            local tipo2="temperatura"
            local local1="setor-norte-1"
            local local2="setor-norte-2"
            ;;
        1)
            local tipo1="pressao"
            local tipo2="movimento"
            local local1="setor-sul-1"
            local local2="setor-sul-2"
            ;;
        2)
            local tipo1="temperatura"
            local tipo2="pressao"
            local local1="setor-leste-1"
            local local2="setor-leste-2"
            ;;
        3)
            local tipo1="movimento"
            local tipo2="temperatura"
            local local1="setor-oeste-1"
            local local2="setor-oeste-2"
            ;;
    esac
    
    local cmd="
        docker rm -f sensor-01 sensor-02 2>/dev/null || true && \
        docker run -d --name sensor-01 --network host sensor:latest ./sensor -id=sensor-$(printf "%02d" $sensor1_id) -tipo=$tipo1 -local='$local1' -brokers=$ip:$sensor_port && \
        docker run -d --name sensor-02 --network host sensor:latest ./sensor -id=sensor-$(printf "%02d" $sensor2_id) -tipo=$tipo2 -local='$local2' -brokers=$ip:$sensor_port
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função para verificar status
check_status() {
    local ip=$1
    local index=$2
    
    echo -e "${BLUE}[$ip] Verificando status...${NC}"
    
    local cmd="
        echo '  Broker: ' && docker ps --filter name=broker --format '{{.Status}}' && \
        echo '  Drones: ' && docker ps --filter name=drone --format 'table {{.Names}}\t{{.Status}}' && \
        echo '  Sensores: ' && docker ps --filter name=sensor --format 'table {{.Names}}\t{{.Status}}'
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função para obter ou clonar o repositório
setup_repository() {
    local ip=$1
    
    echo -e "${BLUE}[$ip] Preparando repositório...${NC}"
    
    local cmd="
        if [ ! -d ~/$PROJECT_DIR ]; then
            git clone $REPO_URL ~/$PROJECT_DIR
        else
            cd ~/$PROJECT_DIR && git pull
        fi
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função principal
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ips)
                shift
                IPS_LIST=($1)
                shift
                ;;
            --user)
                shift
                SSH_USER=$1
                shift
                ;;
            --pass)
                shift
                SSH_PASS=$1
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Opção desconhecida: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validação
    if [ ${#IPS_LIST[@]} -ne 4 ]; then
        echo -e "${RED}❌ Erro: É necessário exatamente 4 IPs!${NC}"
        echo -e "${YELLOW}Você forneceu ${#IPS_LIST[@]} IP(s): ${IPS_LIST[@]}${NC}"
        show_help
        exit 1
    fi
    
    check_dependencies
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}DEPLOY DISTRIBUÍDO - LABORATÓRIO LADICA${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📋 Configuração:${NC}"
    echo -e "  Usuário SSH: ${GREEN}$SSH_USER${NC}"
    echo -e "  Máquinas: ${GREEN}${IPS_LIST[*]}${NC}"
    echo ""
    
    # Testar conexões
    echo -e "${BLUE}🔍 Testando conexões SSH...${NC}"
    for i in "${!IPS_LIST[@]}"; do
        ip=${IPS_LIST[$i]}
        if testar_conexao $ip; then
            echo -e "  ${GREEN}✓ $ip - OK${NC}"
        else
            echo -e "  ${RED}✗ $ip - Falha na conexão${NC}"
            exit 1
        fi
    done
    echo ""
    
    # Preparar string LAB_IPS
    LAB_IPS_STRING="${IPS_LIST[*]}"
    echo -e "${BLUE}📡 LAB_IPS configurado: ${GREEN}$LAB_IPS_STRING${NC}"
    echo ""
    
    # Confirmar deploy
    echo -e "${YELLOW}⚠️  O deploy será feito nas seguintes máquinas:${NC}"
    for i in "${!IPS_LIST[@]}"; do
        echo "  $((i+1)). ${IPS_LIST[$i]} (Broker $((i+1)) + 2 drones + 2 sensores)"
    done
    echo ""
    read -p "Deseja continuar? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}Deploy cancelado.${NC}"
        exit 0
    fi
    echo ""
    
    # Fazer deploy em cada máquina
    for i in "${!IPS_LIST[@]}"; do
        ip=${IPS_LIST[$i]}
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}🚀 Configurando máquina $((i+1)): $ip${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        
        setup_repository $ip
        build_images $ip $i
        deploy_broker $ip $i "$LAB_IPS_STRING"
        deploy_drones $ip $i
        deploy_sensores $ip $i
        
        echo ""
    done
    
    # Aguardar inicialização
    echo -e "${BLUE}⏳ Aguardando 10 segundos para os brokers se estabilizarem...${NC}"
    sleep 10
    
    # Verificar status final
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📊 STATUS FINAL DOS COMPONENTES${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    for i in "${!IPS_LIST[@]}"; do
        ip=${IPS_LIST[$i]}
        echo -e "${BLUE}=== Máquina $((i+1)): $ip ===${NC}"
        check_status $ip $i
        echo ""
    done
    
    # Verificar líder eleito
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🏆 VERIFICANDO LÍDER ELEITO${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    
    leader_ip=${IPS_LIST[0]}
    echo -e "${BLUE}Consultando broker em $leader_ip...${NC}"
    
    local cmd="docker logs broker 2>&1 | grep 'Novo líder eleito' | tail -1"
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$leader_ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$leader_ip "$cmd"
    fi
    
    echo ""
    echo -e "${GREEN}✅ DEPLOY CONCLUÍDO COM SUCESSO!${NC}"
    echo ""
    echo -e "${BLUE}📋 Comandos úteis:${NC}"
    echo "  Ver logs de um broker:     ssh $SSH_USER@<ip> 'docker logs -f broker'"
    echo "  Ver logs de um drone:      ssh $SSH_USER@<ip> 'docker logs -f drone-01'"
    echo "  Ver logs de um sensor:     ssh $SSH_USER@<ip> 'docker logs -f sensor-01'"
    echo "  Parar tudo:                for ip in ${IPS_LIST[*]}; do ssh $SSH_USER@\$ip 'docker rm -f broker drone-01 drone-02 sensor-01 sensor-02'; done"
    echo ""
}

# Executar main com todos os argumentos
main "$@"