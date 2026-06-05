// pkg/ledger/types.go
// Pacote ledger contém as estruturas de dados compartilhadas entre o broker
// e a camada de blockchain (Hyperledger Fabric)
package ledger

import (
	"encoding/json"
	"fmt"
	"time"
)

// ============================================================================
// CONSTANTES - Nomes de chaincodes, canais e eventos
// ============================================================================

const (
	// Canais do consórcio
	ChannelConsortium = "ormuz-channel"

	// Chaincodes
	ChaincodeToken   = "token-contract"
	ChaincodeMission = "mission-contract"

	// Eventos emitidos pela ledger
	EventEscrowCreated    = "EscrowCreated"
	EventEscrowReleased   = "EscrowReleased"
	EventEscrowCancelled  = "EscrowCancelled"
	EventMissionLogged    = "MissionLogged"
	EventTransferComplete = "TransferComplete"

	// Status do escrow
	EscrowStatusLocked    = "locked"
	EscrowStatusReleased  = "released"
	EscrowStatusCancelled = "cancelled"

	// Status da missão
	MissionStatusSuccess = "success"
	MissionStatusFailed  = "failed"
	MissionStatusAlert   = "alert"

	// Custos operacionais (em créditos)
	CostStandardMission  = 10
	CostEmergencyMission = 20
	CostReconnaissance   = 5
)

// ============================================================================
// TIPOS PARA GESTÃO DE CRÉDITOS (TOKEN)
// ============================================================================

// Account representa uma conta de empresa/nação no consórcio
type Account struct {
	Owner     string    `json:"owner"`     // ID da empresa/nação
	Balance   int       `json:"balance"`   // Saldo em créditos
	CreatedAt time.Time `json:"createdAt"` // Data de criação
	UpdatedAt time.Time `json:"updatedAt"` // Última atualização
	IsActive  bool      `json:"isActive"`  // Conta ativa?
}

// TransferRequest representa uma solicitação de transferência de créditos
type TransferRequest struct {
	From      string    `json:"from"`      // Origem
	To        string    `json:"to"`        // Destino
	Amount    int       `json:"amount"`    // Quantidade
	Reason    string    `json:"reason"`    // Motivo (ex: "pagamento_missao")
	Timestamp time.Time `json:"timestamp"` // Data da solicitação
}

// TransferResponse representa a resposta de uma transferência
type TransferResponse struct {
	Success        bool      `json:"success"`
	TransactionID  string    `json:"transactionId"`
	NewBalanceFrom int       `json:"newBalanceFrom"`
	NewBalanceTo   int       `json:"newBalanceTo"`
	Error          string    `json:"error,omitempty"`
	Timestamp      time.Time `json:"timestamp"`
}

// ============================================================================
// TIPOS PARA ESCROW (BLOQUEIO DE CRÉDITOS)
// ============================================================================

// Escrow representa um bloqueio de créditos durante uma missão
type Escrow struct {
	MissionID  string    `json:"missionId"`  // ID da missão
	Requester  string    `json:"requester"`  // Quem solicitou (empresa)
	Operator   string    `json:"operator"`   // Quem operou o drone (broker)
	Amount     int       `json:"amount"`     // Quantidade bloqueada
	Status     string    `json:"status"`     // locked, released, cancelled
	CreatedAt  time.Time `json:"createdAt"`  // Data do bloqueio
	ReleasedAt time.Time `json:"releasedAt"` // Data da liberação
	LaudoHash  string    `json:"laudoHash"`  // Hash do laudo (Merkle root)
	LaudoCID   string    `json:"laudoCid"`   // IPFS CID
	ExpiresAt  time.Time `json:"expiresAt"`  // Expira se não usado
}

// EscrowRequest representa uma solicitação de escrow
type EscrowRequest struct {
	Requester string `json:"requester"`
	MissionID string `json:"missionId"`
	Amount    int    `json:"amount"`
	TTL       int    `json:"ttl"` // Time-to-live em segundos
}

// EscrowReleaseRequest representa a liberação de um escrow
type EscrowReleaseRequest struct {
	MissionID string `json:"missionId"`
	Operator  string `json:"operator"`
	LaudoHash string `json:"laudoHash"`
	LaudoCID  string `json:"laudoCid"`
	Signature string `json:"signature"` // Assinatura do drone
}

// ============================================================================
// TIPOS PARA LAUDOS DE MISSÃO (REGISTROS IMUTÁVEIS)
// ============================================================================

// MissionLog representa o registro imutável de uma missão
type MissionLog struct {
	MissionID     string    `json:"missionId"`     // ID único da missão
	DroneID       string    `json:"droneId"`       // ID do drone utilizado
	BrokerID      string    `json:"brokerId"`      // Broker que coordenou
	CompanyID     string    `json:"companyId"`     // Empresa solicitante
	Timestamp     time.Time `json:"timestamp"`     // Data/hora da missão
	LaudoHash     string    `json:"laudoHash"`     // Merkle root dos dados
	LaudoCID      string    `json:"laudoCid"`      // IPFS CID (dados brutos)
	Signature     string    `json:"signature"`     // Assinatura do drone
	PublicKey     string    `json:"publicKey"`     // Chave pública do drone
	Status        string    `json:"status"`        // success, failed, alert
	EventType     string    `json:"eventType"`     // OBJETO_NAO_IDENTIFICADO, etc
	Cost          int       `json:"cost"`          // Créditos gastos
	BlockNumber   uint64    `json:"blockNumber"`   // Bloco da blockchain
	TransactionID string    `json:"transactionId"` // TX ID para auditoria
}

// MissionLogSummary é um resumo do laudo (para listagens)
type MissionLogSummary struct {
	MissionID string    `json:"missionId"`
	DroneID   string    `json:"droneId"`
	Timestamp time.Time `json:"timestamp"`
	Status    string    `json:"status"`
	EventType string    `json:"eventType"`
	Cost      int       `json:"cost"`
}

// LaudoData representa os dados brutos de uma missão (para IPFS)
type LaudoData struct {
	MissionID      string                 `json:"missionId"`
	DroneID        string                 `json:"droneId"`
	BrokerID       string                 `json:"brokerId"`
	StartTime      time.Time              `json:"startTime"`
	EndTime        time.Time              `json:"endTime"`
	Waypoints      []Waypoint             `json:"waypoints"`      // Rota percorrida
	Events         []MissionEvent         `json:"events"`         // Eventos durante a missão
	Telemetry      []TelemetrySample      `json:"telemetry"`      // Dados telemétricos
	SensorReadings []SensorReading        `json:"sensorReadings"` // Leituras de sensores
	FinalReport    string                 `json:"finalReport"`    // Relatório textual
	Metadata       map[string]interface{} `json:"metadata"`
}

// Waypoint representa um ponto na rota do drone
type Waypoint struct {
	Latitude  float64   `json:"lat"`
	Longitude float64   `json:"lng"`
	Altitude  float64   `json:"alt"`
	Timestamp time.Time `json:"timestamp"`
}

// MissionEvent representa um evento durante a missão
type MissionEvent struct {
	Type      string    `json:"type"`     // OBSTACLE, SUSPECT, WEATHER, etc
	Severity  int       `json:"severity"` // 1-5
	Latitude  float64   `json:"lat"`
	Longitude float64   `json:"lng"`
	Timestamp time.Time `json:"timestamp"`
	Details   string    `json:"details"`
}

// TelemetrySample representa um ponto de telemetria
type TelemetrySample struct {
	Timestamp   time.Time `json:"timestamp"`
	Battery     int       `json:"battery"`     // %
	Speed       float64   `json:"speed"`       // km/h
	Temperature float64   `json:"temperature"` // °C
}

// SensorReading representa uma leitura de sensor
type SensorReading struct {
	SensorID  string    `json:"sensorId"`
	Type      string    `json:"type"` // movimento, temperatura, pressao
	Value     float64   `json:"value"`
	Timestamp time.Time `json:"timestamp"`
}

// ============================================================================
// TIPOS PARA RESPOSTAS E CONSULTAS
// ============================================================================

// BalanceResponse resposta da consulta de saldo
type BalanceResponse struct {
	Owner   string `json:"owner"`
	Balance int    `json:"balance"`
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

// MissionQueryParams parâmetros para consultar missões
type MissionQueryParams struct {
	DroneID   string    `json:"droneId,omitempty"`
	CompanyID string    `json:"companyId,omitempty"`
	BrokerID  string    `json:"brokerId,omitempty"`
	Status    string    `json:"status,omitempty"`
	EventType string    `json:"eventType,omitempty"`
	StartTime time.Time `json:"startTime,omitempty"`
	EndTime   time.Time `json:"endTime,omitempty"`
	Limit     int       `json:"limit"`
	Offset    int       `json:"offset"`
}

// ============================================================================
// FUNÇÕES AUXILIARES (VALIDADE, FORMATAÇÃO)
// ============================================================================

// NewEscrow cria um novo escrow com valores padrão
func NewEscrow(requester, missionID string, amount int) *Escrow {
	now := time.Now()
	return &Escrow{
		MissionID: missionID,
		Requester: requester,
		Amount:    amount,
		Status:    EscrowStatusLocked,
		CreatedAt: now,
		ExpiresAt: now.Add(30 * time.Minute), // Expira em 30 min
	}
}

// NewMissionLog cria um novo registro de missão
func NewMissionLog(missionID, droneID, brokerID, companyID string) *MissionLog {
	return &MissionLog{
		MissionID: missionID,
		DroneID:   droneID,
		BrokerID:  brokerID,
		CompanyID: companyID,
		Timestamp: time.Now(),
		Status:    MissionStatusSuccess,
	}
}

// IsExpired verifica se o escrow expirou
func (e *Escrow) IsExpired() bool {
	return time.Now().After(e.ExpiresAt)
}

// CanBeReleased verifica se o escrow pode ser liberado
func (e *Escrow) CanBeReleased() bool {
	return e.Status == EscrowStatusLocked && !e.IsExpired()
}

// ValidateTransferRequest valida uma solicitação de transferência
func ValidateTransferRequest(req *TransferRequest) error {
	if req.From == "" {
		return fmt.Errorf("origem não pode ser vazia")
	}
	if req.To == "" {
		return fmt.Errorf("destino não pode ser vazio")
	}
	if req.From == req.To {
		return fmt.Errorf("origem e destino não podem ser iguais")
	}
	if req.Amount <= 0 {
		return fmt.Errorf("quantidade deve ser maior que zero")
	}
	if req.Reason == "" {
		return fmt.Errorf("motivo da transferência é obrigatório")
	}
	return nil
}

// ToJSON converte qualquer tipo para JSON (para envio ao chaincode)
func ToJSON(v interface{}) ([]byte, error) {
	return json.Marshal(v)
}

// FromJSON converte JSON para o tipo especificado
func FromJSON(data []byte, v interface{}) error {
	return json.Unmarshal(data, v)
}
