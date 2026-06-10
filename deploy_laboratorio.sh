#!/bin/bash

# ============================================================================
# DEPLOY DISTRIBUÍDO COM HYPERLEDGER FABRIC
# Sistema de Brokers + Blockchain em Múltiplas Máquinas
# ============================================================================

set -e

# Cores
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

SSH_USER="${SSH_USER:-tec502}"
SSH_PASS="${SSH_PASS:-}"
PROJECT_DIR="Redes-PBL3"
REPO_URL="https://github.com/welton-cerqueira/SISTEMA-DISTRIBUIDO-REDES2.git"
FABRIC_IP=""  # IP da máquina que rodará o Fabric (a primeira da lista)

# Arrays
declare -a BROKER_IPS=()
declare -a ALL_IPS=()

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

show_help() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}DEPLOY DISTRIBUÍDO COM HYPERLEDGER FABRIC${NC}                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Uso:${NC} $0 --brokers \"IP1 IP2 IP3 IP4\" [OPÇÕES]"
    echo ""
    echo -e "${BLUE}Opções:${NC}"
    echo "  --brokers \"IP1 IP2 IP3 IP4\"   IPs dos brokers (obrigatório, 4 IPs)"
    echo "  --fabric-ip IP               IP da máquina Fabric (padrão: primeiro broker)"
    echo "  --user USER                  Usuário SSH (padrão: tec502)"
    echo "  --pass PASS                  Senha SSH"
    echo "  --help                       Mostra esta ajuda"
    echo ""
    echo -e "${BLUE}Exemplo:${NC}"
    echo "  $0 --brokers \"172.16.103.1 172.16.103.2 172.16.103.3 172.16.103.4\""
    echo "  $0 --brokers \"...\" --fabric-ip 172.16.103.1"
    echo ""
}

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}SISTEMA DISTRIBUÍDO DE BROKERS + HYPERLEDGER FABRIC${NC}                 ${CYAN}║${NC}"
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

print_info() {
    echo -e "${CYAN}ℹ️${NC} $1"
}

# ============================================================================
# VERIFICAÇÃO DE DEPENDÊNCIAS
# ============================================================================

check_dependencies() {
    local deps_ok=true
    
    print_step "Verificando dependências"
    
    for cmd in ssh ping docker; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Comando não encontrado: $cmd"
            deps_ok=false
        fi
    done
    
    if [ -n "$SSH_PASS" ] && ! command -v sshpass &> /dev/null; then
        print_error "sshpass não encontrado. Instale com: sudo apt install sshpass"
        deps_ok=false
    fi
    
    if [ "$deps_ok" = false ]; then
        exit 1
    fi
    
    print_success "Todas as dependências OK"
}

# ============================================================================
# TESTE DE CONEXÃO
# ============================================================================

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

# ============================================================================
# DEPLOY DO FABRIC (em uma máquina)
# ============================================================================

deploy_fabric() {
    local ip=$1
    
    print_step "Deploy do Hyperledger Fabric em $ip"
    
    # Copiar script start_fabric.sh
    local cmd="
        mkdir -p ~/$PROJECT_DIR/scripts
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
            ~/Redes-PBL3/scripts/start_fabric.sh $SSH_USER@$ip:~/$PROJECT_DIR/scripts/
        
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "
            cd ~/$PROJECT_DIR
            chmod +x scripts/start_fabric.sh
            
            echo '=== Iniciando Fabric ==='
            ./scripts/start_fabric.sh
        "
    else
        scp -o StrictHostKeyChecking=no \
            ~/Redes-PBL3/scripts/start_fabric.sh $SSH_USER@$ip:~/$PROJECT_DIR/scripts/
        
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "
            cd ~/$PROJECT_DIR
            chmod +x scripts/start_fabric.sh
            
            echo '=== Iniciando Fabric ==='
            ./scripts/start_fabric.sh
        "
    fi
    
    print_success "Fabric deployado em $ip"
}

# ============================================================================
# SETUP DO REPOSITÓRIO
# ============================================================================

setup_repository() {
    local ip=$1
    
    print_info "[$ip] Preparando repositório..."
    
    local cmd="
        if [ ! -d ~/$PROJECT_DIR ]; then
            git clone $REPO_URL ~/$PROJECT_DIR
        else
            cd ~/$PROJECT_DIR && git pull
        fi
        cd ~/$PROJECT_DIR
        go mod tidy
        go build -o broker ./cmd/broker/
        go build -o drone ./cmd/drone/
        go build -o sensor ./cmd/sensor/
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# ============================================================================
# DEPLOY DO BROKER
# ============================================================================

deploy_broker() {
    local ip=$1
    local index=$2
    local broker_ip=$3
    
    local broker_id=$((index + 1))
    local base_port=$((9000 + index * 10))
    local tcp_port=":${base_port}"
    local udp_port=":$(($base_port+1))"
    local sensor_port=":$(($base_port+2))"
    
    print_info "[$ip] Deployando broker-$broker_id"
    
    # Construir lista de peers (todos os outros brokers)
    local peers=""
    for i in "${!BROKER_IPS[@]}"; do
        local peer_idx=$((i + 1))
        if [ $peer_idx -ne $broker_id ]; then
            local peer_base=$((9000 + i * 10))
            local peer_ip="${BROKER_IPS[$i]}"
            if [ -n "$peers" ]; then
                peers="${peers};"
            fi
            peers="${peers}broker-${peer_idx},${peer_ip}:${peer_base},${peer_ip}:$(($peer_base+1))"
        fi
    done
    
    # Configurar drones (2 por broker)
    local drone1_id=$((index * 2 + 1))
    local drone2_id=$((index * 2 + 2))
    local drones="drone-$(printf "%02d" $drone1_id)=${ip}:$((9100 + drone1_id)),drone-$(printf "%02d" $drone2_id)=${ip}:$((9100 + drone2_id))"
    
    local cmd="
        cd ~/$PROJECT_DIR
        
        # Matar processos antigos
        pkill -f './broker' 2>/dev/null || true
        
        # Executar broker
        nohup ./broker \\
            -id=broker-${broker_id} \\
            -porta-tcp=${tcp_port} \\
            -porta-udp=${udp_port} \\
            -porta-ctrl=${sensor_port} \\
            -drones=\"${drones}\" \\
            -peers=\"${peers}\" \\
            -enable-ledger=true \\
            -ledger-mock=false \\
            -ledger-gateway=\"http://${FABRIC_IP}:7051\" \\
            > /tmp/broker-${broker_id}.log 2>&1 &
        
        echo \"Broker-${broker_id} iniciado (PID: \$!)\"
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# ============================================================================
# DEPLOY DOS DRONES
# ============================================================================

deploy_drones() {
    local ip=$1
    local index=$2
    
    local drone1_id=$((index * 2 + 1))
    local drone2_id=$((index * 2 + 2))
    local drone1_port=$((9100 + drone1_id))
    local drone2_port=$((9100 + drone2_id))
    
    print_info "[$ip] Deployando drones: drone-$(printf "%02d" $drone1_id) (porta $drone1_port) e drone-$(printf "%02d" $drone2_id) (porta $drone2_port)"
    
    local cmd="
        cd ~/$PROJECT_DIR
        
        pkill -f './drone' 2>/dev/null || true
        
        nohup ./drone -id=drone-$(printf "%02d" $drone1_id) -port=:${drone1_port} > /tmp/drone-${drone1_id}.log 2>&1 &
        nohup ./drone -id=drone-$(printf "%02d" $drone2_id) -port=:${drone2_port} > /tmp/drone-${drone2_id}.log 2>&1 &
        
        echo \"Drones iniciados\"
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# ============================================================================
# DEPLOY DOS SENSORES
# ============================================================================

deploy_sensores() {
    local ip=$1
    local index=$2
    
    local sensor1_id=$((index * 2 + 1))
    local sensor2_id=$((index * 2 + 2))
    local sensor_port=$((9002 + index * 10))
    
    print_info "[$ip] Deployando sensores: sensor-$(printf "%02d" $sensor1_id) e sensor-$(printf "%02d" $sensor2_id)"
    
    # Tipos e localizações
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
        cd ~/$PROJECT_DIR
        
        pkill -f './sensor' 2>/dev/null || true
        
        nohup ./sensor -id=sensor-$(printf "%02d" $sensor1_id) -tipo=$tipo1 -local='$local1' -brokers=${ip}:${sensor_port} > /tmp/sensor-${sensor1_id}.log 2>&1 &
        nohup ./sensor -id=sensor-$(printf "%02d" $sensor2_id) -tipo=$tipo2 -local='$local2' -brokers=${ip}:${sensor_port} > /tmp/sensor-${sensor2_id}.log 2>&1 &
        
        echo \"Sensores iniciados\"
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# ============================================================================
# VERIFICAÇÃO DE STATUS
# ============================================================================

check_status() {
    local ip=$1
    
    echo -e "${BLUE}[$ip] Status:${NC}"
    
    local cmd="
        echo -n '  Broker: ' && pgrep -f './broker' > /dev/null && echo '✅ Rodando' || echo '❌ Parado'
        echo -n '  Drones: ' && pgrep -f './drone' > /dev/null && echo '✅ Rodando' || echo '❌ Parado'
        echo -n '  Sensores: ' && pgrep -f './sensor' > /dev/null && echo '✅ Rodando' || echo '❌ Parado'
    "
    
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
    fi
}

# ============================================================================
# FUNÇÃO PRINCIPAL
# ============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --brokers)
                shift
                BROKER_IPS=($1)
                shift
                ;;
            --fabric-ip)
                shift
                FABRIC_IP=$1
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
                print_error "Opção desconhecida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validação
    if [ ${#BROKER_IPS[@]} -ne 4 ]; then
        print_error "É necessário exatamente 4 IPs para os brokers!"
        echo -e "${YELLOW}Você forneceu ${#BROKER_IPS[@]} IP(s): ${BROKER_IPS[*]}${NC}"
        show_help
        exit 1
    fi
    
    # Se fabric-ip não foi especificado, usa o primeiro broker
    if [ -z "$FABRIC_IP" ]; then
        FABRIC_IP="${BROKER_IPS[0]}"
        print_info "Fabric IP não especificado, usando: $FABRIC_IP"
    fi
    
    print_banner
    
    # Verificar dependências na máquina local
    check_dependencies
    
    # Mostrar configuração
    echo ""
    echo -e "${BLUE}📋 Configuração do deploy:${NC}"
    echo -e "  Usuário SSH: ${GREEN}$SSH_USER${NC}"
    echo -e "  Fabric IP: ${GREEN}$FABRIC_IP${NC}"
    echo -e "  Brokers: ${GREEN}${BROKER_IPS[*]}${NC}"
    echo ""
    
    # Tabela de IDs
    echo -e "${BLUE}📊 Tabela de IDs únicos:${NC}"
    echo "  ┌────────────────┬──────────────┬────────────────┬─────────────────┐"
    echo "  │ Máquina        │ Broker       │ Drones         │ Sensores        │"
    echo "  ├────────────────┼──────────────┼────────────────┼─────────────────┤"
    printf "  │ %-14s │ %-12s │ drone-01,02    │ sensor-01,02    │\n" "${BROKER_IPS[0]}"
    printf "  │ %-14s │ %-12s │ drone-03,04    │ sensor-03,04    │\n" "${BROKER_IPS[1]}"
    printf "  │ %-14s │ %-12s │ drone-05,06    │ sensor-05,06    │\n" "${BROKER_IPS[2]}"
    printf "  │ %-14s │ %-12s │ drone-07,08    │ sensor-07,08    │\n" "${BROKER_IPS[3]}"
    echo "  └────────────────┴──────────────┴────────────────┴─────────────────┘"
    echo ""
    
    # Confirmar deploy
    echo -e "${YELLOW}⚠️  ATENÇÃO: O deploy será feito nas máquinas acima!${NC}"
    echo -e "${YELLOW}   O Hyperledger Fabric será instalado em: $FABRIC_IP${NC}"
    echo ""
    read -p "Deseja continuar? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}Deploy cancelado.${NC}"
        exit 0
    fi
    
    # Testar conexões SSH
    print_step "Testando conexões SSH"
    ALL_IPS=("${BROKER_IPS[@]}")
    ALL_IPS+=("$FABRIC_IP")
    
    for ip in $(echo "${ALL_IPS[@]}" | tr ' ' '\n' | sort -u); do
        if testar_conexao $ip; then
            print_success "$ip - OK"
        else
            print_error "$ip - Falha na conexão"
            exit 1
        fi
    done
    
    # ========================================================================
    # 1. DEPLOY DO FABRIC
    # ========================================================================
    print_step "1. Deploy do Hyperledger Fabric"
    
    # Primeiro, garantir que o repositório existe na máquina Fabric
    setup_repository $FABRIC_IP
    
    # Deploy do Fabric
    deploy_fabric $FABRIC_IP
    
    # ========================================================================
    # 2. DEPLOY DOS BROKERS, DRONES E SENSORES
    # ========================================================================
    print_step "2. Deploy dos Brokers, Drones e Sensores"
    
    for i in "${!BROKER_IPS[@]}"; do
        ip=${BROKER_IPS[$i]}
        
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}🚀 Configurando máquina $((i+1)): $ip${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        
        setup_repository $ip
        deploy_broker $ip $i "$FABRIC_IP"
        deploy_drones $ip $i
        deploy_sensores $ip $i
    done
    
    # ========================================================================
    # 3. AGUARDAR ESTABILIZAÇÃO
    # ========================================================================
    print_step "3. Aguardando estabilização do sistema"
    echo -e "${BLUE}⏳ Aguardando 15 segundos...${NC}"
    sleep 15
    
    # ========================================================================
    # 4. VERIFICAR STATUS
    # ========================================================================
    print_step "4. Verificando status do sistema"
    echo ""
    
    for i in "${!BROKER_IPS[@]}"; do
        ip=${BROKER_IPS[$i]}
        echo -e "${BLUE}=== Máquina $((i+1)): $ip ===${NC}"
        check_status $ip
        echo ""
    done
    
    # ========================================================================
    # 5. VERIFICAR LÍDER ELEITO
    # ========================================================================
    print_step "5. Verificando líder eleito"
    
    local leader_ip="${BROKER_IPS[0]}"
    echo -e "${BLUE}Consultando broker em $leader_ip...${NC}"
    
    local cmd="tail -20 /tmp/broker-1.log | grep 'Novo líder eleito' | tail -1"
    if [ -n "$SSH_PASS" ]; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$leader_ip "$cmd"
    else
        ssh -o StrictHostKeyChecking=no $SSH_USER@$leader_ip "$cmd"
    fi
    
    # ========================================================================
    # 6. RESUMO FINAL
    # ========================================================================
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}DEPLOY CONCLUÍDO COM SUCESSO!${NC}                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📋 Componentes do sistema:${NC}"
    echo -e "  ${GREEN}✅${NC} Hyperledger Fabric em: ${FABRIC_IP}"
    echo -e "  ${GREEN}✅${NC} 4 Brokers distribuídos"
    echo -e "  ${GREEN}✅${NC} 8 Drones (2 por broker)"
    echo -e "  ${GREEN}✅${NC} 8 Sensores (2 por broker)"
    echo ""
    echo -e "${CYAN}📋 Comandos úteis:${NC}"
    echo ""
    echo -e "  ${YELLOW}Ver logs do Fabric:${NC}"
    echo "    ssh $SSH_USER@$FABRIC_IP 'docker exec cli peer chaincode query -C ormuz-channel -n mission -c \"{\\\"Args\\\":[\\\"GetMissionSummary\\\"]}\"'"
    echo ""
    echo -e "  ${YELLOW}Ver logs de um broker:${NC}"
    echo "    ssh $SSH_USER@<ip> 'tail -f /tmp/broker-1.log'"
    echo ""
    echo -e "  ${YELLOW}Parar todos os serviços:${NC}"
    echo "    for ip in ${BROKER_IPS[*]}; do ssh $SSH_USER@\$ip 'pkill -f \"./broker\"; pkill -f \"./drone\"; pkill -f \"./sensor\"'; done"
    echo "    ssh $SSH_USER@$FABRIC_IP 'cd ~/fabric-samples/test-network && ./network.sh down'"
    echo ""
    echo -e "  ${YELLOW}Verificar líder eleito:${NC}"
    echo "    for ip in ${BROKER_IPS[*]}; do echo \"=== \$ip ===\"; ssh $SSH_USER@\$ip 'tail -5 /tmp/broker-1.log | grep \"líder\"'; done"
    echo ""
}

# Executar
main "$@"
