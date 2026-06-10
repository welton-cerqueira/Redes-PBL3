#!/bin/bash

echo "=== Teste de Integração com Ledger ==="

# Teste do chaincode token
docker exec cli peer chaincode query \
  -C ormuz-channel \
  -n token \
  -c '{"Args":["GetBalance","companyA"]}' \
  && echo "✅ Token chaincode OK" || echo "❌ Token chaincode falhou"

# Teste do chaincode mission
docker exec cli peer chaincode invoke \
  -C ormuz-channel \
  -n token \
  -c '{"Args":["Transfer","companyA","broker-1","10"]}' \
  --waitForEvent

docker exec cli peer chaincode query \
  -C ormuz-channel \
  -n mission \
  -c '{"Args":["GetMissionSummary"]}' \
  && echo "✅ Mission chaincode OK" || echo "❌ Mission chaincode falhou"

echo "=== Teste concluído ==="