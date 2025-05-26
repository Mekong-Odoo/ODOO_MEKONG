#!/bin/bash
# debug_odoo.sh - Script debug toàn diện cho EC2

echo "🔍 ODOO DEBUG TRÊN EC2 - 52.221.232.143"
echo "========================================"

# 1. KIỂM TRA CƠ BẢN
check_basic() {
    echo "📋 1. KIỂM TRA CƠ BẢN"
    echo "Docker version:" $(docker --version)
    echo "Docker Compose version:" $(docker-compose --version)
    echo "Available memory:" $(free -h | grep Mem | awk '{print $2}')
    echo "Available disk:" $(df -h / | tail -1 | awk '{print $4}')
    echo ""
}

# 2. KIỂM TRA CONTAINER
check_container() {
    echo "📦 2. KIỂM TRA CONTAINER"
    if docker ps | grep -q odoo_app; then
        echo "✅ Container đang chạy"
        echo "Container uptime:" $(docker ps --format "table {{.Names}}\t{{.Status}}" | grep odoo_app)

        # Kiểm tra CPU và Memory usage
        echo "Resource usage:"
        docker stats odoo_app --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    else
        echo "❌ Container không chạy"
        echo "Container status:"
        docker ps -a | grep odoo
    fi
    echo ""
}

# 3. KIỂM TRA NETWORK VÀ PORT
check_network() {
    echo "🌐 3. KIỂM TRA NETWORK VÀ PORT"

    # Kiểm tra port binding
    echo "Port binding:"
    docker port odoo_app 2>/dev/null || echo "❌ Không có port binding"

    # Kiểm tra port đang listen
    echo "Ports đang listen:"
    netstat -tulpn | grep -E ":(8069|8072)" || echo "❌ Port 8069/8072 không listen"

    # Test kết nối local
    echo "Test kết nối localhost:"
    timeout 5 curl -s -I http://localhost:8069/web >/dev/null && echo "✅ localhost:8069 OK" || echo "❌ localhost:8069 FAIL"

    # Test kết nối external IP
    echo "Test kết nối external IP:"
    timeout 10 curl -s -I http://52.221.232.143:8069/web >/dev/null && echo "✅ External IP OK" || echo "❌ External IP FAIL"

    echo ""
}

# 4. KIỂM TRA CẤU HÌNH
check_config() {
    echo "🔧 4. KIỂM TRA CẤU HÌNH"

    if docker exec odoo_app test -f /etc/odoo/odoo.conf; then
        echo "✅ Config file tồn tại"
        echo "Key configurations:"
        docker exec odoo_app grep -E "^(http_interface|http_port|proxy_mode|workers|db_host|db_name)" /etc/odoo/odoo.conf
    else
        echo "❌ Config file không tồn tại"
    fi
    echo ""
}

# 5. KIỂM TRA DATABASE
check_database() {
    echo "🗄️ 5. KIỂM TRA DATABASE"

    # Test database connection
    docker exec odoo_app python3 -c "
import psycopg2
import os
try:
    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        user=os.environ.get('DB_USER', 'odoo'),
        password=os.environ.get('DB_PASSWORD', ''),
        dbname=os.environ.get('DB_NAME', 'odoo')
    )
    print('✅ Database connection successful')

    cursor = conn.cursor()
    # Kiểm tra bảng cơ bản
    cursor.execute(\"SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'ir_module_module';\")
    if cursor.fetchone()[0] > 0:
        cursor.execute(\"SELECT COUNT(*) FROM ir_module_module WHERE state='installed';\")
        installed_count = cursor.fetchone()[0]
        print(f'✅ Database initialized: {installed_count} modules installed')
    else:
        print('⚠️ Database not initialized (no ir_module_module table)')

    conn.close()
except Exception as e:
    print(f'❌ Database connection failed: {e}')
" 2>/dev/null
    echo ""
}

# 6. KIỂM TRA LOG
check_logs() {
    echo "📋 6. KIỂM TRA LOG (20 dòng cuối)"

    echo "=== DOCKER LOGS ==="
    docker logs --tail=20 odoo_app 2>/dev/null | tail -10

    echo ""
    echo "=== ODOO LOG FILE ==="
    if docker exec odoo_app test -f /var/log/odoo/odoo.log; then
        docker exec odoo_app tail -10 /var/log/odoo/odoo.log
    else
        echo "❌ Log file không tồn tại"
    fi
    echo ""
}

# 7. KIỂM TRA HTTP RESPONSE CHI TIẾT
check_http_detailed() {
    echo "🌍 7. KIỂM TRA HTTP RESPONSE CHI TIẾT"

    echo "=== Test GET /web ==="
    curl -v -L --max-time 10 --max-redirs 5 http://52.221.232.143:8069/web 2>&1 | head -20

    echo ""
    echo "=== Test GET /web/database/selector ==="
    curl -v --max-time 10 http://52.221.232.143:8069/web/database/selector 2>&1 | head -15

    echo ""
}

# 8. KIỂM TRA FILES VÀ PERMISSIONS
check_files() {
    echo "📁 8. KIỂM TRA FILES VÀ PERMISSIONS"

    echo "Odoo data directory:"
    ls -la ./odoo_data/ 2>/dev/null | head -5 || echo "❌ Không truy cập được odoo_data"

    echo ""
    echo "Container internal directories:"
    docker exec odoo_app ls -la /var/lib/odoo/ 2>/dev/null | head -5 || echo "❌ Không truy cập được /var/lib/odoo"

    echo ""
    echo "Config directory:"
    docker exec odoo_app ls -la /etc/odoo/ 2>/dev/null || echo "❌ Không truy cập được /etc/odoo"

    echo ""
}

# MAIN EXECUTION
echo "Bắt đầu kiểm tra hệ thống..."
check_basic
check_container
check_network
check_config
check_database
check_logs
check_http_detailed
check_files

echo "🏁 HOÀN THÀNH KIỂM TRA"
echo "====================="

# TÓM TẮT VÀ ĐỀ XUẤT
echo "📊 TÓM TẮT:"
if docker ps | grep -q odoo_app && netstat -tulpn | grep -q :8069; then
    echo "✅ Container và port đang hoạt động"
    if timeout 5 curl -s http://localhost:8069/web >/dev/null; then
        echo "✅ HTTP response OK"
        echo "🎯 Hệ thống có vẻ hoạt động bình thường"
        echo "💡 Nếu vẫn không truy cập được, kiểm tra Security Group EC2"
    else
        echo "❌ HTTP response không OK"
        echo "💡 Cần kiểm tra log và cấu hình Odoo"
    fi
else
    echo "❌ Container hoặc port có vấn đề"
    echo "💡 Cần khởi động lại container"
fi
