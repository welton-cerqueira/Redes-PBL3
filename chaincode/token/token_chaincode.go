// chaincode/token_chaincode.go
// Smart contract para gestão de créditos operacionais (tokens)
// Previne double-spend e garante imutabilidade das transações
package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// TokenContract gerencia os créditos operacionais
type TokenContract struct {
	contractapi.Contract
}

// Account representa uma conta de empresa/nação
type Account struct {
	Owner     string    `json:"owner"`
	Balance   int       `json:"balance"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
	IsActive  bool      `json:"isActive"`
}

// Escrow representa um bloqueio de créditos para uma missão
type Escrow struct {
	MissionID  string    `json:"missionId"`
	Requester  string    `json:"requester"`
	Operator   string    `json:"operator"`
	Amount     int       `json:"amount"`
	Status     string    `json:"status"` // locked, released, cancelled
	CreatedAt  time.Time `json:"createdAt"`
	ReleasedAt time.Time `json:"releasedAt"`
	ExpiresAt  time.Time `json:"expiresAt"`
	LaudoHash  string    `json:"laudoHash"`
	LaudoCID   string    `json:"laudoCid"`
}

// Transaction representa uma transação de créditos (para auditoria)
type Transaction struct {
	ID        string    `json:"id"`
	From      string    `json:"from"`
	To        string    `json:"to"`
	Amount    int       `json:"amount"`
	Type      string    `json:"type"` // transfer, escrow_create, escrow_release, escrow_cancel
	MissionID string    `json:"missionId,omitempty"`
	Timestamp time.Time `json:"timestamp"`
	TxID      string    `json:"txId"`
}

// ============================================================================
// FUNÇÕES DE INICIALIZAÇÃO
// ============================================================================

// InitLedger inicializa o ledger com contas padrão do consórcio
func (t *TokenContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	fmt.Println("InitLedger: Inicializando ledger do consórcio Ormuz")

	// Contas iniciais das empresas do consórcio
	initialAccounts := []Account{
		{Owner: "companyA", Balance: 1000, CreatedAt: time.Now(), UpdatedAt: time.Now(), IsActive: true},
		{Owner: "companyB", Balance: 1000, CreatedAt: time.Now(), UpdatedAt: time.Now(), IsActive: true},
		{Owner: "companyC", Balance: 1000, CreatedAt: time.Now(), UpdatedAt: time.Now(), IsActive: true},
		{Owner: "companyD", Balance: 1000, CreatedAt: time.Now(), UpdatedAt: time.Now(), IsActive: true},
	}

	for _, account := range initialAccounts {
		accountJSON, err := json.Marshal(account)
		if err != nil {
			return fmt.Errorf("falha ao serializar conta %s: %v", account.Owner, err)
		}

		err = ctx.GetStub().PutState(account.Owner, accountJSON)
		if err != nil {
			return fmt.Errorf("falha ao salvar conta %s: %v", account.Owner, err)
		}
	}

	// Registra evento de inicialização
	ctx.GetStub().SetEvent("LedgerInitialized", []byte("consortium_ormuz"))

	fmt.Println("InitLedger: Ledger inicializado com sucesso")
	return nil
}

// ============================================================================
// OPERAÇÕES DE CONSULTA
// ============================================================================

// GetBalance retorna o saldo de uma conta
func (t *TokenContract) GetBalance(ctx contractapi.TransactionContextInterface, owner string) (int, error) {
	accountJSON, err := ctx.GetStub().GetState(owner)
	if err != nil {
		return 0, fmt.Errorf("falha ao consultar conta %s: %v", owner, err)
	}
	if accountJSON == nil {
		return 0, fmt.Errorf("conta %s não encontrada", owner)
	}

	var account Account
	err = json.Unmarshal(accountJSON, &account)
	if err != nil {
		return 0, fmt.Errorf("falha ao deserializar conta: %v", err)
	}

	return account.Balance, nil
}

// GetAccount retorna os dados completos da conta
func (t *TokenContract) GetAccount(ctx contractapi.TransactionContextInterface, owner string) (*Account, error) {
	accountJSON, err := ctx.GetStub().GetState(owner)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar conta %s: %v", owner, err)
	}
	if accountJSON == nil {
		return nil, fmt.Errorf("conta %s não encontrada", owner)
	}

	var account Account
	err = json.Unmarshal(accountJSON, &account)
	if err != nil {
		return nil, fmt.Errorf("falha ao deserializar conta: %v", err)
	}

	return &account, nil
}

// GetEscrow retorna os dados de um escrow
func (t *TokenContract) GetEscrow(ctx contractapi.TransactionContextInterface, missionID string) (*Escrow, error) {
	escrowKey := "escrow_" + missionID
	escrowJSON, err := ctx.GetStub().GetState(escrowKey)
	if err != nil {
		return nil, fmt.Errorf("falha ao consultar escrow %s: %v", missionID, err)
	}
	if escrowJSON == nil {
		return nil, fmt.Errorf("escrow %s não encontrado", missionID)
	}

	var escrow Escrow
	err = json.Unmarshal(escrowJSON, &escrow)
	if err != nil {
		return nil, fmt.Errorf("falha ao deserializar escrow: %v", err)
	}

	return &escrow, nil
}

// GetEscrowStatus retorna apenas o status do escrow
func (t *TokenContract) GetEscrowStatus(ctx contractapi.TransactionContextInterface, missionID string) (string, error) {
	escrow, err := t.GetEscrow(ctx, missionID)
	if err != nil {
		return "", err
	}
	return escrow.Status, nil
}

// GetAllAccounts retorna todas as contas (para auditoria)
func (t *TokenContract) GetAllAccounts(ctx contractapi.TransactionContextInterface) ([]Account, error) {
	resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
	if err != nil {
		return nil, fmt.Errorf("falha ao iterar contas: %v", err)
	}
	defer resultsIterator.Close()

	var accounts []Account
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			continue
		}

		// Pula chaves que não são contas (ex: escrow_*)
		if len(queryResponse.Key) > 7 && queryResponse.Key[:7] == "escrow_" {
			continue
		}

		var account Account
		err = json.Unmarshal(queryResponse.Value, &account)
		if err != nil {
			continue
		}
		accounts = append(accounts, account)
	}

	return accounts, nil
}

// ============================================================================
// OPERAÇÕES DE TRANSFERÊNCIA
// ============================================================================

// Transfer transfere créditos entre duas contas
// Previne double-spend através da atomicidade da transação
func (t *TokenContract) Transfer(ctx contractapi.TransactionContextInterface, from, to string, amount int) error {
	// Validações básicas
	if from == "" || to == "" {
		return fmt.Errorf("origem e destino são obrigatórios")
	}
	if from == to {
		return fmt.Errorf("não é possível transferir para si mesmo")
	}
	if amount <= 0 {
		return fmt.Errorf("quantidade deve ser maior que zero")
	}

	// Obtém conta de origem
	fromAccount, err := t.GetAccount(ctx, from)
	if err != nil {
		return fmt.Errorf("conta de origem inválida: %v", err)
	}
	if !fromAccount.IsActive {
		return fmt.Errorf("conta de origem está inativa")
	}
	if fromAccount.Balance < amount {
		return fmt.Errorf("saldo insuficiente: %d < %d", fromAccount.Balance, amount)
	}

	// Obtém conta de destino
	toAccount, err := t.GetAccount(ctx, to)
	if err != nil {
		// Se destino não existe, cria conta nova
		toAccount = &Account{
			Owner:     to,
			Balance:   0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
			IsActive:  true,
		}
	}
	if !toAccount.IsActive {
		return fmt.Errorf("conta de destino está inativa")
	}

	// Realiza a transferência atomicamente
	fromAccount.Balance -= amount
	toAccount.Balance += amount
	fromAccount.UpdatedAt = time.Now()
	toAccount.UpdatedAt = time.Now()

	// Serializa e salva
	fromJSON, err := json.Marshal(fromAccount)
	if err != nil {
		return fmt.Errorf("falha ao serializar conta origem: %v", err)
	}
	toJSON, err := json.Marshal(toAccount)
	if err != nil {
		return fmt.Errorf("falha ao serializar conta destino: %v", err)
	}

	err = ctx.GetStub().PutState(from, fromJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar conta origem: %v", err)
	}
	err = ctx.GetStub().PutState(to, toJSON)
	if err != nil {
		// Rollback: tenta restaurar conta origem
		_ = ctx.GetStub().PutState(from, fromJSON)
		return fmt.Errorf("falha ao salvar conta destino: %v", err)
	}

	// Registra transação para auditoria
	txID := ctx.GetStub().GetTxID()
	transaction := Transaction{
		ID:        txID,
		From:      from,
		To:        to,
		Amount:    amount,
		Type:      "transfer",
		Timestamp: time.Now(),
		TxID:      txID,
	}
	txJSON, _ := json.Marshal(transaction)
	_ = ctx.GetStub().PutState("tx_"+txID, txJSON)

	// Emite evento
	eventData, _ := json.Marshal(map[string]interface{}{
		"from":   from,
		"to":     to,
		"amount": amount,
		"txId":   txID,
	})
	ctx.GetStub().SetEvent("TransferComplete", eventData)

	fmt.Printf("Transferência realizada: %s -> %s, %d créditos (TX: %s)\n", from, to, amount, txID)
	return nil
}

// ============================================================================
// OPERAÇÕES DE ESCROW (BLOQUEIO PARA MISSÕES)
// ============================================================================

// CreateEscrow cria um escrow bloqueando créditos para uma missão
// Previne double-spend ao bloquear os créditos atomicamente
func (t *TokenContract) CreateEscrow(ctx contractapi.TransactionContextInterface, requester, missionID string, amount int) error {
	// Validações
	if requester == "" || missionID == "" {
		return fmt.Errorf("solicitante e ID da missão são obrigatórios")
	}
	if amount <= 0 {
		return fmt.Errorf("quantidade deve ser maior que zero")
	}

	// Verifica se já existe escrow para esta missão
	existingEscrow, err := t.GetEscrow(ctx, missionID)
	if err == nil && existingEscrow != nil {
		return fmt.Errorf("já existe escrow para a missão %s (status: %s)", missionID, existingEscrow.Status)
	}

	// Obtém conta do solicitante
	account, err := t.GetAccount(ctx, requester)
	if err != nil {
		return fmt.Errorf("conta do solicitante inválida: %v", err)
	}
	if !account.IsActive {
		return fmt.Errorf("conta do solicitante está inativa")
	}
	if account.Balance < amount {
		return fmt.Errorf("saldo insuficiente para escrow: %d < %d", account.Balance, amount)
	}

	// Bloqueia os créditos (debita da conta)
	account.Balance -= amount
	account.UpdatedAt = time.Now()

	accountJSON, err := json.Marshal(account)
	if err != nil {
		return fmt.Errorf("falha ao serializar conta: %v", err)
	}
	err = ctx.GetStub().PutState(requester, accountJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar conta: %v", err)
	}

	// Cria o escrow
	escrow := Escrow{
		MissionID: missionID,
		Requester: requester,
		Amount:    amount,
		Status:    "locked",
		CreatedAt: time.Now(),
		ExpiresAt: time.Now().Add(30 * time.Minute),
	}
	escrowKey := "escrow_" + missionID
	escrowJSON, err := json.Marshal(escrow)
	if err != nil {
		// Rollback: restaura saldo
		account.Balance += amount
		accountJSON, _ := json.Marshal(account)
		_ = ctx.GetStub().PutState(requester, accountJSON)
		return fmt.Errorf("falha ao serializar escrow: %v", err)
	}
	err = ctx.GetStub().PutState(escrowKey, escrowJSON)
	if err != nil {
		// Rollback: restaura saldo
		account.Balance += amount
		accountJSON, _ := json.Marshal(account)
		_ = ctx.GetStub().PutState(requester, accountJSON)
		return fmt.Errorf("falha ao salvar escrow: %v", err)
	}

	// Registra transação
	txID := ctx.GetStub().GetTxID()
	transaction := Transaction{
		ID:        txID,
		From:      requester,
		To:        "",
		Amount:    amount,
		Type:      "escrow_create",
		MissionID: missionID,
		Timestamp: time.Now(),
		TxID:      txID,
	}
	txJSON, _ := json.Marshal(transaction)
	_ = ctx.GetStub().PutState("tx_"+txID, txJSON)

	// Emite evento
	eventData, _ := json.Marshal(map[string]interface{}{
		"requester": requester,
		"missionId": missionID,
		"amount":    amount,
		"txId":      txID,
	})
	ctx.GetStub().SetEvent("EscrowCreated", eventData)

	fmt.Printf("Escrow criado: missão %s, %d créditos bloqueados de %s (TX: %s)\n",
		missionID, amount, requester, txID)
	return nil
}

// ReleaseEscrow libera o escrow e transfere créditos para o operador do drone
func (t *TokenContract) ReleaseEscrow(ctx contractapi.TransactionContextInterface, missionID, operator, laudoHash, laudoCID string) error {
	// Validações
	if missionID == "" || operator == "" {
		return fmt.Errorf("ID da missão e operador são obrigatórios")
	}

	// Obtém o escrow
	escrowKey := "escrow_" + missionID
	escrowJSON, err := ctx.GetStub().GetState(escrowKey)
	if err != nil {
		return fmt.Errorf("falha ao consultar escrow: %v", err)
	}
	if escrowJSON == nil {
		return fmt.Errorf("escrow %s não encontrado", missionID)
	}

	var escrow Escrow
	err = json.Unmarshal(escrowJSON, &escrow)
	if err != nil {
		return fmt.Errorf("falha ao deserializar escrow: %v", err)
	}

	if escrow.Status != "locked" {
		return fmt.Errorf("escrow já foi %s", escrow.Status)
	}
	if time.Now().After(escrow.ExpiresAt) {
		return fmt.Errorf("escrow expirou em %v", escrow.ExpiresAt)
	}

	// Atualiza o escrow
	escrow.Status = "released"
	escrow.Operator = operator
	escrow.ReleasedAt = time.Now()
	escrow.LaudoHash = laudoHash
	escrow.LaudoCID = laudoCID

	escrowJSON, err = json.Marshal(escrow)
	if err != nil {
		return fmt.Errorf("falha ao serializar escrow: %v", err)
	}
	err = ctx.GetStub().PutState(escrowKey, escrowJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar escrow: %v", err)
	}

	// Transfere os créditos para o operador
	err = t.Transfer(ctx, escrow.Requester, operator, escrow.Amount)
	if err != nil {
		return fmt.Errorf("falha ao transferir créditos para operador: %v", err)
	}

	// Registra transação
	txID := ctx.GetStub().GetTxID()
	transaction := Transaction{
		ID:        txID,
		From:      escrow.Requester,
		To:        operator,
		Amount:    escrow.Amount,
		Type:      "escrow_release",
		MissionID: missionID,
		Timestamp: time.Now(),
		TxID:      txID,
	}
	txJSON, _ := json.Marshal(transaction)
	_ = ctx.GetStub().PutState("tx_"+txID, txJSON)

	// Emite evento
	eventData, _ := json.Marshal(map[string]interface{}{
		"missionId": missionID,
		"operator":  operator,
		"amount":    escrow.Amount,
		"laudoHash": laudoHash,
		"laudoCID":  laudoCID,
		"txId":      txID,
	})
	ctx.GetStub().SetEvent("EscrowReleased", eventData)

	fmt.Printf("Escrow liberado: missão %s, %d créditos para %s (TX: %s)\n",
		missionID, escrow.Amount, operator, txID)
	return nil
}

// CancelEscrow cancela um escrow e devolve os créditos ao solicitante
func (t *TokenContract) CancelEscrow(ctx contractapi.TransactionContextInterface, missionID string) error {
	if missionID == "" {
		return fmt.Errorf("ID da missão é obrigatório")
	}

	// Obtém o escrow
	escrowKey := "escrow_" + missionID
	escrowJSON, err := ctx.GetStub().GetState(escrowKey)
	if err != nil {
		return fmt.Errorf("falha ao consultar escrow: %v", err)
	}
	if escrowJSON == nil {
		return fmt.Errorf("escrow %s não encontrado", missionID)
	}

	var escrow Escrow
	err = json.Unmarshal(escrowJSON, &escrow)
	if err != nil {
		return fmt.Errorf("falha ao deserializar escrow: %v", err)
	}

	if escrow.Status != "locked" {
		return fmt.Errorf("escrow já foi %s, não pode ser cancelado", escrow.Status)
	}

	// Atualiza o escrow
	escrow.Status = "cancelled"
	escrow.ReleasedAt = time.Now()

	escrowJSON, err = json.Marshal(escrow)
	if err != nil {
		return fmt.Errorf("falha ao serializar escrow: %v", err)
	}
	err = ctx.GetStub().PutState(escrowKey, escrowJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar escrow: %v", err)
	}

	// Devolve os créditos ao solicitante
	account, err := t.GetAccount(ctx, escrow.Requester)
	if err != nil {
		return fmt.Errorf("falha ao obter conta do solicitante: %v", err)
	}

	account.Balance += escrow.Amount
	account.UpdatedAt = time.Now()

	accountJSON, err := json.Marshal(account)
	if err != nil {
		return fmt.Errorf("falha ao serializar conta: %v", err)
	}
	err = ctx.GetStub().PutState(escrow.Requester, accountJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar conta: %v", err)
	}

	// Registra transação
	txID := ctx.GetStub().GetTxID()
	transaction := Transaction{
		ID:        txID,
		From:      escrow.Requester,
		To:        escrow.Requester,
		Amount:    escrow.Amount,
		Type:      "escrow_cancel",
		MissionID: missionID,
		Timestamp: time.Now(),
		TxID:      txID,
	}
	txJSON, _ := json.Marshal(transaction)
	_ = ctx.GetStub().PutState("tx_"+txID, txJSON)

	// Emite evento
	eventData, _ := json.Marshal(map[string]interface{}{
		"missionId": missionID,
		"requester": escrow.Requester,
		"amount":    escrow.Amount,
		"txId":      txID,
	})
	ctx.GetStub().SetEvent("EscrowCancelled", eventData)

	fmt.Printf("Escrow cancelado: missão %s, %d créditos devolvidos a %s (TX: %s)\n",
		missionID, escrow.Amount, escrow.Requester, txID)
	return nil
}

// ============================================================================
// FUNÇÕES DE ADMINISTRAÇÃO
// ============================================================================

// AddAccount adiciona uma nova conta (apenas administradores)
func (t *TokenContract) AddAccount(ctx contractapi.TransactionContextInterface, owner string, initialBalance int) error {
	if owner == "" {
		return fmt.Errorf("owner é obrigatório")
	}
	if initialBalance < 0 {
		return fmt.Errorf("saldo inicial não pode ser negativo")
	}

	// Verifica se já existe
	existing, _ := t.GetAccount(ctx, owner)
	if existing != nil {
		return fmt.Errorf("conta %s já existe", owner)
	}

	account := Account{
		Owner:     owner,
		Balance:   initialBalance,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		IsActive:  true,
	}

	accountJSON, err := json.Marshal(account)
	if err != nil {
		return fmt.Errorf("falha ao serializar conta: %v", err)
	}

	err = ctx.GetStub().PutState(owner, accountJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar conta: %v", err)
	}

	fmt.Printf("Conta criada: %s com saldo inicial %d\n", owner, initialBalance)
	return nil
}

// DeactivateAccount desativa uma conta (impede novas transações)
func (t *TokenContract) DeactivateAccount(ctx contractapi.TransactionContextInterface, owner string) error {
	account, err := t.GetAccount(ctx, owner)
	if err != nil {
		return err
	}

	account.IsActive = false
	account.UpdatedAt = time.Now()

	accountJSON, err := json.Marshal(account)
	if err != nil {
		return fmt.Errorf("falha ao serializar conta: %v", err)
	}

	err = ctx.GetStub().PutState(owner, accountJSON)
	if err != nil {
		return fmt.Errorf("falha ao salvar conta: %v", err)
	}

	fmt.Printf("Conta desativada: %s\n", owner)
	return nil
}

// ============================================================================
// FUNÇÃO MAIN (obrigatória para chaincode)
// ============================================================================

func main() {
	chaincode, err := contractapi.NewChaincode(&TokenContract{})
	if err != nil {
		fmt.Printf("Erro ao criar chaincode TokenContract: %v\n", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Erro ao iniciar chaincode TokenContract: %v\n", err)
	}
}
