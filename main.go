package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"github.com/wjordan/gossip-mesh/membership"
	"github.com/wjordan/gossip-mesh/mesh"
	"log"
	"os"
	"time"
)

func main() {
	// nodeId := "test1"
	tlsCfg, err := LoadTLSConfig(
		"./certs/ca.crt",
		//"./certs/test1.crt",
		"./certs/test2.crt",
		//"./certs/test1.key",
		"./certs/test2.key",
	)
	if err != nil {
		fmt.Println(err)
	}
	nodeId := "test2"
	m, err := mesh.Join(mesh.Config{
		NodeID:    nodeId,
		BindAddr:  "0.0.0.0",
		BindPort:  7946,
		SeedAddrs: []string{"192.168.1.109:7946"},
		TLS:       tlsCfg,
		Meta: membership.NodeMeta{
			// QUICAddr: "192.168.1.109",
			QUICAddr: "192.168.1.122",
			QUICPort: 7947,
		},
	})
	if err != nil {
		fmt.Println(err.Error())
	}
	defer m.Leave()
	log.Printf("启动成功")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 关键：启动 Gossip 引擎
	go m.Engine.Run(ctx)
	// 接收所有节点传播过来的消息。
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case entry := <-m.Engine.Deliver():
				log.Printf(
					"[RECEIVED] topic=%d seq=%d payload=%s",
					entry.Topic,
					entry.Seq,
					string(entry.Payload),
				)
			}
		}
	}()

	// 等引擎启动后，再发送测试消息
	time.Sleep(time.Second)
	m.Engine.Enqueue(100, 1, []byte("hello from test1"))

	select {}
}

func LoadTLSConfig(
	caCertFile string,
	nodeCertFile string,
	nodeKeyFile string,
) (*tls.Config, error) {

	// 1. 加载当前网关自己的证书和私钥
	nodeCert, err := tls.LoadX509KeyPair(
		nodeCertFile,
		nodeKeyFile,
	)
	if err != nil {
		return nil, fmt.Errorf("加载网关证书失败: %w", err)
	}

	// 2. 读取自建 CA 根证书
	caCertPEM, err := os.ReadFile(caCertFile)
	if err != nil {
		return nil, fmt.Errorf("读取 CA 根证书失败: %w", err)
	}

	// 3. 创建 CA 信任池
	caPool := x509.NewCertPool()
	if ok := caPool.AppendCertsFromPEM(caCertPEM); !ok {
		return nil, fmt.Errorf("解析 CA 根证书失败")
	}

	// 4. 配置双向 TLS
	tlsCfg := &tls.Config{
		MinVersion: tls.VersionTLS13,

		// 当前网关自己的身份
		Certificates: []tls.Certificate{nodeCert},

		// 验证对端服务端证书
		RootCAs: caPool,

		// 验证对端客户端证书
		ClientCAs: caPool,

		// 强制要求客户端提供有效证书
		ClientAuth: tls.RequireAndVerifyClientCert,
	}

	return tlsCfg, nil
}
