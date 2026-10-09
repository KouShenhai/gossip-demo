# test1种子节点，test2集群节点

```shell
go mod tidy
```

```shell
sudo apt update
sudo apt install -y openssl
```

```shell
go env -w CGO_ENABLED=0
go env -w GOOS=linux
go env -w GOARCH=amd64
go build -o gossip main.go
```

```shell
go env -w CGO_ENABLED=0
go env -w GOOS=linux
go env -w GOARCH=arm64
go build -o gossip main.go
```
