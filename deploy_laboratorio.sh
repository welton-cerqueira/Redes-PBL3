#!/bin/bash

# ============================================================================
# DEPLOY DISTRIBUÍDO COM HYPERLEDGER FABRIC - VERSÃO LABORATÓRIO
# SEM sudo e SEM sshpass (usa SSH normal)
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

# ============================================================================
# CONFIGURAÇÕES PADRÃO
# ============================================================================

SSH_USER="${SSH_USER:-tec502}"
PROJECT_DIR="Redes-PBL3"
REPO_URL="https://github.com/welton-cerqueira/Redes-PBL3.git"
FABRIC_IP=""

declare -a BROKER_IPS=()

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

show_help() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}DEPLOY DISTRIBUÍDO - LABORATÓRIO (SEM SUDO)${NC}                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Uso:${NC} $0 --brokers \"IP1 IP2 IP3 IP4\" [OPÇÕES]"
    echo ""
    echo -e "${BLUE}Opções:${NC}"
    echo "  --brokers \"IP1 IP2 IP3 IP4\"   IPs dos brokers (obrigatório, 4 IPs)"
    echo "  --fabric-ip IP               IP da máquina Fabric (padrão: primeiro broker)"
    echo "  --user USER                  Usuário SSH (padrão: tec502)"
    echo "  --help                       Mostra esta ajuda"
    echo ""
    echo -e "${BLUE}Exemplo:${NC}"
    echo "  $0 --brokers \"172.16.201.1 172.16.201.2 172.16.201.3 172.16.201.4\""
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
# TESTE DE CONEXÃO SSH (sem sshpass)
# ============================================================================

testar_conexao() {
    local ip=$1
    
    # Teste de ping primeiro
    if ! ping -c 1 -W 1 $ip &> /dev/null; then
        return 1
    fi
    
    # Teste SSH (vai pedir senha se não tiver chave)
    ssh -o BatchMode=yes -o ConnectTimeout=5 $SSH_USER@$ip "echo OK" 2>/dev/null
}

# ============================================================================
# EXECUTAR COMANDO SSH (sem sshpass)
# ============================================================================

ssh_cmd() {
    local ip=$1
    local cmd=$2
    
    ssh -o StrictHostKeyChecking=no $SSH_USER@$ip "$cmd"
}

# ============================================================================
# COPIAR ARQUIVO (sem scp com senha)
# ============================================================================

copy_file() {
    local src=$1
    local dst_ip=$2
    local dst_path=$3
    
    scp -o StrictHostKeyChecking=no $src $SSH_USER@$dst_ip:$dst_path
}

# ============================================================================
# SETUP DO REPOSITÓRIO (sem sudo)
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
        go mod tidy 2>/dev/null || true
        go build -o broker ./cmd/broker/ 2>/dev/null || true
        go build -o drone ./cmd/drone/ 2>/dev/null || true
        go build -o sensor ./cmd/sensor/ 2>/dev/null || true
        chmod +x broker drone sensor
    "
    
    ssh_cmd "$ip" "$cmd"
}

# ============================================================================
# DEPLOY DO FABRIC (apenas verificar se está rodando)
# ============================================================================

check_fabric() {
    local ip=$1
    
    print_step "Verificando Hyperledger Fabric em $ip"
    
    local cmd="
        cd ~/fabric-samples/test-network 2>/dev/null && \
        docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'peer|orderer|cli' || \
        echo 'Fabric não está rodando'
    "
    
    ssh_cmd "$ip" "$cmd"
}

# ============================================================================
# DEPLOY DO BROKER
# ============================================================================

deploy_broker() {
    local ip=$1
    local index=$2
    local fabric_ip=$3
    
    local broker_id=$((index + 1))
    local base_port=$((9000 + index * 10))
    
    print_info "[$ip] Deployando broker-$broker_id (porta TCP: $base_port)"
    
    # Construir lista de peers
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
    
    # Configurar drones
    local drone1_id=$((index * 2 + 1))
    local drone2_id=$((index * 2 + 2))
    local drones="drone-$(printf "%02d" $drone1_id)=${ip}:$((9100 + drone1_id)),drone-$(printf "%02d" $drone2_id)=${ip}:$((9100 + drone2_id))"
    
    local cmd="
        cd ~/$PROJECT_DIR
        
        # Matar processos antigos
        pkill -f './broker' 2>/dev/null || true
        sleep 1
        
        # Executar broker
        nohup ./broker \\
            -id=broker-${broker_id} \\
            -porta-tcp=:${base_port} \\
            -porta-udp=:$(($base_port+1)) \\
            -porta-ctrl=:$(($base_port+2)) \\
            -drones=\"${drones}\" \\
            -peers=\"${peers}\" \\
            -enable-ledger=true \\
            -ledger-mock=false \\
            -ledger-gateway=\"http://${fabric_ip}:7051\" \\
            > /tmp/broker-${broker_id}.log 2>&1 &
        
        sleep 2
        echo \"Broker-${broker_id} iniciado (PID: \$(pgrep -f './broker' | head -1))\" 2>/dev/null || echo \"Broker-${broker_id} iniciado\"
    "
    
    ssh_cmd "$ip" "$cmd"
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
    
    print_info "[$ip] Deployando drones: drone-$(printf "%02d" $drone1_id) e drone-$(printf "%02d" $drone2_id)"
    
    local cmd="
        cd ~/$PROJECT_DIR
        
        pkill -f './drone' 2>/dev/null || true
        sleep 1
        
        nohup ./drone -id=drone-$(printf "%02d" $drone1_id) -port=:${drone1_port} > /tmp/drone-${drone1_id}.log 2>&1 &
        nohup ./drone -id=drone-$(printf "%02d" $drone2_id) -port=:${drone2_port} > /tmp/drone-${drone2_id}.log 2>&1 &
        
        echo \"Drones iniciados\"
    "
    
    ssh_cmd "$ip" "$cmd"
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
        sleep 1
        
        nohup ./sensor -id=sensor-$(printf "%02d" $sensor1_id) -tipo=$tipo1 -local='$local1' -brokers=${ip}:${sensor_port} > /tmp/sensor-${sensor1_id}.log 2>&1 &
        nohup ./sensor -id=sensor-$(printf "%02d" $sensor2_id) -tipo=$tipo2 -local='$local2' -brokers=${ip}:${sensor_port} > /tmp/sensor-${sensor2_id}.log 2>&1 &
        
        echo \"Sensores iniciados\"
    "
    
    ssh_cmd "$ip" "$cmd"
}

# ============================================================================
# VERIFICAÇÃO DE STATUS
# ============================================================================

check_status() {
    local ip=$1
    
    echo -e "${BLUE}[$ip] Status:${NC}"
    
    local cmd="
        echo -n '  Broker: ' && pgrep -f './broker' > /dev/null 2>&1 && echo '✅ Rodando' || echo '❌ Parado'
        echo -n '  Drones: ' && pgrep -f './drone' > /dev/null 2>&1 && echo '✅ Rodando' || echo '❌ Parado'
        echo -n '  Sensores: ' && pgrep -f './sensor' > /dev/null 2>&1 && echo '✅ Rodando' || echo '❌ Parado'
    "
    
    ssh_cmd "$ip" "$cmd"
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
        show_help
        exit 1
    fi
    
    # Se fabric-ip não foi especificado, usa o primeiro broker
    if [ -z "$FABRIC_IP" ]; then
        FABRIC_IP="${BROKER_IPS[0]}"
        print_info "Fabric IP não especificado, usando: $FABRIC_IP"
    fi
    
    print_banner
    
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
    echo -e "${YELLOW}   O Hyperledger Fabric será usado em: $FABRIC_IP${NC}"
    echo ""
    read -p "Deseja continuar? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}Deploy cancelado.${NC}"
        exit 0
    fi
    
    # Testar conexões SSH
    print_step "Testando conexões SSH (pode pedir senha)"
    
    for ip in "${BROKER_IPS[@]}"; do
        echo -n "  Testando $ip... "
        if ssh -o BatchMode=yes -o ConnectTimeout=5 $SSH_USER@$ip "echo OK" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}Será solicitada a senha${NC}"
            if ! ssh -o ConnectTimeout=5 $SSH_USER@$ip "echo OK" 2>/dev/null; then
                print_error "$ip - Falha na conexão"
                exit 1
            fi
        fi
    done
    
    # ========================================================================
    # 1. SETUP DO REPOSITÓRIO
    # ========================================================================
    print_step "1. Setup do repositório nas máquinas"
    
    for ip in "${BROKER_IPS[@]}"; do
        setup_repository $ip
    done
    
    # ========================================================================
    # 2. VERIFICAR FABRIC
    # ========================================================================
    print_step "2. Verificando Hyperledger Fabric"
    check_fabric $FABRIC_IP
    
    # ========================================================================
    # 3. DEPLOY DOS BROKERS, DRONES E SENSORES
    # ========================================================================
    print_step "3. Deploy dos Brokers, Drones e Sensores"
    
    for i in "${!BROKER_IPS[@]}"; do
        ip=${BROKER_IPS[$i]}
        
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}🚀 Configurando máquina $((i+1)): $ip${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
        
        deploy_broker $ip $i "$FABRIC_IP"
        deploy_drones $ip $i
        deploy_sensores $ip $i
    done
    
    # ========================================================================
    # 4. AGUARDAR ESTABILIZAÇÃO
    # ========================================================================
    print_step "4. Aguardando estabilização do sistema"
    echo -e "${BLUE}⏳ Aguardando 15 segundos...${NC}"
    sleep 15
    
    # ========================================================================
    # 5. VERIFICAR STATUS
    # ========================================================================
    print_step "5. Verificando status do sistema"
    echo ""
    
    for i in "${!BROKER_IPS[@]}"; do
        ip=${BROKER_IPS[$i]}
        echo -e "${BLUE}=== Máquina $((i+1)): $ip ===${NC}"
        check_status $ip
        echo ""
    done
    
    # ========================================================================
    # 6. RESUMO FINAL
    # ========================================================================
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}DEPLOY CONCLUÍDO COM SUCESSO!${NC}                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📋 Componentes do sistema:${NC}"
    echo -e "  ${GREEN}✅${NC} 4 Brokers distribuídos"
    echo -e "  ${GREEN}✅${NC} 8 Drones (2 por broker)"
    echo -e "  ${GREEN}✅${NC} 8 Sensores (2 por broker)"
    echo ""
    echo -e "${CYAN}📋 Comandos úteis:${NC}"
    echo ""
    echo -e "  ${YELLOW}Ver logs de um broker:${NC}"
    echo "    ssh $SSH_USER@<ip> 'tail -f /tmp/broker-1.log'"
    echo ""
    echo -e "  ${YELLOW}Parar todos os serviços:${NC}"
    echo "    for ip in ${BROKER_IPS[*]}; do ssh $SSH_USER@\$ip 'pkill -f \"./broker\"; pkill -f \"./drone\"; pkill -f \"./sensor\"'; done"
    echo ""
    echo -e "  ${YELLOW}Verificar líder eleito:${NC}"
    echo "    for ip in ${BROKER_IPS[*]}; do echo \"=== \$ip ===\"; ssh $SSH_USER@\$ip 'tail -5 /tmp/broker-1.log | grep -E \"lider|líder\"'; done"
    echo ""
}

# Executar
main "$@"
