#!/bin/bash

# Script para Package de Chaincodes Hyperledger Fabric
# Empacota os chaincodes (token e mission) no formato requerido pelo lifecycle
# Uso: ./scripts/package_chaincodes.sh

set -e

# Cores para output
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
CHAINCODE_VERSION="1.0"

# Argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            CHAINCODE_VERSION="$2"
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
    echo -e "${CYAN}║${NC}     ${BOLD}PACKAGE CHAINCODES - Hyperledger Fabric${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Uso:${NC} $0 [--version VERSION]"
    echo -e "${BLUE}Exemplo:${NC} $0                    # Usa versão 1.0"
    echo -e "${BLUE}Exemplo:${NC} $0 --version 1.1    # Define versão 1.1"
    echo ""
}

# Verificar peer CLI
check_peer_cli() {
    if ! command -v peer &>/dev/null; then
        if [ -f "${PROJECT_ROOT}/bin/peer" ]; then
            export PATH="${PROJECT_ROOT}/bin:$PATH"
            log_success "peer CLI encontrado em bin/"
        else
            log_error "peer CLI não encontrado"
            echo "  Instale Fabric Tools ou execute dentro de um container Docker"
            exit 1
        fi
    fi
    log_success "peer CLI disponível"
}

# Validar chaincode
validate_chaincode() {
    local cc=$1
    local cc_dir="${CHAINCODE_DIR}/${cc}"
    
    if [ ! -d "$cc_dir" ]; then
        log_error "Diretório não encontrado: $cc_dir"
        return 1
    fi
    
    if [ ! -f "${cc_dir}/${cc}_chaincode.go" ] && [ ! -f "${cc_dir}/main.go" ]; then
        log_error "Arquivo Go não encontrado em $cc_dir"
        return 1
    fi
    
    log_success "Chaincode $cc validado"
    return 0
}

# Empacotar chaincode
package_chaincode() {
    local cc=$1
    local version=$2
    local cc_dir="${CHAINCODE_DIR}/${cc}"
    local package_name="${cc}.tar.gz"
    local package_path="${CHAINCODE_DIR}/${package_name}"
    
    echo ""
    log_info "Empacotando: ${BOLD}${cc}${NC} (versão: ${BOLD}${version}${NC})"
    
    if ! validate_chaincode "$cc"; then
        return 1
    fi
    
    # Remover package anterior
    [ -f "$package_path" ] && rm -f "$package_path"
    
    # Executar package dentro do diretório
    (
        cd "$cc_dir" || return 1
        
        if peer lifecycle chaincode package "$package_name" \
            --label="${cc}-${version}" \
            --lang golang \
            --path . &>/dev/null; then
            
            if [ -f "$package_name" ]; then
                mv "$package_name" "${CHAINCODE_DIR}/"
                local size=$(du -h "$package_path" | cut -f1)
                log_success "Package criado: $package_name ($size)"
                return 0
            else
                log_error "Arquivo $package_name não encontrado"
                return 1
            fi
        else
            log_error "Falha ao empacotar $cc"
            return 1
        fi
    ) || return 1
}

# Main
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}     ${BOLD}PACKAGE CHAINCODES - Hyperledger Fabric v2.5.0${NC}       ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "Diretório do projeto: ${BOLD}${PROJECT_ROOT}${NC}"
log_info "Versão dos chaincodes: ${BOLD}${CHAINCODE_VERSION}${NC}"

check_peer_cli

log_info "Iniciando empacotamento..."
echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"

all_success=true
for cc in "${CHAINCODES[@]}"; do
    if ! package_chaincode "$cc" "$CHAINCODE_VERSION"; then
        all_success=false
    fi
done

echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"

# Validação final
echo ""
log_info "Validando packages gerados..."

valid_count=0
for cc in "${CHAINCODES[@]}"; do
    if [ -f "${CHAINCODE_DIR}/${cc}.tar.gz" ]; then
        log_success "${cc}.tar.gz criado com sucesso"
        ((valid_count++))
    else
        log_error "${cc}.tar.gz não encontrado"
    fi
done

echo ""
if [ "$valid_count" -eq "${#CHAINCODES[@]}" ] && [ "$all_success" = true ]; then
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${GREEN}${BOLD}✓ EMPACOTAMENTO CONCLUÍDO COM SUCESSO${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "Próximo passo: docker-compose up -d"
    echo ""
    exit 0
else
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${RED}${BOLD}✗ EMPACOTAMENTO FALHOU${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
