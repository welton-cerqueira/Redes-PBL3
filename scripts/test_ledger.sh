cat > ~/Redes-PBL3/scripts/test_ledger.sh << 'EOF'
#!/bin/bash

echo "=== Teste de Integração com Ledger ==="

cd ~/fabric-samples/test-network

docker exec cli bash -c "
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem
  export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
  export CORE_PEER_ADDRESS=peer0.org1.example.com:7051

  echo ''
  echo '📊 Resumo das missões:'
  peer chaincode query -C ormuz-channel -n mission -c '{\"Args\":[\"GetMissionSummary\"]}' | jq . 2>/dev/null || peer chaincode query -C ormuz-channel -n mission -c '{\"Args\":[\"GetMissionSummary\"]}'

  echo ''
  echo '📋 Todas as missões:'
  peer chaincode query -C ormuz-channel -n mission -c '{\"Args\":[\"GetAllMissionLogs\",\"10\",\"0\"]}' | jq . 2>/dev/null || peer chaincode query -C ormuz-channel -n mission -c '{\"Args\":[\"GetAllMissionLogs\",\"10\",\"0\"]}'

  echo ''
  echo '💰 Saldo da companyA:'
  peer chaincode query -C ormuz-channel -n token -c '{\"Args\":[\"GetBalance\",\"companyA\"]}'
"

echo ""
echo "=== Teste concluído ==="
EOF

chmod +x ~/Redes-PBL3/scripts/test_ledger.sh