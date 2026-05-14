#!/bin/sh
set -e

# Se argumentos forem passados (via docker-compose command), executa o broker diretamente
if [ $# -gt 0 ]; then
    echo "Executando broker com argumentos fornecidos: $@"
    exec /root/broker "$@"
fi

# Modo automático com LAB_IPS (para deploy em máquinas reais)
if [ -z "$LAB_IPS" ]; then
    echo "ERRO: Variável LAB_IPS não definida e nenhum argumento fornecido."
    echo "Uso: Defina LAB_IPS ou passe argumentos diretamente"
    exit 1
fi

# Função para obter IP da interface correta (compatível com BusyBox)
obter_ip_laboratorio() {
    # Tenta obter IP via BROKER_IP manual (prioridade máxima)
    if [ -n "$BROKER_IP" ]; then
        echo "$BROKER_IP"
        return 0
    fi
    
    # Tenta obter IP da interface eth0 (comum em laboratório)
    eth0_ip=$(ip -4 addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$eth0_ip" ]; then
        echo "$eth0_ip"
        return 0
    fi
    
    # Tenta obter IP da interface enp* ou ens* (nomenclatura moderna)
    for iface in $(ip -4 addr show | grep -E '^[0-9]+: (enp|ens)' | awk -F': ' '{print $2}'); do
        ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$ip_addr" ]; then
            echo "$ip_addr"
            return 0
        fi
    done
    
    # Fallback: pega o IP da rota padrão (mais confiável)
    route_ip=$(ip -4 route get 1 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}')
    if [ -n "$route_ip" ]; then
        echo "$route_ip"
        return 0
    fi
    
    # Último fallback: pega o primeiro IP que não seja loopback
    first_ip=$(ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
    if [ -n "$first_ip" ]; then
        echo "$first_ip"
        return 0
    fi
    
    return 1
}

# Obtém o IP local usando a função acima
MY_IP=$(obter_ip_laboratorio)

if [ -z "$MY_IP" ]; then
    echo "ERRO: Não foi possível detectar IP local."
    echo "Alternativas:"
    echo "  1. Defina BROKER_IP manualmente: docker run -e BROKER_IP=172.16.201.X ..."
    echo "  2. Verifique as interfaces de rede: ip addr show"
    exit 1
fi

echo "IP local detectado: $MY_IP"

# Lista de IPs da LAB_IPS (separadores: espaço, vírgula, ponto e vírgula)
# Filtra apenas IPs da faixa 172.16.201.x (rede do laboratório)
LAB_IPS_LIST=""
for ip in $(echo "$LAB_IPS" | tr ',;' ' '); do
    # Aceita apenas IPs da rede 172.16.201.x (rede do LADICA)
    case "$ip" in
        172.16.201.*)
            LAB_IPS_LIST="$LAB_IPS_LIST $ip"
            ;;
        *)
            echo "AVISO: Ignorando IP fora da rede do laboratório: $ip"
            ;;
    esac
done

# Remove espaço inicial
LAB_IPS_LIST=$(echo "$LAB_IPS_LIST" | sed 's/^ //')

if [ -z "$LAB_IPS_LIST" ]; then
    echo "ERRO: Nenhum IP válido na rede 172.16.201.x"
    echo "IPs fornecidos: $LAB_IPS"
    exit 1
fi

echo "IPs da rede do laboratório: $LAB_IPS_LIST"

# Gera ID baseado no último octeto do IP
octeto=$(echo "$MY_IP" | cut -d. -f4)
BROKER_ID="broker-${octeto}"

# Calcula portas baseadas no último octeto para evitar conflitos
# Fórmula: base = 9000 + (octeto - 1) * 10
base=$((9000 + (octeto - 1) * 10))
TCP_PORT=":${base}"
UDP_PORT=":$(($base+1))"
CTRL_PORT=":$(($base+2))"

echo "Configuração: ID=$BROKER_ID TCP=$TCP_PORT UDP=$UDP_PORT CTRL=$CTRL_PORT"

# Constrói peers a partir dos LAB_IPS válidos, excluindo o próprio IP
PEERS_ARRAY=""
for ip in $LAB_IPS_LIST; do
    # Pula o próprio IP
    if [ "$ip" = "$MY_IP" ]; then
        continue
    fi
    
    oct=$(echo "$ip" | cut -d. -f4)
    base_peer=$((9000 + (oct - 1) * 10))
    tcp="${ip}:${base_peer}"
    udp="${ip}:$(($base_peer+1))"
    id="broker-${oct}"
    
    if [ -n "$PEERS_ARRAY" ]; then
        PEERS_ARRAY="${PEERS_ARRAY},${id},${tcp},${udp}"
    else
        PEERS_ARRAY="${id},${tcp},${udp}"
    fi
    echo "Peer adicionado: $id em $tcp (UDP: $udp)"
done

if [ -z "$PEERS_ARRAY" ]; then
    echo "AVISO: Nenhum peer encontrado (apenas este broker na rede?)"
fi

echo "String de peers: $PEERS_ARRAY"

# Executa o broker com os parâmetros corretos
exec /root/broker \
    -id="$BROKER_ID" \
    -porta-tcp="$TCP_PORT" \
    -porta-udp="$UDP_PORT" \
    -porta-ctrl="$CTRL_PORT" \
    -peers="$PEERS_ARRAY"