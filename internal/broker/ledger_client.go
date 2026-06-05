// internal/broker/ledger_client.go
// Cliente simplificado para comunicação com Hyperledger Fabric
// Usa HTTP REST Gateway em vez do SDK direto para evitar problemas de compatibilidade
package broker

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"

	"sistema-distribuido-brokers/pkg/ledger"
	"sistema-distribuido-brokers/pkg/utils"
)

// LedgerClient gerencia a comunicação com a blockchain via REST Gateway
type LedgerClient struct {
	// Configuração
	gatewayURL       string
	channelName      string
	tokenChaincode   string
	missionChaincode string

	// HTTP Client
	httpClient *http.Client

	// Estado
	isConnected bool
	connectedAt time.Time
	lastError   error
	mutex       sync.RWMutex

	// Modo offline (para desenvolvimento/teste)
	mockMode bool

	// Callbacks para eventos (simulados)
	eventCallbacks map[string]func(interface{})
	callbackMutex  sync.RWMutex
}

// LedgerConfig configuração do cliente ledger
type LedgerConfig struct {
	GatewayURL       string // URL do Fabric Gateway (ex: "http://localhost:8080")
	ChannelName      string // Nome do canal
	TokenChaincode   string // Nome do chaincode de token
	MissionChaincode string // Nome do chaincode de missão
	MockMode         bool   // Usar modo mock (sem conexão real)
}

// NewLedgerClient cria um novo cliente ledger
func NewLedgerClient(cfg LedgerConfig) (*LedgerClient, error) {
	// Valores padrão
	if cfg.GatewayURL == "" && !cfg.MockMode {
		cfg.GatewayURL = "http://localhost:8080"
	}
	if cfg.ChannelName == "" {
		cfg.ChannelName = ledger.ChannelConsortium
	}
	if cfg.TokenChaincode == "" {
		cfg.TokenChaincode = ledger.ChaincodeToken
	}
	if cfg.MissionChaincode == "" {
		cfg.MissionChaincode = ledger.ChaincodeMission
	}

	lc := &LedgerClient{
		gatewayURL:       cfg.GatewayURL,
		channelName:      cfg.ChannelName,
		tokenChaincode:   cfg.TokenChaincode,
		missionChaincode: cfg.MissionChaincode,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		mockMode:       cfg.MockMode,
		eventCallbacks: make(map[string]func(interface{})),
	}

	if !cfg.MockMode {
		// Testa conexão
		if err := lc.testConnection(); err != nil {
			utils.RegistrarLog("AVISO", "LedgerClient: conexão com gateway falhou: %v, usando modo offline", err)
			lc.mockMode = true
		} else {
			lc.isConnected = true
			lc.connectedAt = time.Now()
			utils.RegistrarLog("INFO", "LedgerClient conectado ao gateway %s", cfg.GatewayURL)
		}
	} else {
		utils.RegistrarLog("INFO", "LedgerClient em MODO MOCK (sem conexão real com blockchain)")
		lc.isConnected = true // Mock está sempre "conectado"
	}

	return lc, nil
}

// testConnection testa se o gateway está acessível
func (lc *LedgerClient) testConnection() error {
	resp, err := lc.httpClient.Get(lc.gatewayURL + "/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("gateway retornou status %d", resp.StatusCode)
	}
	return nil
}

// IsConnected retorna se o cliente está conectado
func (lc *LedgerClient) IsConnected() bool {
	lc.mutex.RLock()
	defer lc.mutex.RUnlock()
	return lc.isConnected
}

// Close fecha o cliente
func (lc *LedgerClient) Close() {
	lc.mutex.Lock()
	defer lc.mutex.Unlock()
	lc.isConnected = false
	utils.RegistrarLog("INFO", "LedgerClient fechado")
}

// ============================================================================
// OPERAÇÕES DE CRÉDITOS (TOKEN)
// ============================================================================

// GetBalance consulta o saldo de uma conta
func (lc *LedgerClient) GetBalance(owner string) (int, error) {
	if lc.mockMode {
		return lc.mockGetBalance(owner), nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.tokenChaincode,
		"function":  "GetBalance",
		"args":      []string{owner},
	}

	resp, err := lc.doQuery(reqBody)
	if err != nil {
		return 0, err
	}

	var balance int
	if err := json.Unmarshal(resp, &balance); err != nil {
		return 0, fmt.Errorf("erro ao decodificar saldo: %v", err)
	}

	utils.RegistrarLog("DEBUG", "LedgerClient: saldo de %s = %d", owner, balance)
	return balance, nil
}

// Transfer realiza transferência de créditos
func (lc *LedgerClient) Transfer(from, to string, amount int) error {
	if lc.mockMode {
		lc.mockTransfer(from, to, amount)
		return nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.tokenChaincode,
		"function":  "Transfer",
		"args":      []string{from, to, fmt.Sprintf("%d", amount)},
	}

	_, err := lc.doExecute(reqBody)
	if err != nil {
		return fmt.Errorf("transferência falhou: %v", err)
	}

	utils.RegistrarLog("INFO", "LedgerClient: transferência de %d créditos de %s para %s realizada",
		amount, from, to)
	return nil
}

// ============================================================================
// OPERAÇÕES DE ESCROW
// ============================================================================

// CreateEscrow cria um escrow (bloqueia créditos)
func (lc *LedgerClient) CreateEscrow(requester, missionID string, amount int) error {
	if lc.mockMode {
		lc.mockCreateEscrow(requester, missionID, amount)
		return nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.tokenChaincode,
		"function":  "CreateEscrow",
		"args":      []string{requester, missionID, fmt.Sprintf("%d", amount)},
	}

	resp, err := lc.doExecute(reqBody)
	if err != nil {
		utils.RegistrarLog("ERRO", "LedgerClient: CreateEscrow falhou: %v", err)
		return fmt.Errorf("criação de escrow falhou: %v", err)
	}

	utils.RegistrarLog("INFO", "LedgerClient: escrow criado para missão %s (TX=%s)",
		missionID, string(resp))
	return nil
}

// ReleaseEscrow libera um escrow
func (lc *LedgerClient) ReleaseEscrow(missionID, operator, laudoHash, laudoCID string) error {
	if lc.mockMode {
		lc.mockReleaseEscrow(missionID, operator)
		return nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.tokenChaincode,
		"function":  "ReleaseEscrow",
		"args":      []string{missionID, operator, laudoHash, laudoCID},
	}

	_, err := lc.doExecute(reqBody)
	if err != nil {
		utils.RegistrarLog("ERRO", "LedgerClient: ReleaseEscrow falhou: %v", err)
		return fmt.Errorf("liberação de escrow falhou: %v", err)
	}

	utils.RegistrarLog("INFO", "LedgerClient: escrow liberado para missão %s", missionID)
	return nil
}

// CancelEscrow cancela um escrow
func (lc *LedgerClient) CancelEscrow(missionID string) error {
	if lc.mockMode {
		lc.mockCancelEscrow(missionID)
		return nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.tokenChaincode,
		"function":  "CancelEscrow",
		"args":      []string{missionID},
	}

	_, err := lc.doExecute(reqBody)
	if err != nil {
		return fmt.Errorf("cancelamento de escrow falhou: %v", err)
	}

	utils.RegistrarLog("INFO", "LedgerClient: escrow cancelado para missão %s", missionID)
	return nil
}

// GetEscrowStatus consulta status do escrow
func (lc *LedgerClient) GetEscrowStatus(missionID string) (string, error) {
	if lc.mockMode {
		return "released", nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.tokenChaincode,
		"function":  "GetEscrowStatus",
		"args":      []string{missionID},
	}

	resp, err := lc.doQuery(reqBody)
	if err != nil {
		return "", err
	}

	var status string
	if err := json.Unmarshal(resp, &status); err != nil {
		return "", err
	}
	return status, nil
}

// ============================================================================
// OPERAÇÕES DE LAUDOS
// ============================================================================

// RegisterMissionLog registra um laudo
func (lc *LedgerClient) RegisterMissionLog(log *ledger.MissionLog) error {
	if lc.mockMode {
		lc.mockRegisterMissionLog(log)
		return nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.missionChaincode,
		"function":  "RegisterMissionLog",
		"args": []string{
			log.MissionID,
			log.DroneID,
			log.BrokerID,
			log.CompanyID,
			log.LaudoHash,
			log.LaudoCID,
			log.Signature,
			log.PublicKey,
			log.Status,
			log.EventType,
			fmt.Sprintf("%d", log.Cost),
		},
	}

	resp, err := lc.doExecute(reqBody)
	if err != nil {
		utils.RegistrarLog("ERRO", "LedgerClient: RegisterMissionLog falhou: %v", err)
		return fmt.Errorf("registro de laudo falhou: %v", err)
	}

	log.TransactionID = string(resp)
	utils.RegistrarLog("INFO", "LedgerClient: laudo da missão %s registrado", log.MissionID)
	return nil
}

// GetMissionLog consulta um laudo
func (lc *LedgerClient) GetMissionLog(missionID string) (*ledger.MissionLog, error) {
	if lc.mockMode {
		return lc.mockGetMissionLog(missionID), nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.missionChaincode,
		"function":  "GetMissionLog",
		"args":      []string{missionID},
	}

	resp, err := lc.doQuery(reqBody)
	if err != nil {
		return nil, err
	}

	var log ledger.MissionLog
	if err := json.Unmarshal(resp, &log); err != nil {
		return nil, err
	}
	return &log, nil
}

// GetMissionsByDrone consulta missões de um drone
func (lc *LedgerClient) GetMissionsByDrone(droneID string) ([]ledger.MissionLog, error) {
	if lc.mockMode {
		return lc.mockGetMissionsByDrone(droneID), nil
	}

	reqBody := map[string]interface{}{
		"channel":   lc.channelName,
		"chaincode": lc.missionChaincode,
		"function":  "GetMissionsByDrone",
		"args":      []string{droneID},
	}

	resp, err := lc.doQuery(reqBody)
	if err != nil {
		return nil, err
	}

	var missions []ledger.MissionLog
	if err := json.Unmarshal(resp, &missions); err != nil {
		return nil, err
	}
	return missions, nil
}

// ============================================================================
// MÉTODOS AUXILIARES (HTTP)
// ============================================================================

// doQuery executa uma query (leitura) no ledger
func (lc *LedgerClient) doQuery(reqBody map[string]interface{}) ([]byte, error) {
	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	resp, err := lc.httpClient.Post(
		lc.gatewayURL+"/api/query",
		"application/json",
		bytes.NewBuffer(jsonBody),
	)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("query falhou (status %d): %s", resp.StatusCode, string(body))
	}

	return io.ReadAll(resp.Body)
}

// doExecute executa uma transação (escrita) no ledger
func (lc *LedgerClient) doExecute(reqBody map[string]interface{}) ([]byte, error) {
	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	resp, err := lc.httpClient.Post(
		lc.gatewayURL+"/api/execute",
		"application/json",
		bytes.NewBuffer(jsonBody),
	)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("execução falhou (status %d): %s", resp.StatusCode, string(body))
	}

	return io.ReadAll(resp.Body)
}

// ============================================================================
// MODO MOCK (para desenvolvimento sem blockchain real)
// ============================================================================

type mockAccount struct {
	Owner   string
	Balance int
}

type mockEscrow struct {
	MissionID string
	Requester string
	Amount    int
	Status    string
}

var (
	mockAccounts = map[string]*mockAccount{
		"companyA": {Owner: "companyA", Balance: 1000},
		"companyB": {Owner: "companyB", Balance: 1000},
		"companyC": {Owner: "companyC", Balance: 1000},
		"broker-1": {Owner: "broker-1", Balance: 0},
		"broker-2": {Owner: "broker-2", Balance: 0},
		"broker-3": {Owner: "broker-3", Balance: 0},
		"broker-4": {Owner: "broker-4", Balance: 0},
	}
	mockEscrows = make(map[string]*mockEscrow)
	mockLogs    = make(map[string]*ledger.MissionLog)
	mockMutex   sync.Mutex
)

func (lc *LedgerClient) mockGetBalance(owner string) int {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	if acc, ok := mockAccounts[owner]; ok {
		return acc.Balance
	}
	return 1000 // Default para empresas novas
}

func (lc *LedgerClient) mockTransfer(from, to string, amount int) {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	if fromAcc, ok := mockAccounts[from]; ok {
		if fromAcc.Balance >= amount {
			fromAcc.Balance -= amount
			if toAcc, ok := mockAccounts[to]; ok {
				toAcc.Balance += amount
			} else {
				mockAccounts[to] = &mockAccount{Owner: to, Balance: amount}
			}
		}
	}
}

func (lc *LedgerClient) mockCreateEscrow(requester, missionID string, amount int) {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	if acc, ok := mockAccounts[requester]; ok && acc.Balance >= amount {
		acc.Balance -= amount
		mockEscrows[missionID] = &mockEscrow{
			MissionID: missionID,
			Requester: requester,
			Amount:    amount,
			Status:    "locked",
		}
	}
}

func (lc *LedgerClient) mockReleaseEscrow(missionID, operator string) {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	if escrow, ok := mockEscrows[missionID]; ok && escrow.Status == "locked" {
		escrow.Status = "released"
		if opAcc, ok := mockAccounts[operator]; ok {
			opAcc.Balance += escrow.Amount
		} else {
			mockAccounts[operator] = &mockAccount{Owner: operator, Balance: escrow.Amount}
		}
	}
}

func (lc *LedgerClient) mockCancelEscrow(missionID string) {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	if escrow, ok := mockEscrows[missionID]; ok {
		escrow.Status = "cancelled"
		if acc, ok := mockAccounts[escrow.Requester]; ok {
			acc.Balance += escrow.Amount
		}
	}
}

func (lc *LedgerClient) mockRegisterMissionLog(log *ledger.MissionLog) {
	mockMutex.Lock()
	defer mockMutex.Unlock()
	mockLogs[log.MissionID] = log
}

func (lc *LedgerClient) mockGetMissionLog(missionID string) *ledger.MissionLog {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	if log, ok := mockLogs[missionID]; ok {
		return log
	}
	return nil
}

func (lc *LedgerClient) mockGetMissionsByDrone(droneID string) []ledger.MissionLog {
	mockMutex.Lock()
	defer mockMutex.Unlock()

	var result []ledger.MissionLog
	for _, log := range mockLogs {
		if log.DroneID == droneID {
			result = append(result, *log)
		}
	}
	return result
}

// ============================================================================
// UTILITÁRIOS
// ============================================================================

// HasEnoughCredits verifica se empresa tem créditos suficientes
func (lc *LedgerClient) HasEnoughCredits(company string, required int) (bool, error) {
	balance, err := lc.GetBalance(company)
	if err != nil {
		return false, err
	}
	return balance >= required, nil
}

// GetStatus retorna status do cliente
func (lc *LedgerClient) GetStatus() map[string]interface{} {
	lc.mutex.RLock()
	defer lc.mutex.RUnlock()

	return map[string]interface{}{
		"isConnected": lc.isConnected,
		"mockMode":    lc.mockMode,
		"gatewayURL":  lc.gatewayURL,
		"connectedAt": lc.connectedAt,
	}
}

// OnEvent registra callback para eventos (mock)
func (lc *LedgerClient) OnEvent(eventName string, callback func(interface{})) {
	lc.callbackMutex.Lock()
	defer lc.callbackMutex.Unlock()
	lc.eventCallbacks[eventName] = callback
}
