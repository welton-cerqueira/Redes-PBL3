#!/bin/bash

# Script para Install de Chaincodes no Fabric
# Instala e valida chaincodes token e mission nos peers
# Uso: ./scripts/install_chaincodes.sh [--channel CHANNEL]

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configurações
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAINCODE_DIR="${PROJECT_ROOT}/chaincode"
CHAINCODES=("token" "mission")
CHANNEL="canal"
FABRIC_CFG_PATH="${PROJECT_ROOT}/config"

# Argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --channel)
            CHANNEL="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Funções
log_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC}  $1"; }

show_help() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}INSTALL CHAINCODES - Hyperledger Fabric${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Uso:${NC} $0 [--channel CHANNEL]"
    echo -e "${BLUE}Exemplo:${NC} $0                   # Usa canal 'canal'"
    echo -e "${BLUE}Exemplo:${NC} $0 --channel test  # Usa canal 'test'"
    echo ""
}

# Verificar peer CLI
check_peer_cli() {
    if ! command -v peer &>/dev/null; then
        if [ -f "${PROJECT_ROOT}/bin/peer" ]; then
            export PATH="${PROJECT_ROOT}/bin:$PATH"
        else
            log_error "peer CLI não encontrado"
            exit 1
        fi
    fi
    log_success "peer CLI disponível"
}

# Verificar packages
check_packages() {
    log_info "Verificando packages..."
    
    for cc in "${CHAINCODES[@]}"; do
        if [ ! -f "${CHAINCODE_DIR}/${cc}.tar.gz" ]; then
            log_error "Package não encontrado: ${CHAINCODE_DIR}/${cc}.tar.gz"
            echo "  Execute: ./scripts/package_chaincodes.sh"
            exit 1
        fi
        log_success "Package encontrado: ${cc}.tar.gz"
    done
}

# Instalar chaincode
install_chaincode() {
    local cc=$1
    local package="${CHAINCODE_DIR}/${cc}.tar.gz"
    
    echo ""
    log_info "Instalando: ${BOLD}${cc}${NC}"
    
    if peer lifecycle chaincode install "$package" &>/dev/null; then
        log_success "Chaincode instalado: $cc"
        
        # Extrair Package ID
        local pkg_id=$(peer lifecycle chaincode queryinstalled | grep "${cc}" | awk '{print $3}' | cut -d',' -f1 || echo "N/A")
        log_info "  Package ID: $pkg_id"
        
        return 0
    else
        log_error "Falha ao instalar: $cc"
        return 1
    fi
}

# Validar instalação
validate_installation() {
    echo ""
    log_info "Validando instalação..."
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    
    if peer lifecycle chaincode queryinstalled; then
        echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
        log_success "Chaincodes instalados com sucesso"
        return 0
    else
        log_error "Falha ao validar chaincodes"
        return 1
    fi
}

# Main
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}     ${BOLD}INSTALL CHAINCODES - Hyperledger Fabric v2.5.0${NC}        ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "Diretório do projeto: ${BOLD}${PROJECT_ROOT}${NC}"
log_info "Canal: ${BOLD}${CHANNEL}${NC}"
log_info "Fabric Config: ${BOLD}${FABRIC_CFG_PATH}${NC}"

check_peer_cli
check_packages

log_info "Iniciando instalação..."
echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"

all_success=true
for cc in "${CHAINCODES[@]}"; do
    if ! install_chaincode "$cc"; then
        all_success=false
    fi
done

echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"

# Validação e resultado
if validate_installation && [ "$all_success" = true ]; then
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${GREEN}${BOLD}✓ INSTALAÇÃO CONCLUÍDA COM SUCESSO${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "Chaincodes instalados e prontos para aprovação"
    echo ""
    echo -e "${YELLOW}Próximos passos:${NC}"
    echo "  1. Approve para sua organização:"
    echo "     peer lifecycle chaincode approveformyorg --channelID ${CHANNEL} \\"
    echo "       --name token-contract --version 1.0 --package-id <PACKAGE_ID> \\"
    echo "       --sequence 1 --tls --cafile <CA_CERT>"
    echo ""
    echo "  2. Commit da definição:"
    echo "     peer lifecycle chaincode commit --channelID ${CHANNEL} \\"
    echo "       --name token-contract --version 1.0 --sequence 1 \\"
    echo "       --tls --cafile <CA_CERT>"
    echo ""
    exit 0
else
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${RED}${BOLD}✗ INSTALAÇÃO FALHOU${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
