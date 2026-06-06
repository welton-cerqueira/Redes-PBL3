// chaincode/mission/mission_chaincode.go
// Smart contract para registro imutável de laudos de missão de drones
package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// MissionContract gerencia os laudos de missão
type MissionContract struct {
	contractapi.Contract
}

// MissionLog representa o registro imutável de uma missão
type MissionLog struct {
	MissionID     string    `json:"missionId"`
	DroneID       string    `json:"droneId"`
	BrokerID      string    `json:"brokerId"`
	CompanyID     string    `json:"companyId"`
	Timestamp     time.Time `json:"timestamp"`
	LaudoHash     string    `json:"laudoHash"`     // Merkle root dos dados
	LaudoCID      string    `json:"laudoCid"`      // IPFS CID dos dados brutos
	Signature     string    `json:"signature"`     // Assinatura do drone
	PublicKey     string    `json:"publicKey"`     // Chave pública do drone
	Status        string    `json:"status"`        // success, failed, alert
	EventType     string    `json:"eventType"`     // OBJETO_NAO_IDENTIFICADO, etc
	Cost          int       `json:"cost"`          // Créditos gastos
	TransactionID string    `json:"transactionId"` // TX ID da blockchain
	BlockNumber   uint64    `json:"blockNumber"`   // Bloco onde foi registrado
}

// ============================================================================
// FUNÇÕES DE INICIALIZAÇÃO
// ============================================================================

// InitLedger inicializa o ledger de missões
func (m *MissionContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	fmt.Println("InitLedger: Inicializando ledger de missões do consórcio Ormuz")

	// Registra evento de inicialização
	ctx.GetStub().SetEvent("MissionLedgerInitialized", []byte("consortium_ormuz"))

	fmt.Println("InitLedger: Ledger de missões inicializado com sucesso")
	return nil
}

// ============================================================================
// REGISTRO DE LAUDOS
// ============================================================================

// RegisterMissionLog registra um laudo de missão na blockchain
// O laudo deve ser assinado pelo drone antes do envio
func (m *MissionContract) RegisterMissionLog(
	ctx contractapi.TransactionContextInterface,
	missionID, droneID, brokerID, companyID,
	laudoHash, laudoCID, signature, publicKey,
	status, eventType string,
	cost int,
) error {
	// Validações básicas
	if missionID == "" {
		return fmt.Errorf("missionID é obrigatório")
	}
	if droneID == "" {
		return fmt.Errorf("droneID é obrigatório")
	}
	if brokerID == "" {
		return fmt.Errorf("brokerID é obrigatório")
	}
	if companyID == "" {
		return fmt.Errorf("companyID é obrigatório")
	}
	if laudoHash == "" {
		return fmt.Errorf("laudoHash é obrigatório")
	}
	if signature == "" {
		return fmt.Errorf("assinatura é obrigatória")
	}
	if publicKey == "" {
		return fmt.Errorf("publicKey é obrigatória")
	}
	if status == "" {
		status = "success"
	}
	if cost < 0 {
		cost = 0
	}

	// Verifica se já existe um laudo para esta missão (imutabilidade)
	existing, err := m.GetMissionLog(ctx, missionID)
	if err == nil && existing != nil {
		return fmt.Errorf("já existe laudo para a missão %s, não é possível alterar", missionID)
	}

	// Cria o laudo
	txID := ctx.GetStub().GetTxID()
	timestamp, _ := ctx.GetStub().GetTxTimestamp()

	log := MissionLog{
		MissionID:     missionID,
		DroneID:       droneID,
		BrokerID:      brokerID,
		CompanyID:     companyID,
		Timestamp:     time.Unix(timestamp.GetSeconds(), int64(timestamp.GetNanos())),
		LaudoHash:     laudoHash,
		LaudoCID:      laudoCID,
		Signature:     signature,
		PublicKey:     publicKey,
		Status:        status,
		EventType:     eventType,
		Cost:          cost,
		TransactionID: txID,
		BlockNumber:   uint64(timestamp.GetSeconds()),
	}

	// Serializa e salva
	logJSON, err := json.Marshal(log)
	if err != nil {
		return fmt.Errorf("falha ao serializar laudo: %v", err)
	}

	// Salva usando missionID como chave principal
	err = ctx.GetStub().PutState(missionID, logJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar laudo: %v", err)
	}

	// Cria índices secundários para consultas eficientes
	// Índice por drone
	droneKey := "drone~" + droneID + "~" + missionID
	_ = ctx.GetStub().PutState(droneKey, []byte(missionID))

	// Índice por empresa
	companyKey := "company~" + companyID + "~" + missionID
	_ = ctx.GetStub().PutState(companyKey, []byte(missionID))

	// Índice por broker
	brokerKey := "broker~" + brokerID + "~" + missionID
	_ = ctx.GetStub().PutState(brokerKey, []byte(missionID))

	// Índice por timestamp (para consultas por período)
	timestampKey := fmt.Sprintf("ts~%d~%s", log.Timestamp.UnixNano(), missionID)
	_ = ctx.GetStub().PutState(timestampKey, []byte(missionID))

	// Emite evento para notificar os brokers
	eventData, _ := json.Marshal(map[string]interface{}{
		"missionId": missionID,
		"droneId":   droneID,
		"brokerId":  brokerID,
		"companyId": companyID,
		"status":    status,
		"eventType": eventType,
		"timestamp": log.Timestamp,
		"txId":      txID,
	})
	ctx.GetStub().SetEvent("MissionLogged", eventData)

	fmt.Printf("Laudo registrado: missão %s, drone %s, status=%s, eventType=%s (TX: %s)\n",
		missionID, droneID, status, eventType, txID)
	return nil
}

// ============================================================================
// CONSULTAS
// ============================================================================

// GetMissionLog retorna o laudo de uma missão específica
func (m *MissionContract) GetMissionLog(ctx contractapi.TransactionContextInterface, missionID string) (*MissionLog, error) {
	logJSON, err := ctx.GetStub().GetState(missionID)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar laudo %s: %v", missionID, err)
	}
	if logJSON == nil {
		return nil, fmt.Errorf("laudo %s não encontrado", missionID)
	}

	var log MissionLog
	err = json.Unmarshal(logJSON, &log)
	if err != nil {
		return nil, fmt.Errorf("falha ao deserializar laudo: %v", err)
	}

	return &log, nil
}

// GetMissionLogsByDrone retorna todos os laudos de um drone
func (m *MissionContract) GetMissionLogsByDrone(ctx contractapi.TransactionContextInterface, droneID string) ([]MissionLog, error) {
	// Busca índices do drone
	startKey := "drone~" + droneID + "~"
	endKey := startKey + "\uffff"

	resultsIterator, err := ctx.GetStub().GetStateByRange(startKey, endKey)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar missões do drone %s: %v", droneID, err)
	}
	defer resultsIterator.Close()

	var missionIDs []string
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		missionIDs = append(missionIDs, string(queryResponse.Value))
	}

	// Busca os laudos completos
	var logs []MissionLog
	for _, missionID := range missionIDs {
		log, err := m.GetMissionLog(ctx, missionID)
		if err != nil {
			continue
		}
		logs = append(logs, *log)
	}

	return logs, nil
}

// GetMissionLogsByCompany retorna todos os laudos de uma empresa
func (m *MissionContract) GetMissionLogsByCompany(ctx contractapi.TransactionContextInterface, companyID string) ([]MissionLog, error) {
	startKey := "company~" + companyID + "~"
	endKey := startKey + "\uffff"

	resultsIterator, err := ctx.GetStub().GetStateByRange(startKey, endKey)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar missões da empresa %s: %v", companyID, err)
	}
	defer resultsIterator.Close()

	var missionIDs []string
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		missionIDs = append(missionIDs, string(queryResponse.Value))
	}

	var logs []MissionLog
	for _, missionID := range missionIDs {
		log, err := m.GetMissionLog(ctx, missionID)
		if err != nil {
			continue
		}
		logs = append(logs, *log)
	}

	return logs, nil
}

// GetMissionLogsByBroker retorna todos os laudos de um broker
func (m *MissionContract) GetMissionLogsByBroker(ctx contractapi.TransactionContextInterface, brokerID string) ([]MissionLog, error) {
	startKey := "broker~" + brokerID + "~"
	endKey := startKey + "\uffff"

	resultsIterator, err := ctx.GetStub().GetStateByRange(startKey, endKey)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar missões do broker %s: %v", brokerID, err)
	}
	defer resultsIterator.Close()

	var missionIDs []string
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		missionIDs = append(missionIDs, string(queryResponse.Value))
	}

	var logs []MissionLog
	for _, missionID := range missionIDs {
		log, err := m.GetMissionLog(ctx, missionID)
		if err != nil {
			continue
		}
		logs = append(logs, *log)
	}

	return logs, nil
}

// GetMissionLogsByTimeRange retorna laudos em um período de tempo
func (m *MissionContract) GetMissionLogsByTimeRange(ctx contractapi.TransactionContextInterface, startTime, endTime string) ([]MissionLog, error) {
	// Parse dos timestamps (formato RFC3339)
	start, err := time.Parse(time.RFC3339, startTime)
	if err != nil {
		return nil, fmt.Errorf("formato de startTime inválido: %v", err)
	}
	end, err := time.Parse(time.RFC3339, endTime)
	if err != nil {
		return nil, fmt.Errorf("formato de endTime inválido: %v", err)
	}

	startKey := fmt.Sprintf("ts~%d~", start.UnixNano())
	endKey := fmt.Sprintf("ts~%d~\uffff", end.UnixNano())

	resultsIterator, err := ctx.GetStub().GetStateByRange(startKey, endKey)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar missões por período: %v", err)
	}
	defer resultsIterator.Close()

	var missionIDs []string
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}
		missionIDs = append(missionIDs, string(queryResponse.Value))
	}

	var logs []MissionLog
	for _, missionID := range missionIDs {
		log, err := m.GetMissionLog(ctx, missionID)
		if err != nil {
			continue
		}
		logs = append(logs, *log)
	}

	return logs, nil
}

// GetAllMissionLogs retorna todos os laudos (com paginação)
func (m *MissionContract) GetAllMissionLogs(ctx contractapi.TransactionContextInterface, limit, offset int) ([]MissionLog, error) {
	if limit <= 0 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}

	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("falha ao iterar laudos: %v", err)
	}
	defer resultsIterator.Close()

	var logs []MissionLog
	skipped := 0
	count := 0

	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}

		// Pula índices (chaves que não são missões diretas)
		key := queryResponse.Key
		if len(key) == 0 {
			continue
		}

		// Pula chaves de índice
		if key[0] == 'd' && len(key) > 5 && key[:5] == "drone" {
			continue
		}
		if key[0] == 'c' && len(key) > 7 && key[:7] == "company" {
			continue
		}
		if key[0] == 'b' && len(key) > 6 && key[:6] == "broker" {
			continue
		}
		if key[0] == 't' && len(key) > 2 && key[:2] == "ts" {
			continue
		}
		// Pula chaves que começam com escrow_ (se houver)
		if len(key) > 7 && key[:7] == "escrow_" {
			continue
		}

		if skipped < offset {
			skipped++
			continue
		}
		if count >= limit {
			break
		}

		var log MissionLog
		err = json.Unmarshal(queryResponse.Value, &log)
		if err != nil {
			continue
		}
		logs = append(logs, log)
		count++
	}

	return logs, nil
}

// ============================================================================
// CONSULTAS AGREGADAS (MÉTRICAS)
// ============================================================================

// GetMissionCountByDrone retorna o número de missões por drone
func (m *MissionContract) GetMissionCountByDrone(ctx contractapi.TransactionContextInterface, droneID string) (int, error) {
	logs, err := m.GetMissionLogsByDrone(ctx, droneID)
	if err != nil {
		return 0, err
	}
	return len(logs), nil
}

// GetTotalCostByCompany retorna o custo total gasto por uma empresa
func (m *MissionContract) GetTotalCostByCompany(ctx contractapi.TransactionContextInterface, companyID string) (int, error) {
	logs, err := m.GetMissionLogsByCompany(ctx, companyID)
	if err != nil {
		return 0, err
	}

	totalCost := 0
	for _, log := range logs {
		totalCost += log.Cost
	}
	return totalCost, nil
}

// GetAlertCountByDrone retorna o número de alertas gerados por um drone
func (m *MissionContract) GetAlertCountByDrone(ctx contractapi.TransactionContextInterface, droneID string) (int, error) {
	logs, err := m.GetMissionLogsByDrone(ctx, droneID)
	if err != nil {
		return 0, err
	}

	alertCount := 0
	for _, log := range logs {
		if log.Status == "alert" {
			alertCount++
		}
	}
	return alertCount, nil
}

// GetMissionSummary retorna um resumo de todas as missões (para dashboard)
func (m *MissionContract) GetMissionSummary(ctx contractapi.TransactionContextInterface) (map[string]interface{}, error) {
	allLogs, err := m.GetAllMissionLogs(ctx, 10000, 0)
	if err != nil {
		return nil, err
	}

	totalMissions := len(allLogs)
	totalAlerts := 0
	totalCost := 0
	dronesMap := make(map[string]bool)
	companiesMap := make(map[string]bool)

	for _, log := range allLogs {
		if log.Status == "alert" {
			totalAlerts++
		}
		totalCost += log.Cost
		dronesMap[log.DroneID] = true
		companiesMap[log.CompanyID] = true
	}

	summary := map[string]interface{}{
		"totalMissions":   totalMissions,
		"totalAlerts":     totalAlerts,
		"totalCost":       totalCost,
		"uniqueDrones":    len(dronesMap),
		"uniqueCompanies": len(companiesMap),
		"lastUpdate":      time.Now(),
	}

	return summary, nil
}

// ============================================================================
// VALIDAÇÃO E VERIFICAÇÃO
// ============================================================================

// VerifyMissionLog verifica a integridade de um laudo (hash + assinatura)
// NOTA: A verificação criptográfica deve ser feita no cliente
// Este método apenas retorna os dados necessários para a verificação
func (m *MissionContract) VerifyMissionLog(ctx contractapi.TransactionContextInterface, missionID string) (map[string]string, error) {
	log, err := m.GetMissionLog(ctx, missionID)
	if err != nil {
		return nil, err
	}

	return map[string]string{
		"missionId":     log.MissionID,
		"laudoHash":     log.LaudoHash,
		"signature":     log.Signature,
		"publicKey":     log.PublicKey,
		"timestamp":     log.Timestamp.String(),
		"status":        log.Status,
		"transactionId": log.TransactionID,
	}, nil
}

// ============================================================================
// FUNÇÕES DE ADMINISTRAÇÃO
// ============================================================================

// DeleteMissionLog remove um laudo (apenas para emergências/administração)
// NOTA: Isso compromete a imutabilidade! Deve ser usado apenas em situações extremas
// e com aprovação do consórcio.
func (m *MissionContract) DeleteMissionLog(ctx contractapi.TransactionContextInterface, missionID string) error {
	// Verifica se o laudo existe
	_, err := m.GetMissionLog(ctx, missionID)
	if err != nil {
		return err
	}

	// Remove o laudo principal
	err = ctx.GetStub().DelState(missionID)
	if err != nil {
		return fmt.Errorf("falha ao remover laudo: %v", err)
	}

	fmt.Printf("AVISO: Laudo %s removido (ação administrativa)\n", missionID)
	ctx.GetStub().SetEvent("MissionLogDeleted", []byte(missionID))
	return nil
}

// ============================================================================
// FUNÇÃO MAIN
// ============================================================================

func main() {
	chaincode, err := contractapi.NewChaincode(&MissionContract{})
	if err != nil {
		fmt.Printf("Erro ao criar chaincode MissionContract: %v\n", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Erro ao iniciar chaincode MissionContract: %v\n", err)
	}
}
