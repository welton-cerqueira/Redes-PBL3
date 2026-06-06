// pkg/tipos/tipos.go
package tipos

import (
	"fmt"
	"time"
)

// Mensagem representa uma mensagem trocada entre brokers
type Mensagem struct {
	Tipo            string      `json:"tipo"`
	OrigemID        string      `json:"origem_id"`
	DestinoID       string      `json:"destino_id"`
	Dados           interface{} `json:"dados"`
	CarimboTempo    time.Time   `json:"carimbo_tempo"`
	NumeroSequencia uint64      `json:"numero_sequencia"`
}

// EstadoBroker representa o estado de um broker
type EstadoBroker struct {
	ID                string             `json:"id"`
	LiderAtual        string             `json:"lider_atual"`
	Vizinhos          map[string]Vizinho `json:"vizinhos"`
	Recursos          map[string]Recurso `json:"recursos"`
	UltimaAtualizacao time.Time          `json:"ultima_atualizacao"`
	Versao            uint64             `json:"versao"`
}

// Vizinho representa um broker conhecido
type Vizinho struct {
	ID              string    `json:"id"`
	EnderecoTCP     string    `json:"endereco_tcp"`
	EnderecoUDP     string    `json:"endereco_udp"`
	UltimoBatimento time.Time `json:"ultimo_batimento"`
	Ativo           bool      `json:"ativo"`
	VersaoEstado    uint64    `json:"versao_estado"`
}

// Recurso representa um recurso gerenciado pelo sistema
type Recurso struct {
	ID             string    `json:"id"`
	Nome           string    `json:"nome"`
	Tipo           string    `json:"tipo"`
	Estado         string    `json:"estado"` // disponivel, em_uso, manutencao
	BrokerAtual    string    `json:"broker_atual"`
	BloqueadoPor   string    `json:"bloqueado_por"`   // ID do broker que tem o lock
	DonoRequisicao string    `json:"dono_requisicao"` // ID da requisicao que usou
	UltimoAcesso   time.Time `json:"ultimo_acesso"`
	Versao         uint64    `json:"versao"`
}

// ============================================================================
// REQUISICAO - MODIFICADO COM CAMPOS PARA LEDGER
// ============================================================================

// Requisicao representa uma requisicao no sistema
type Requisicao struct {
	ID               string        `json:"id"`
	Tipo             string        `json:"tipo"`
	BrokerOrigem     string        `json:"broker_origem"`
	RecursoID        string        `json:"recurso_id"`
	Dados            interface{}   `json:"dados"`
	Estado           string        `json:"estado"` // pendente, concluido, em_andamento, falhou
	CarimboTempo     time.Time     `json:"carimbo_tempo"`
	Prioridade       int           `json:"prioridade"`       // 1=baixa, 5=alta
	GrauCriticidade  int           `json:"grau_criticidade"` // 1-5, onde 5 é mais crítico
	Tentativas       int           `json:"tentativas"`
	TimestampEntrada time.Time     `json:"timestamp_entrada"` // Quando entrou na fila
	SetorID          string        `json:"setor_id"`          // Setor que fez a requisição
	Timeout          time.Duration `json:"timeout"`           // Tempo máximo para atendimento

	// 🔴 NOVO: Campos para integração com Blockchain/Ledger
	EscrowID    string `json:"escrow_id,omitempty"`    // ID do escrow na blockchain
	LaudoHash   string `json:"laudo_hash,omitempty"`   // Hash do laudo da missão (Merkle root)
	LaudoCID    string `json:"laudo_cid,omitempty"`    // IPFS CID do laudo completo
	Signature   string `json:"signature,omitempty"`    // Assinatura digital do drone
	PublicKey   string `json:"public_key,omitempty"`   // Chave pública do drone
	CreditsCost int    `json:"credits_cost,omitempty"` // Créditos gastos na missão
	LedgerTXID  string `json:"ledger_txid,omitempty"`  // Transaction ID da blockchain
}

// ============================================================================
// NOVOS TIPOS PARA DRONE MISSION
// ============================================================================

// DroneMission representa uma missão atribuída a um drone (para rastreamento)
type DroneMission struct {
	MissionID    string    `json:"missionId"`
	DroneID      string    `json:"droneId"`
	BrokerID     string    `json:"brokerId"`
	CompanyID    string    `json:"companyId"`
	StartTime    time.Time `json:"startTime"`
	EndTime      time.Time `json:"endTime"`
	Status       string    `json:"status"` // pending, in_progress, completed, failed
	LaudoHash    string    `json:"laudoHash"`
	LaudoCID     string    `json:"laudoCid"`
	Signature    string    `json:"signature"`
	PublicKey    string    `json:"publicKey"`
	EventType    string    `json:"eventType"`
	CreditsSpent int       `json:"creditsSpent"`
	LedgerTXID   string    `json:"ledgerTxId"`
}

// Resposta representa uma resposta a uma requisicao
type Resposta struct {
	RequisicaoID string      `json:"requisicao_id"`
	Sucesso      bool        `json:"sucesso"`
	Dados        interface{} `json:"dados"`
	Erro         string      `json:"erro,omitempty"`
	CarimboTempo time.Time   `json:"carimbo_tempo"`
}

// SensorData representa os dados enviados por um sensor
type SensorData struct {
	ID           string    `json:"id"`
	Tipo         string    `json:"tipo"` // temperatura, pressao, movimento
	Valor        float64   `json:"valor"`
	Localizacao  string    `json:"localizacao"`
	CarimboTempo time.Time `json:"carimbo_tempo"`
	SetorID      string    `json:"setor_id"`
}

// Sensor representa um dispositivo sensor conectado ao sistema
type Sensor struct {
	ID            string    `json:"id"`
	SetorID       string    `json:"setor_id"`
	EnderecoTCP   string    `json:"endereco_tcp"` // usado para callback se necessário
	Tipo          string    `json:"tipo"`         // radar, boia, etc
	Localizacao   string    `json:"localizacao"`
	Conectado     bool      `json:"conectado"`
	UltimaLeitura time.Time `json:"ultima_leitura"`
}

// EventoSensor representa um evento crítico detectado por um sensor
type EventoSensor struct {
	ID           string      `json:"id"`
	TipoEvento   string      `json:"tipo_evento"` // BLOQUEIO_PARCIAL, EMBARCACAO_DERIVA, etc
	SensorID     string      `json:"sensor_id"`
	SetorID      string      `json:"setor_id"`
	Gravidade    int         `json:"gravidade"` // 1-5, onde 5 é mais crítico
	Descricao    string      `json:"descricao"`
	DadosRaw     interface{} `json:"dados_raw"`
	CarimboTempo time.Time   `json:"carimbo_tempo"`
	Processado   bool        `json:"processado"`
}

// MensagemDescoberta representa uma mensagem de descoberta de novos brokers
type MensagemDescoberta struct {
	Tipo         string     `json:"tipo"` // "DESCOBERTA", "ANUNCIO_NOVO_BROKER"
	OrigemID     string     `json:"origem_id"`
	BrokerInfo   BrokerInfo `json:"broker_info"`
	CarimboTempo time.Time  `json:"carimbo_tempo"`
}

// BrokerInfo contém informações de um broker para descoberta
type BrokerInfo struct {
	ID            string `json:"id"`
	EnderecoTCP   string `json:"endereco_tcp"`
	EnderecoUDP   string `json:"endereco_udp"`
	PortaControle string `json:"porta_controle"`
}

// ============================================================================
// FUNÇÕES AUXILIARES (existentes e novas)
// ============================================================================

// NovaRequisicao cria uma nova requisição com valores padrão
func NovaRequisicao(tipo, brokerOrigem, recursoID string, prioridade, criticidade int) *Requisicao {
	return &Requisicao{
		ID:               fmt.Sprintf("req-%d-%d", time.Now().UnixNano(), prioridade),
		Tipo:             tipo,
		BrokerOrigem:     brokerOrigem,
		RecursoID:        recursoID,
		Estado:           "pendente",
		CarimboTempo:     time.Now(),
		Prioridade:       prioridade,
		GrauCriticidade:  criticidade,
		Tentativas:       0,
		TimestampEntrada: time.Now(),
		Timeout:          30 * time.Second,
		// 🔴 Campos ledger inicializados com zero/empty
		CreditsCost: 0,
	}
}

// 🔴 NOVA FUNÇÃO: NovaRequisicaoComLedger cria requisição com custo de créditos
func NovaRequisicaoComLedger(tipo, brokerOrigem, recursoID string, prioridade, criticidade, creditsCost int) *Requisicao {
	req := NovaRequisicao(tipo, brokerOrigem, recursoID, prioridade, criticidade)
	req.CreditsCost = creditsCost
	return req
}

// 🔴 NOVA FUNÇÃO: SetLedgerData adiciona dados do ledger à requisição
func (r *Requisicao) SetLedgerData(escrowID, laudoHash, laudoCID, signature, publicKey string) {
	r.EscrowID = escrowID
	r.LaudoHash = laudoHash
	r.LaudoCID = laudoCID
	r.Signature = signature
	r.PublicKey = publicKey
}

// 🔴 NOVA FUNÇÃO: HasLedgerData verifica se a requisição tem dados de ledger
func (r *Requisicao) HasLedgerData() bool {
	return r.EscrowID != "" || r.LaudoHash != "" || r.Signature != ""
}

// 🔴 NOVA FUNÇÃO: NewDroneMission cria uma nova missão de drone
func NewDroneMission(missionID, droneID, brokerID, companyID string) *DroneMission {
	return &DroneMission{
		MissionID: missionID,
		DroneID:   droneID,
		BrokerID:  brokerID,
		CompanyID: companyID,
		StartTime: time.Now(),
		Status:    "pending",
	}
}

// 🔴 NOVA FUNÇÃO: CompleteMission marca a missão como concluída
func (dm *DroneMission) CompleteMission(laudoHash, laudoCID, signature, publicKey, eventType string, creditsSpent int) {
	dm.EndTime = time.Now()
	dm.Status = "completed"
	dm.LaudoHash = laudoHash
	dm.LaudoCID = laudoCID
	dm.Signature = signature
	dm.PublicKey = publicKey
	dm.EventType = eventType
	dm.CreditsSpent = creditsSpent
}

// 🔴 NOVA FUNÇÃO: FailMission marca a missão como falha
func (dm *DroneMission) FailMission(reason string) {
	dm.EndTime = time.Now()
	dm.Status = "failed"
	dm.EventType = reason
}
