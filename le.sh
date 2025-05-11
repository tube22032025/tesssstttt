#!/bin/bash
# Script tự động cài đặt Docker và triển khai Windows 10 trong container
# Phiên bản: 2.0
# Ngày cập nhật: 09/05/2025

# Hàm kiểm tra lỗi
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ Lỗi: $1"
        echo "🔄 Đang thử phương án thay thế..."
        return 1
    fi
    return 0
}

# Hàm kiểm tra và tạo backup
create_backup() {
    if [ -f "$1" ]; then
        echo "📦 Tạo bản sao lưu của $1 tại $1.bak"
        cp "$1" "$1.bak"
    fi
}

# Hàm kiểm tra cổng đã sử dụng
check_port() {
    if netstat -tuln | grep -q ":$1 "; then
        echo "⚠️ Cổng $1 đã được sử dụng. Sẽ sử dụng cổng $2 thay thế."
        return 1
    fi
    return 0
}

# Đảm bảo script chạy với quyền root
if [ "$(id -u)" -ne 0 ]; then
    echo "🔒 Script cần được chạy với quyền root. Đang chuyển sang quyền root..."
    exec sudo "$0" "$@"
    exit 1
fi

echo "🚀 === Bắt đầu quá trình cài đặt tự động ==="

# Kiểm tra hệ điều hành
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    CODENAME=$VERSION_CODENAME
    echo "🖥️ Hệ điều hành: $OS $VER ($CODENAME)"
else
    echo "❌ Không thể xác định hệ điều hành. Đang sử dụng cấu hình mặc định."
    OS="Ubuntu"
    CODENAME="focal"
fi

echo "🔄 Đang cập nhật hệ thống..."
apt-get update -y
check_error "Không thể cập nhật hệ thống" || exit 1

echo "📦 Đang cài đặt các gói cần thiết..."
apt-get install -y ca-certificates curl gnupg apt-transport-https lsb-release
check_error "Không thể cài đặt các gói cần thiết" || exit 1

echo "🧹 Đang gỡ bỏ các phiên bản Docker cũ nếu có..."
apt-get remove -y docker docker-engine docker.io containerd runc moby-tini moby-buildx moby-runc || true
apt-get autoremove -y

echo "🔑 Đang thêm khóa GPG của Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
check_error "Không thể thêm khóa GPG của Docker" || exit 1

echo "📋 Đang thêm repository Docker..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
check_error "Không thể thêm repository Docker" || {
    echo "⚠️ Không thể thêm repository chính thức. Đang sử dụng repository thay thế..."
    apt-get install -y docker.io
}

echo "🔄 Đang cập nhật lại danh sách gói..."
apt-get update -y
check_error "Không thể cập nhật danh sách gói" || exit 1

echo "🐳 Đang cài đặt Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if check_error "Không thể cài đặt Docker từ repository chính thức"; then
    echo "✅ Cài đặt Docker thành công!"
else
    echo "⚠️ Đang thử cài đặt Docker từ repository Ubuntu..."
    apt-get install -y docker.io
    check_error "Không thể cài đặt Docker từ repository Ubuntu" || exit 1
fi

echo "🔄 Đang cài đặt Docker Compose..."
if command -v docker-compose &> /dev/null; then
    echo "✅ Docker Compose đã được cài đặt!"
else
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    check_error "Không thể cài đặt Docker Compose" || {
        echo "⚠️ Đang thử cài đặt Docker Compose qua apt..."
        apt-get install -y docker-compose
    }
fi

echo "🔄 Đang kích hoạt Docker service..."
if command -v systemctl &> /dev/null; then
    systemctl enable --now docker
    check_error "Không thể kích hoạt Docker service qua systemctl" || {
        echo "⚠️ Đang thử kích hoạt Docker service qua service..."
        service docker start
    }
else
    service docker start
    check_error "Không thể kích hoạt Docker service" || true
fi

echo "🔍 Kiểm tra Docker đã cài đặt thành công..."
if docker --version; then
    echo "✅ Docker đã cài đặt thành công!"
else
    echo "❌ Docker chưa được cài đặt đúng cách. Vui lòng kiểm tra lại."
    exit 1
fi

echo "🔍 Kiểm tra Docker Compose đã cài đặt thành công..."
if docker-compose --version || docker compose version; then
    echo "✅ Docker Compose đã cài đặt thành công!"
else
    echo "❌ Docker Compose chưa được cài đặt đúng cách. Vui lòng kiểm tra lại."
    exit 1
fi

echo "🔍 Kiểm tra docker-proxy..."
if [ ! -f /usr/bin/docker-proxy ]; then
    echo "⚠️ Không tìm thấy docker-proxy. Đang tạo liên kết..."
    DOCKER_PROXY_PATH=$(find /usr -name docker-proxy 2>/dev/null | head -n 1)
    if [ -n "$DOCKER_PROXY_PATH" ]; then
        ln -s "$DOCKER_PROXY_PATH" /usr/bin/docker-proxy
    else
        echo "⚠️ Không thể tìm thấy docker-proxy trong hệ thống."
    fi
fi

echo "🔍 Kiểm tra quyền truy cập KVM..."
if [ ! -c /dev/kvm ]; then
    echo "⚠️ Thiết bị KVM không tồn tại. Virtualization có thể chưa được bật trong BIOS hoặc hệ thống của bạn không hỗ trợ."
    echo "⚠️ Windows container có thể không hoạt động đúng cách."
    SUPPORTS_KVM=false
else
    chmod 666 /dev/kvm 2>/dev/null || true
    SUPPORTS_KVM=true
    echo "✅ KVM được hỗ trợ và đã cấu hình đúng!"
fi

echo "🔍 Kiểm tra cổng RDP (3389)..."
DEFAULT_RDP_PORT=3389
ALTERNATE_RDP_PORT=13389
if check_port $DEFAULT_RDP_PORT $ALTERNATE_RDP_PORT; then
    RDP_PORT=$DEFAULT_RDP_PORT
    echo "✅ Cổng RDP $RDP_PORT khả dụng."
else
    RDP_PORT=$ALTERNATE_RDP_PORT
    echo "🔄 Sẽ sử dụng cổng RDP $RDP_PORT thay thế."
fi

echo "📝 Đang tạo file cấu hình Windows 10..."
create_backup "windows10.yml"

cat > windows10.yml << EOL
version: '3'

services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "10"
      USERNAME: "MASTER"
      PASSWORD: "admin@123"
      RAM_SIZE: "4G"
      CPU_CORES: "4"
      DISK_SIZE: "400G"
      DISK2_SIZE: "100G"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "${RDP_PORT}:3389/tcp"
      - "${RDP_PORT}:3389/udp"
      - "8006:8006"
    restart: unless-stopped
    stop_grace_period: 2m
EOL

if [ "$SUPPORTS_KVM" = false ]; then
    echo "⚠️ Đang điều chỉnh cấu hình do không có KVM..."
    sed -i '/devices:/d' windows10.yml
    sed -i '/- \/dev\/kvm/d' windows10.yml
fi

echo "✅ File cấu hình windows10.yml đã được tạo thành công!"

echo "🚀 Đang khởi chạy Windows 10 container..."
docker-compose -f windows10.yml up -d
if check_error "Không thể khởi chạy Windows 10 container"; then
    echo "✅ Windows 10 container đã được khởi chạy thành công!"
else
    echo "⚠️ Đang thử phương án thay thế..."
    docker compose -f windows10.yml up -d
    check_error "Không thể khởi chạy Windows 10 container với docker compose" || {
        echo "❌ Không thể khởi chạy Windows 10 container. Vui lòng kiểm tra lại cấu hình."
        exit 1
    }
fi

echo ""
echo "✅ === Cài đặt hoàn tất ==="
echo "🖥️ Windows 10 đang được khởi động trong container Docker."
echo "🔗 Bạn có thể kết nối qua RDP tới máy chủ này qua cổng $RDP_PORT"
echo "👤 Thông tin đăng nhập:"
echo "   Username: MASTER"
echo "   Password: admin@123"
echo ""
echo "🛠️ Các lệnh hữu ích:"
echo "   Kiểm tra trạng thái: docker ps"
echo "   Xem logs: docker logs windows"
echo "   Dừng container: docker-compose -f windows10.yml down"
echo "   Khởi động lại: docker-compose -f windows10.yml restart"
echo ""
echo "⚠️ Lưu ý: Quá trình khởi động Windows 10 có thể mất vài phút."
echo "   Hãy kiểm tra logs để biết trạng thái: docker logs -f windows"
