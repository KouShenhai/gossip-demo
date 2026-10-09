#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# 局域网 CA 配置
# =========================
OUT_DIR="./certs"
DAYS=7300

CA_CN="KCloud IoT Local CA"
ORG="KCloud IoT"

# 网关名称与 IP 地址
declare -A GATEWAYS=(
  ["test1"]="192.168.1.109"
  ["test2"]="192.168.1.122"
)

command -v openssl >/dev/null 2>&1 || {
  echo "错误：未安装 OpenSSL"
  exit 1
}

mkdir -p "$OUT_DIR"
umask 077

# 防止误覆盖已有私钥或证书
if [[ -e "$OUT_DIR/ca.key" || -e "$OUT_DIR/ca.crt" ]]; then
  echo "错误：$OUT_DIR 中已存在 CA 文件。"
  echo "为避免覆盖现有 CA，请备份后更换输出目录或手动处理。"
  exit 1
fi

for name in "${!GATEWAYS[@]}"; do
  if [[ -e "$OUT_DIR/$name.key" || -e "$OUT_DIR/$name.crt" ]]; then
    echo "错误：$OUT_DIR/$name.key 或 $OUT_DIR/$name.crt 已存在。"
    exit 1
  fi
done

# =========================
# 1. 生成 CA 私钥和根证书
# =========================
echo "==> 生成 CA 私钥"

openssl genrsa \
  -out "$OUT_DIR/ca.key" 4096

cat > "$OUT_DIR/ca.ext" <<'EOF'
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

echo "==> 生成 CA 根证书"

openssl req -x509 -new \
  -key "$OUT_DIR/ca.key" \
  -sha256 \
  -days "$DAYS" \
  -subj "/O=$ORG/CN=$CA_CN" \
  -out "$OUT_DIR/ca.crt" \
  -extensions v3_ca \
  -config <(
    cat <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no
[dn]
[v3_ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF
  )

# =========================
# 2. 为每台网关生成私钥与证书
# =========================
for name in "${!GATEWAYS[@]}"; do
  ip="${GATEWAYS[$name]}"

  echo "==> 生成 $name ($ip) 私钥"

  openssl genrsa \
    -out "$OUT_DIR/$name.key" 2048

  echo "==> 生成 $name 证书请求"

  openssl req -new \
    -key "$OUT_DIR/$name.key" \
    -out "$OUT_DIR/$name.csr" \
    -subj "/O=$ORG/OU=Edge Gateways/CN=$name"

  # 证书扩展：同时配置 DNS 名称与 IP SAN
  cat > "$OUT_DIR/$name.ext" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = @alt_names

[alt_names]
DNS.1 = $name
IP.1 = $ip
EOF

  echo "==> 签发 $name 证书（有效期约 20 年）"

  openssl x509 -req \
    -in "$OUT_DIR/$name.csr" \
    -CA "$OUT_DIR/ca.crt" \
    -CAkey "$OUT_DIR/ca.key" \
    -CAcreateserial \
    -out "$OUT_DIR/$name.crt" \
    -days "$DAYS" \
    -sha256 \
    -extfile "$OUT_DIR/$name.ext"

  # 校验签名与 IP SAN
  openssl verify \
    -CAfile "$OUT_DIR/ca.crt" \
    -verify_ip "$ip" \
    "$OUT_DIR/$name.crt"

  # CSR 和扩展配置无需分发
  rm -f "$OUT_DIR/$name.csr" "$OUT_DIR/$name.ext"
done

# =========================
# 3. 权限设置
# =========================
chmod 600 "$OUT_DIR/ca.key" \
          "$OUT_DIR/test1.key" \
          "$OUT_DIR/test2.key"

chmod 644 "$OUT_DIR/ca.crt" \
          "$OUT_DIR/test1.crt" \
          "$OUT_DIR/test2.crt"

echo
echo "===================================="
echo "证书生成完成"
echo "===================================="
find "$OUT_DIR" -maxdepth 1 -type f -printf '%f\n' | sort

echo
echo "test1: 192.168.1.109"
echo "test2: 192.168.1.122"
echo "有效期：$DAYS 天（约 20 年）"
echo "根证书：$OUT_DIR/ca.crt"
echo "===================================="
