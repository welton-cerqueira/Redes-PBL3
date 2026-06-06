// internal/broker/token_manager.go
// Gerencia créditos operacionais localmente (cache + validação)
package broker

import (
	"fmt"
	"sync"
	"time"

	"sistema-distribuido-brokers/pkg/ledger"
	"sistema-distribuido-brokers/pkg/utils"
)

// TokenManager gerencia créditos operacionais localmente
type TokenManager struct {
	brokerID     string
	ledgerClient *LedgerClient

	// Cache de saldos
	balanceCache map[string]*cachedBalance
	cacheMutex   sync.RWMutex

	// Locks para operações concorrentes
	operationLocks map[string]*sync.Mutex // lock por empresa/missão

	// Transações pendentes (para sync com ledger)
	pendingTx map[string]*pendingTransaction

	// Configuração
	cacheTTL     time.Duration
	syncInterval time.Duration

	// Controle
	executando bool
	stopCh     chan struct{}
	wg         sync.WaitGroup
}

// cachedBalance representa um saldo em cache
type cachedBalance struct {
	Company  string
	Balance  int
	CachedAt time.Time
	Version  int64 // Para detectar mudanças
}

// pendingTransaction representa uma transação pendente
type pendingTransaction struct {
	ID         string
	Type       string // "transfer", "escrow", "release"
	Company    string
	Amount     int
	MissionID  string
	Status     string // "pending", "committed", "failed"
	CreatedAt  time.Time
	RetryCount int
}

// TokenManagerConfig configuração do gerenciador
type TokenManagerConfig struct {
	BrokerID     string
	LedgerClient *LedgerClient
	CacheTTL     time.Duration // Tempo de vida do cache (padrão: 30s)
	SyncInterval time.Duration // Intervalo de sync (padrão: 60s)
}

// NewTokenManager cria um novo gerenciador de tokens
func NewTokenManager(cfg TokenManagerConfig) *TokenManager {
	if cfg.CacheTTL == 0 {
		cfg.CacheTTL = 30 * time.Second
	}
	if cfg.SyncInterval == 0 {
		cfg.SyncInterval = 60 * time.Second
	}

	tm := &TokenManager{
		brokerID:       cfg.BrokerID,
		ledgerClient:   cfg.LedgerClient,
		balanceCache:   make(map[string]*cachedBalance),
		operationLocks: make(map[string]*sync.Mutex),
		pendingTx:      make(map[string]*pendingTransaction),
		cacheTTL:       cfg.CacheTTL,
		syncInterval:   cfg.SyncInterval,
		executando:     true,
		stopCh:         make(chan struct{}),
	}

	// Inicia sync periódico
	tm.wg.Add(1)
	go tm.periodicSync()

	utils.RegistrarLog("INFO", "TokenManager inicializado para broker %s (cacheTTL=%v, syncInterval=%v)",
		cfg.BrokerID, cfg.CacheTTL, cfg.SyncInterval)

	return tm
}

// ============================================================================
// OPERAÇÕES PÚBLICAS
// ============================================================================

// GetBalance retorna o saldo de uma empresa (com cache)
func (tm *TokenManager) GetBalance(company string) (int, error) {
	// Tenta cache primeiro
	if balance, ok := tm.getFromCache(company); ok {
		utils.RegistrarLog("DEBUG", "TokenManager: saldo de %s (cache) = %d", company, balance)
		return balance, nil
	}

	// Cache expirado, consulta ledger
	balance, err := tm.ledgerClient.GetBalance(company)
	if err != nil {
		// Se ledger falhou, retorna último cache se existir
		if cached, ok := tm.balanceCache[company]; ok {
			utils.RegistrarLog("AVISO", "TokenManager: ledger falhou, usando cache expirado para %s", company)
			return cached.Balance, nil
		}
		return 0, fmt.Errorf("falha ao obter saldo de %s: %v", company, err)
	}

	// Atualiza cache
	tm.updateCache(company, balance)
	return balance, nil
}

// HasEnoughCredits verifica se empresa tem créditos suficientes
func (tm *TokenManager) HasEnoughCredits(company string, required int) (bool, error) {
	balance, err := tm.GetBalance(company)
	if err != nil {
		return false, err
	}
	return balance >= required, nil
}

// ReserveCredits reserva créditos para uma missão (cria escrow)
// Retorna (sucesso, motivo_erro)
func (tm *TokenManager) ReserveCredits(company, missionID string, amount int) (bool, string) {
	// Lock para evitar race condition na mesma empresa
	lock := tm.getOperationLock(company)
	lock.Lock()
	defer lock.Unlock()

	// Verifica saldo atual (com cache fresco)
	balance, err := tm.GetBalance(company)
	if err != nil {
		utils.RegistrarLog("ERRO", "TokenManager: falha ao verificar saldo de %s: %v", company, err)
		return false, "erro_interno"
	}

	if balance < amount {
		utils.RegistrarLog("AVISO", "TokenManager: %s tem saldo insuficiente (%d < %d)", company, balance, amount)
		return false, "saldo_insuficiente"
	}

	// Verifica se já existe escrow para esta missão (double-spend prevention)
	if tm.hasActiveEscrow(missionID) {
		utils.RegistrarLog("AVISO", "TokenManager: missão %s já possui escrow ativo", missionID)
		return false, "escrow_existente"
	}

	// Cria escrow na ledger
	err = tm.ledgerClient.CreateEscrow(company, missionID, amount)
	if err != nil {
		// Se ledger falhou, registra transação pendente
		tm.addPendingTransaction(&pendingTransaction{
			ID:        missionID,
			Type:      "escrow",
			Company:   company,
			Amount:    amount,
			MissionID: missionID,
			Status:    "pending",
			CreatedAt: time.Now(),
		})
		utils.RegistrarLog("AVISO", "TokenManager: escrow para %s registrado como pendente", missionID)
		return true, "pendente" // Retorna sucesso, será sincronizado depois
	}

	// Atualiza cache local (diminui saldo)
	tm.updateCache(company, balance-amount)

	utils.RegistrarLog("INFO", "TokenManager: %d créditos reservados para %s (missão %s)", amount, company, missionID)
	return true, "sucesso"
}

// ReleaseCredits libera créditos após missão concluída
func (tm *TokenManager) ReleaseCredits(missionID, operator, laudoHash, laudoCID string) error {
	lock := tm.getOperationLock(missionID)
	lock.Lock()
	defer lock.Unlock()

	// Verifica status do escrow
	status, err := tm.ledgerClient.GetEscrowStatus(missionID)
	if err != nil {
		utils.RegistrarLog("ERRO", "TokenManager: falha ao verificar escrow %s: %v", missionID, err)
		// Registra para retry
		tm.addPendingTransaction(&pendingTransaction{
			ID:        missionID,
			Type:      "release",
			MissionID: missionID,
			Status:    "pending",
			CreatedAt: time.Now(),
		})
		return fmt.Errorf("escrow pendente: %v", err)
	}

	if status != ledger.EscrowStatusLocked && status != "" {
		return fmt.Errorf("escrow já foi %s", status)
	}

	// Libera escrow
	err = tm.ledgerClient.ReleaseEscrow(missionID, operator, laudoHash, laudoCID)
	if err != nil {
		return fmt.Errorf("falha ao liberar escrow: %v", err)
	}

	utils.RegistrarLog("INFO", "TokenManager: créditos da missão %s liberados para %s", missionID, operator)
	return nil
}

// CancelReservation cancela uma reserva de créditos
func (tm *TokenManager) CancelReservation(missionID string) error {
	lock := tm.getOperationLock(missionID)
	lock.Lock()
	defer lock.Unlock()

	err := tm.ledgerClient.CancelEscrow(missionID)
	if err != nil {
		return fmt.Errorf("falha ao cancelar escrow: %v", err)
	}

	utils.RegistrarLog("INFO", "TokenManager: reserva da missão %s cancelada", missionID)
	return nil
}

// ============================================================================
// OPERAÇÕES DE TRANSFERÊNCIA (entre empresas)
// ============================================================================

// TransferCredits transfere créditos entre empresas
func (tm *TokenManager) TransferCredits(from, to string, amount int, reason string) error {
	// Lock na origem
	lock := tm.getOperationLock(from)
	lock.Lock()
	defer lock.Unlock()

	// Verifica saldo
	balance, err := tm.GetBalance(from)
	if err != nil {
		return err
	}
	if balance < amount {
		return fmt.Errorf("saldo insuficiente: %d < %d", balance, amount)
	}

	// Executa transferência
	err = tm.ledgerClient.Transfer(from, to, amount)
	if err != nil {
		// Registra pendente
		tm.addPendingTransaction(&pendingTransaction{
			ID:      fmt.Sprintf("tx_%d", time.Now().UnixNano()),
			Type:    "transfer",
			Company: from,
			Amount:  amount,
			Status:  "pending",
		})
		return fmt.Errorf("transferência pendente: %v", err)
	}

	// Atualiza cache
	tm.updateCache(from, balance-amount)

	// Atualiza cache do destino (força refresh)
	tm.invalidateCache(to)

	utils.RegistrarLog("INFO", "TokenManager: transferência de %d créditos de %s para %s (%s)",
		amount, from, to, reason)
	return nil
}

// ============================================================================
// MÉTODOS DE CACHE
// ============================================================================

// getFromCache tenta obter saldo do cache
func (tm *TokenManager) getFromCache(company string) (int, bool) {
	tm.cacheMutex.RLock()
	defer tm.cacheMutex.RUnlock()

	cached, exists := tm.balanceCache[company]
	if !exists {
		return 0, false
	}

	// Verifica se cache expirou
	if time.Since(cached.CachedAt) > tm.cacheTTL {
		return 0, false
	}

	return cached.Balance, true
}

// updateCache atualiza o cache de saldo
func (tm *TokenManager) updateCache(company string, balance int) {
	tm.cacheMutex.Lock()
	defer tm.cacheMutex.Unlock()

	tm.balanceCache[company] = &cachedBalance{
		Company:  company,
		Balance:  balance,
		CachedAt: time.Now(),
		Version:  time.Now().UnixNano(),
	}
}

// invalidateCache invalida o cache de uma empresa
func (tm *TokenManager) invalidateCache(company string) {
	tm.cacheMutex.Lock()
	defer tm.cacheMutex.Unlock()
	delete(tm.balanceCache, company)
}

// refreshAllCache atualiza todo o cache
func (tm *TokenManager) refreshAllCache() {
	tm.cacheMutex.Lock()
	defer tm.cacheMutex.Unlock()

	for company := range tm.balanceCache {
		// Remove para forçar refresh
		delete(tm.balanceCache, company)
	}
}

// ============================================================================
// OPERAÇÕES DE LOCK
// ============================================================================

// getOperationLock retorna lock para uma chave
func (tm *TokenManager) getOperationLock(key string) *sync.Mutex {
	tm.cacheMutex.Lock()
	defer tm.cacheMutex.Unlock()

	if lock, exists := tm.operationLocks[key]; exists {
		return lock
	}

	lock := &sync.Mutex{}
	tm.operationLocks[key] = lock
	return lock
}

// ============================================================================
// TRANSAÇÕES PENDENTES
// ============================================================================

// addPendingTransaction adiciona transação pendente
func (tm *TokenManager) addPendingTransaction(tx *pendingTransaction) {
	tm.cacheMutex.Lock()
	defer tm.cacheMutex.Unlock()
	tm.pendingTx[tx.ID] = tx
}

// removePendingTransaction remove transação pendente
func (tm *TokenManager) removePendingTransaction(id string) {
	tm.cacheMutex.Lock()
	defer tm.cacheMutex.Unlock()
	delete(tm.pendingTx, id)
}

// getPendingTransactions retorna todas pendentes
func (tm *TokenManager) getPendingTransactions() []*pendingTransaction {
	tm.cacheMutex.RLock()
	defer tm.cacheMutex.RUnlock()

	var result []*pendingTransaction
	for _, tx := range tm.pendingTx {
		result = append(result, tx)
	}
	return result
}

// periodicSync sincroniza transações pendentes periodicamente
func (tm *TokenManager) periodicSync() {
	defer tm.wg.Done()

	ticker := time.NewTicker(tm.syncInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			tm.syncPendingTransactions()
			tm.refreshAllCache()
		case <-tm.stopCh:
			return
		}
	}
}

// syncPendingTransactions tenta processar transações pendentes
func (tm *TokenManager) syncPendingTransactions() {
	pending := tm.getPendingTransactions()

	for _, tx := range pending {
		if tx.RetryCount > 5 {
			utils.RegistrarLog("ERRO", "TokenManager: transação %s excedeu tentativas, removendo", tx.ID)
			tm.removePendingTransaction(tx.ID)
			continue
		}

		utils.RegistrarLog("INFO", "TokenManager: tentando sincronizar transação %s (tentativa %d)",
			tx.ID, tx.RetryCount+1)

		var err error
		switch tx.Type {
		case "escrow":
			err = tm.ledgerClient.CreateEscrow(tx.Company, tx.MissionID, tx.Amount)
		case "release":
			err = tm.ledgerClient.ReleaseEscrow(tx.MissionID, tm.brokerID, "", "")
		case "transfer":
			err = tm.ledgerClient.Transfer(tx.Company, "system", tx.Amount)
		}

		if err == nil {
			utils.RegistrarLog("INFO", "TokenManager: transação %s sincronizada", tx.ID)
			tm.removePendingTransaction(tx.ID)
		} else {
			tx.RetryCount++
			utils.RegistrarLog("AVISO", "TokenManager: falha ao sincronizar %s: %v", tx.ID, err)
		}
	}
}

// ============================================================================
// VALIDAÇÃO E PREVENÇÃO DE DOUBLE-SPEND
// ============================================================================

// hasActiveEscrow verifica se existe escrow ativo para uma missão
func (tm *TokenManager) hasActiveEscrow(missionID string) bool {
	status, err := tm.ledgerClient.GetEscrowStatus(missionID)
	if err != nil {
		return false
	}
	return status == ledger.EscrowStatusLocked
}

// ValidateAndDebit valida e debita créditos atomicamente
// Previne double-spend em operações concorrentes
func (tm *TokenManager) ValidateAndDebit(company, operationID string, amount int) (bool, error) {
	// Lock global para esta empresa
	lock := tm.getOperationLock(company)
	lock.Lock()
	defer lock.Unlock()

	// Get fresh balance
	balance, err := tm.GetBalance(company)
	if err != nil {
		return false, err
	}

	if balance < amount {
		utils.RegistrarLog("AVISO", "TokenManager: double-spend prevenido - %s tentou debitar %d mas tem %d",
			company, amount, balance)
		return false, nil
	}

	// Simula débito (será confirmado na ledger depois)
	tm.updateCache(company, balance-amount)

	utils.RegistrarLog("DEBUG", "TokenManager: débito de %d validado para %s (op=%s)", amount, company, operationID)
	return true, nil
}

// ============================================================================
// MÉTRICAS E STATUS
// ============================================================================

// GetMetrics retorna métricas do gerenciador
func (tm *TokenManager) GetMetrics() map[string]interface{} {
	tm.cacheMutex.RLock()
	defer tm.cacheMutex.RUnlock()

	return map[string]interface{}{
		"broker_id":     tm.brokerID,
		"cache_size":    len(tm.balanceCache),
		"pending_tx":    len(tm.pendingTx),
		"active_locks":  len(tm.operationLocks),
		"cache_ttl":     tm.cacheTTL.String(),
		"sync_interval": tm.syncInterval.String(),
	}
}

// Stop para o gerenciador
func (tm *TokenManager) Stop() {
	tm.executando = false
	close(tm.stopCh)
	tm.wg.Wait()
	utils.RegistrarLog("INFO", "TokenManager parado")
}
