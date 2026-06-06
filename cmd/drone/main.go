package main

import (
	"bufio"
	"crypto/ed25519"
	cryptorand "crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"net"
	"os"
	"strings"
	"time"
)

var (
	privateKey ed25519.PrivateKey
	publicKey  ed25519.PublicKey
)

func init() {
	// Gera par de chaves para o drone
	var err error
	publicKey, privateKey, err = ed25519.GenerateKey(cryptorand.Reader)
	if err != nil {
		panic(fmt.Sprintf("Falha ao gerar chaves: %v", err))
	}
	fmt.Printf("[CRYPTO] Chave pública do drone: %s\n", hex.EncodeToString(publicKey)[:16]+"...")
}

type comandoDrone struct {
	Tipo           string    `json:"tipo"`
	DroneID        string    `json:"drone_id"`
	RequisicaoID   string    `json:"requisicao_id"`
	SetorID        string    `json:"setor_id"`
	CallbackBroker string    `json:"callback_broker"`
	CarimboTempo   time.Time `json:"carimbo_tempo"`
}

type LaudoMissao struct {
	MissionID   string    `json:"missionId"`
	DroneID     string    `json:"droneId"`
	Timestamp   time.Time `json:"timestamp"`
	Waypoints   []string  `json:"waypoints"`
	Events      []string  `json:"events"`
	Telemetry   string    `json:"telemetry"`
	FinalReport string    `json:"finalReport"`
	LaudoHash   string    `json:"laudoHash"`
	Signature   string    `json:"signature"`
	PublicKey   string    `json:"publicKey"`
}

func main() {
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	droneID := flag.String("id", env("DRONE_ID", "drone-01"), "ID do drone")
	porta := flag.String("port", env("DRONE_PORT", ":9101"), "porta tcp")
	flag.Parse()

	prefixo := fmt.Sprintf("[DRONE-%s]", strings.ToUpper(strings.TrimPrefix(*droneID, "drone-")))
	listener, err := net.Listen("tcp", *porta)
	if err != nil {
		panic(err)
	}
	defer listener.Close()
	fmt.Printf("%s iniciado em %s estado=DISPONIVEL\n", prefixo, *porta)
	fmt.Printf("%s Chave pública: %s\n", prefixo, hex.EncodeToString(publicKey)[:16]+"...")

	for {
		conn, err := listener.Accept()
		if err != nil {
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			linha, err := bufio.NewReader(c).ReadBytes('\n')
			if err != nil {
				return
			}
			var cmd comandoDrone
			if err := json.Unmarshal(linha, &cmd); err != nil {
				return
			}
			if cmd.Tipo != "START_MISSION" || cmd.DroneID != *droneID {
				return
			}
			fmt.Printf("%s req=%s setor=%s estado=EM_MISSAO\n", prefixo, cmd.RequisicaoID, cmd.SetorID)

			// Simula execução da missão
			time.Sleep(time.Duration(5+rng.Intn(10)) * time.Second)

			// Gera laudo da missão
			laudo := gerarLaudo(cmd.RequisicaoID, *droneID, rng)

			// Assina o laudo
			laudoJSON, _ := json.Marshal(laudo)
			signature := ed25519.Sign(privateKey, laudoJSON)
			laudo.Signature = hex.EncodeToString(signature)
			laudo.PublicKey = hex.EncodeToString(publicKey)

			// Calcula hash do laudo
			laudo.LaudoHash = calcularHash(laudoJSON)

			fmt.Printf("%s req=%s concluida estado=DISPONIVEL laudoHash=%s\n",
				prefixo, cmd.RequisicaoID, laudo.LaudoHash[:16])

			notificarDisponivel(*droneID, cmd.RequisicaoID, cmd.CallbackBroker, laudo)
		}(conn)
	}
}

// gerarLaudo cria um laudo simulado da missão
func gerarLaudo(missionID, droneID string, rng *rand.Rand) *LaudoMissao {
	return &LaudoMissao{
		MissionID:   missionID,
		DroneID:     droneID,
		Timestamp:   time.Now(),
		Waypoints:   []string{"pontoA", "pontoB", "pontoC"},
		Events:      []string{"monitoramento_normal"},
		Telemetry:   fmt.Sprintf("bateria=%d%%, velocidade=%.1fkm/h", 75+rng.Intn(20), 30+rng.Float64()*20),
		FinalReport: "Missão concluída com sucesso. Nenhuma anomalia detectada.",
	}
}

// calcularHash calcula um hash para o laudo
func calcularHash(data []byte) string {
	hash := ed25519.Sign(privateKey, data)
	return hex.EncodeToString(hash)
}

func notificarDisponivel(droneID, reqID, callback string, laudo *LaudoMissao) {
	callback = strings.TrimSpace(callback)
	if callback == "" {
		return
	}
	conn, err := net.DialTimeout("tcp", callback, 3*time.Second)
	if err != nil {
		return
	}
	defer conn.Close()

	msg := map[string]interface{}{
		"tipo":          "DRONE_DISPONIVEL",
		"origem_id":     droneID,
		"carimbo_tempo": time.Now(),
		"dados": map[string]interface{}{
			"drone_id":      droneID,
			"requisicao_id": reqID,
			"estado":        "DISPONIVEL",
			"laudo_hash":    laudo.LaudoHash,
			"laudo_cid":     "", // Seria o CID do IPFS
			"signature":     laudo.Signature,
			"public_key":    laudo.PublicKey,
			"laudo_dados":   laudo,
		},
	}
	dados, _ := json.Marshal(msg)
	_, _ = conn.Write(append(dados, '\n'))
}

func env(chave, padrao string) string {
	v := strings.TrimSpace(os.Getenv(chave))
	if v == "" {
		return padrao
	}
	return v
}
