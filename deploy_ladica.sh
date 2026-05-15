#!/bin/bash

# Script de Deploy para Laboratório (genérico - aceita qualquer rede)
# Uso: ./deploy_ladica.sh --ips "172.16.103.1 172.16.103.2 172.16.103.3 172.16.103.4"

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

# Arrays para armazenar IPs
declare -a IPS_LIST=()

# Função para mostrar ajuda
show_help() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}DEPLOY DISTRIBUÍDO - LABORATÓRIO${NC}                       ${CYAN}║${NC}"
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
    echo "  $0 --ips \"172.16.103.1 172.16.103.2 172.16.103.3 172.16.103.4\""
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
    
    # Verificar sshpass se senha foi fornecida
    if [ -n "$SSH_PASS" ] && ! command -v sshpass &> /dev/null; then
        echo -e "${RED}❌ sshpass não encontrado. Instale com: sudo apt install sshpass${NC}"
        deps_ok=false
    fi
    
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
    
    echo -e "${BLUE}[$ip] Construindo imagens Docker...${NC}"
    
    local cmd="
        cd ~/$PROJECT_DIR && \
        echo '  → Broker...' && \
        docker build -t broker:latest -f Dockerfile . && \
        echo '  → Drone...' && \
        docker build -t drone:latest -f Dockerfile.drone . && \
        echo '  → Sensor...' && \
        docker build -t sensor:latest -f Dockerfile.sensor . && \
        echo '  ✓ Imagens construídas com sucesso!'
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
    
    local broker_id=$((index + 1))
    local base_port=$((9000 + index * 10))
    local tcp_port=":${base_port}"
    local udp_port=":$(($base_port+1))"
    local sensor_port=":$(($base_port+2))"
    
    echo -e "${BLUE}[$ip] Deployando broker-${broker_id} (portas: TCP=${base_port}, UDP=$(($base_port+1)), Sensores=$(($base_port+2)))...${NC}"
    
    local cmd="
        docker rm -f broker 2>/dev/null || true && \
        docker run -d --name broker --network host \
            -e LAB_IPS='$lab_ips_str' \
            broker:latest \
            -id=broker-${broker_id} \
            -porta-tcp=$tcp_port \
            -porta-udp=$udp_port \
            -porta-ctrl=$sensor_port
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# Função para deploy dos drones (IDs ÚNICOS de 1 a 8)
deploy_drones() {
    local ip=$1
    local index=$2
    
    # Cálculo dos IDs únicos dos drones (1 a 8)
    # Máquina 0 (índice 0): drones 1 e 2
    # Máquina 1 (índice 1): drones 3 e 4
    # Máquina 2 (índice 2): drones 5 e 6
    # Máquina 3 (índice 3): drones 7 e 8
    local drone1_id=$((index * 2 + 1))
    local drone2_id=$((index * 2 + 2))
    
    # Portas baseadas no ID do drone (9101 a 9108)
    local drone1_port=$((9100 + drone1_id))
    local drone2_port=$((9100 + drone2_id))
    
    echo -e "${BLUE}[$ip] Deployando drones: drone-$(printf "%02d" $drone1_id) (porta $drone1_port) e drone-$(printf "%02d" $drone2_id) (porta $drone2_port)...${NC}"
    
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

# Função para deploy dos sensores (IDs ÚNICOS de 1 a 8)
deploy_sensores() {
    local ip=$1
    local index=$2
    
    # Cálculo dos IDs únicos dos sensores (1 a 8)
    # Máquina 0 (índice 0): sensores 1 e 2
    # Máquina 1 (índice 1): sensores 3 e 4
    # Máquina 2 (índice 2): sensores 5 e 6
    # Máquina 3 (índice 3): sensores 7 e 8
    local sensor1_id=$((index * 2 + 1))
    local sensor2_id=$((index * 2 + 2))
    
    local sensor_port=$((9002 + index * 10))
    
    echo -e "${BLUE}[$ip] Deployando sensores: sensor-$(printf "%02d" $sensor1_id) e sensor-$(printf "%02d" $sensor2_id)...${NC}"
    
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
    echo -e "${CYAN}║${NC}     ${BOLD}DEPLOY DISTRIBUÍDO - LABORATÓRIO${NC}                       ${CYAN}║${NC}"
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
    
    # Mostrar tabela de IDs
    echo -e "${BLUE}📊 Tabela de IDs únicos:${NC}"
    echo "  ┌────────────┬──────────────┬────────────────┬─────────────────┐"
    echo "  │ Máquina    │ Broker       │ Drones         │ Sensores        │"
    echo "  ├────────────┼──────────────┼────────────────┼─────────────────┤"
    printf "  │ %-10s │ %-12s │ drone-01,02    │ sensor-01,02    │\n" "${IPS_LIST[0]}"
    printf "  │ %-10s │ %-12s │ drone-03,04    │ sensor-03,04    │\n" "${IPS_LIST[1]}"
    printf "  │ %-10s │ %-12s │ drone-05,06    │ sensor-05,06    │\n" "${IPS_LIST[2]}"
    printf "  │ %-10s │ %-12s │ drone-07,08    │ sensor-07,08    │\n" "${IPS_LIST[3]}"
    echo "  └────────────┴──────────────┴────────────────┴─────────────────┘"
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
        build_images $ip
        deploy_broker $ip $i "$LAB_IPS_STRING"
        deploy_drones $ip $i
        deploy_sensores $ip $i
        
        echo ""
    done
    
    # Aguardar inicialização
    echo -e "${BLUE}⏳ Aguardando 15 segundos para os brokers se estabilizarem...${NC}"
    sleep 15
    
    # Verificar status final
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📊 STATUS FINAL DOS COMPONENTES${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    for i in "${!IPS_LIST[@]}"; do
        ip=${IPS_LIST[$i]}
        echo -e "${BLUE}=== Máquina $((i+1)): $ip ===${NC}"
        check_status $ip
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
    echo ""
    echo -e "${BLUE}📊 Verificar líder em todos os brokers:${NC}"
    echo "  for ip in ${IPS_LIST[*]}; do echo \"=== \$ip ===\"; ssh $SSH_USER@\$ip 'docker logs broker 2>&1 | grep \"Novo líder eleito\" | tail -1'; done"
    echo ""
    echo -e "${BLUE}🛑 Parar tudo:${NC}"
    echo "  for ip in ${IPS_LIST[*]}; do ssh $SSH_USER@\$ip 'docker rm -f broker drone-01 drone-02 sensor-01 sensor-02'; done"
    echo ""
}

# Executar main com todos os argumentos
main "$@"