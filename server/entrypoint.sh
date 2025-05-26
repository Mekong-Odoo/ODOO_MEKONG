#!/bin/bash
set -e

# Thiết lập locale để tránh cảnh báo
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Thiết lập biến môi trường để tránh lỗi HTTP server
export PYTHONUNBUFFERED=1
export GEVENT_SUPPORT=True

# File marker để theo dõi trạng thái khởi tạo
INIT_MARKER="/var/lib/odoo/.odoo_initialized"
DB_READY_MARKER="/var/lib/odoo/.db_ready_${DB_NAME}"

echo "🔍 Đang kiểm tra cài đặt Odoo..."

# Tìm đúng đường dẫn tới binary Odoo
if [ -f "/usr/bin/odoo" ]; then
    ODOO_CMD="/usr/bin/odoo"
elif [ -f "/usr/local/bin/odoo" ]; then
    ODOO_CMD="/usr/local/bin/odoo"
elif [ -f "/opt/odoo/odoo-bin" ]; then
    ODOO_CMD="/opt/odoo/odoo-bin"
elif command -v odoo > /dev/null 2>&1; then
    ODOO_CMD="odoo"
elif command -v odoo-bin > /dev/null 2>&1; then
    ODOO_CMD="odoo-bin"
else
    echo "❌ Không tìm thấy binary Odoo!"
    ODOO_BIN_PATH=$(find / -name "odoo*" -type f -executable 2>/dev/null | head -n 1)
    if [ -n "$ODOO_BIN_PATH" ]; then
        ODOO_CMD="$ODOO_BIN_PATH"
        echo "✅ Tìm thấy binary Odoo tại: $ODOO_CMD"
    else
        echo "❌ Không tìm thấy binary Odoo!"
        exit 1
    fi
fi

echo "🔧 Sử dụng binary Odoo: $ODOO_CMD"

# Kiểm tra và sửa lỗi thư viện Python
fix_python_issues() {
    echo "🔧 Kiểm tra và sửa lỗi thư viện Python..."

    # Kiểm tra phiên bản Werkzeug
    python3 -c "import werkzeug; print(f'Werkzeug version: {werkzeug.__version__}')" 2>/dev/null || {
        echo "⚠️ Lỗi import Werkzeug, cài đặt lại..."
        pip3 install --no-cache-dir --break-system-packages --force-reinstall werkzeug==2.0.3
    }

    # Kiểm tra các thư viện cần thiết khác
    python3 -c "
import sys
try:
    import gevent
    import eventlet
    print('✅ Gevent và Eventlet sẵn sàng')
except ImportError as e:
    print(f'⚠️ Thiếu thư viện: {e}')
    sys.exit(1)
" || {
        echo "🔧 Cài đặt lại các thư viện HTTP server..."
        pip3 install --no-cache-dir --break-system-packages gevent eventlet
    }
}

# Tạo thư mục cần thiết một lần duy nhất
setup_directories() {
    echo "🔧 Thiết lập thư mục..."
    if [ "$(id -u)" = "0" ]; then
        mkdir -p /var/run/odoo /var/log/odoo /var/lib/odoo
        mkdir -p /var/lib/odoo/filestore/${DB_NAME}
        mkdir -p /var/lib/odoo/sessions
        chown -R odoo:odoo /var/run/odoo /var/log/odoo /var/lib/odoo
        chmod -R 775 /var/lib/odoo
        echo "✅ Đã thiết lập thư mục với quyền root"
    else
        mkdir -p /var/lib/odoo/filestore/${DB_NAME}
        mkdir -p /var/lib/odoo/sessions
        echo "✅ Đã thiết lập thư mục cơ bản"
    fi
}

# Tạo file cấu hình với các tham số HTTP server được tối ưu - KHÔNG trùng lặp
setup_config() {
    echo "🔧 Tạo file cấu hình..."

    # Tạo config trong thư mục tmp trước, sau đó copy để tránh lỗi quyền
    local temp_config="/tmp/odoo.conf"

    if [ -f "/etc/odoo/odoo.conf.template" ]; then
        # Sử dụng template có sẵn
        envsubst < /etc/odoo/odoo.conf.template > "$temp_config"
        echo "✅ Đã tạo config từ template"

        # Kiểm tra và thêm các tùy chọn nếu chưa có
        echo "🔧 Kiểm tra và cập nhật các tùy chọn cấu hình..."

        # Hàm để thêm hoặc cập nhật tùy chọn trong file config (sử dụng temp file)
        update_config_option() {
            local option=$1
            local value=$2
            local config_file="$temp_config"

            if grep -q "^${option}\s*=" "$config_file"; then
                # Tùy chọn đã tồn tại, tạo file mới thay vì sed in-place
                grep -v "^${option}\s*=" "$config_file" > "${config_file}.tmp"
                echo "${option} = ${value}" >> "${config_file}.tmp"
                mv "${config_file}.tmp" "$config_file"
                echo "  ↻ Cập nhật: ${option} = ${value}"
            else
                # Tùy chọn chưa tồn tại, thêm vào
                echo "${option} = ${value}" >> "$config_file"
                echo "  ＋ Thêm: ${option} = ${value}"
            fi
        }

        # Cập nhật các tùy chọn HTTP server
        update_config_option "max_cron_threads" "2"
        update_config_option "workers" "0"
        update_config_option "server_wide_modules" "base,web"
        update_config_option "proxy_mode" "True"

    else
        # Tạo config cơ bản nếu không có template
        echo "⚠️ Không tìm thấy template, tạo config cơ bản..."
        cat > "$temp_config" << EOF
[options]
addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/custom_modules
data_dir = /var/lib/odoo
db_host = ${DB_HOST:-localhost}
db_port = ${DB_PORT:-5432}
db_user = ${DB_USER:-odoo}
db_password = ${DB_PASSWORD:-odoo}
logfile = /var/log/odoo/odoo.log
log_level = info
max_cron_threads = 2
workers = 0
server_wide_modules = base,web
proxy_mode = True
EOF
    fi

    # Copy file config từ temp sang vị trí cuối cùng
    cp "$temp_config" /etc/odoo/odoo.conf
    chmod 644 /etc/odoo/odoo.conf

    if [ "$(id -u)" = "0" ]; then
        chown odoo:odoo /etc/odoo/odoo.conf
    fi

    # Xóa temp file
    rm -f "$temp_config" "${temp_config}.tmp"

    echo "✅ File cấu hình đã được tạo với tối ưu HTTP server (không trùng lặp)"

    # Hiển thị nội dung config để debug
    echo "📋 Nội dung file cấu hình:"
    cat /etc/odoo/odoo.conf | head -20
}

# Kiểm tra kết nối PostgreSQL với timeout ngắn hơn
check_postgres() {
    echo "🔍 Kiểm tra kết nối PostgreSQL..."
    local max_retries=3
    local counter=0
    local wait_time=2

    while ! PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c "SELECT 1" > /dev/null 2>&1; do
        counter=$((counter+1))
        if [ $counter -ge $max_retries ]; then
            echo "❌ Không thể kết nối PostgreSQL sau $max_retries lần thử."
            return 1
        fi
        echo "⏳ Đợi PostgreSQL... ($counter/$max_retries)"
        sleep $wait_time
    done

    echo "✅ Kết nối PostgreSQL thành công"
    return 0
}

# Kiểm tra database đã tồn tại và đã được khởi tạo chưa
check_database_status() {
    local db_exists=false
    local db_initialized=false

    # Kiểm tra database có tồn tại không
    if PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
        "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
        db_exists=true
        echo "✅ Database ${DB_NAME} đã tồn tại"

        # Kiểm tra database đã được khởi tạo chưa (có bảng ir_module_module)
        if PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} \
            -c "SELECT 1 FROM pg_tables WHERE tablename = 'ir_module_module';" | grep -q 1; then

            # Kiểm tra có ít nhất 1 module được cài đặt
            local installed_count=$(PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -t \
                -c "SELECT COUNT(*) FROM ir_module_module WHERE state='installed';")

            if [ "$installed_count" -gt 0 ]; then
                db_initialized=true
                echo "✅ Database đã được khởi tạo với $installed_count module"

                # Tạo marker file
                touch "$DB_READY_MARKER"
            fi
        fi
    fi

    echo "$db_exists,$db_initialized"
}

# Khởi tạo database chỉ khi cần thiết với HTTP server tối ưu
initialize_database() {
    echo "⚙️ Khởi tạo database ${DB_NAME}..."

    # Tạo database nếu chưa tồn tại
    if ! PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
        "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
        echo "📦 Tạo database ${DB_NAME}..."
        PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
            "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";"
    fi

    # Khởi tạo với module cơ bản và worker = 0 để tránh lỗi HTTP
    echo "📦 Cài đặt module cơ bản (base, web)..."
    local core_modules="base,web"

    if [ "$(id -u)" = "0" ]; then
        gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${core_modules} --stop-after-init --log-level=warn --workers=0
    else
        $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${core_modules} --stop-after-init --log-level=warn --workers=0
    fi

    # Tạo marker để đánh dấu đã khởi tạo
    touch "$DB_READY_MARKER"
    echo "✅ Database đã được khởi tạo"
}

# Kiểm tra filestore nhanh và hiệu quả
quick_filestore_check() {
    echo "🔍 Kiểm tra nhanh filestore..."

    local filestore_path="/var/lib/odoo/filestore/${DB_NAME}"

    # Tạo thư mục nếu chưa có
    if [ ! -d "$filestore_path" ]; then
        echo "📁 Tạo thư mục filestore..."
        mkdir -p "$filestore_path"
        if [ "$(id -u)" = "0" ]; then
            chown -R odoo:odoo "$filestore_path"
        fi
        chmod -R 775 "$filestore_path"
    fi

    # Kiểm tra quyền truy cập cơ bản
    if [ -w "$filestore_path" ]; then
        echo "✅ Filestore có thể ghi"

        # Chạy script kiểm tra chi tiết trong background (không chặn khởi động)
        if [ -f "/usr/local/bin/fix_file_references.py" ]; then
            echo "🔧 Chạy kiểm tra filestore trong background..."
            export FILESTORE_PATH=/var/lib/odoo/filestore

            if [ "$(id -u)" = "0" ]; then
                (gosu odoo python3 /usr/local/bin/fix_file_references.py > /var/log/odoo/filestore_check.log 2>&1 &)
            else
                (python3 /usr/local/bin/fix_file_references.py > /var/log/odoo/filestore_check.log 2>&1 &)
            fi
        fi
    else
        echo "⚠️ Không thể ghi vào filestore, sửa quyền..."
        if [ "$(id -u)" = "0" ]; then
            chown -R odoo:odoo "$filestore_path"
        fi
        chmod -R 775 "$filestore_path"
    fi
}

# === MAIN EXECUTION ===

# Thêm error handling để tránh restart loop
handle_error() {
    echo "❌ Lỗi xảy ra trong quá trình khởi tạo: $1"
    echo "⏸️ Tạm dừng 30 giây để tránh restart loop..."
    sleep 30
    exit 1
}

# Sửa lỗi thư viện Python trước
echo "🔄 Bước 1: Kiểm tra thư viện Python..."
if ! fix_python_issues; then
    handle_error "Lỗi khi kiểm tra thư viện Python"
fi

# Luôn thiết lập thư mục và cấu hình
echo "🔄 Bước 2: Thiết lập thư mục..."
if ! setup_directories; then
    handle_error "Lỗi khi thiết lập thư mục"
fi

echo "🔄 Bước 3: Tạo file cấu hình..."
if ! setup_config; then
    handle_error "Lỗi khi tạo file cấu hình"
fi

# Kiểm tra PostgreSQL
echo "🔄 Bước 4: Kiểm tra PostgreSQL..."
if ! check_postgres; then
    echo "⚠️ Không thể kết nối PostgreSQL, nhưng sẽ tiếp tục khởi động..."
else
    echo "🔄 Bước 5: Kiểm tra database..."
    # Kiểm tra trạng thái database
    db_status=$(check_database_status)
    db_exists=$(echo $db_status | cut -d',' -f1)
    db_initialized=$(echo $db_status | cut -d',' -f2)

    # Chỉ khởi tạo database khi thực sự cần thiết
    if [ "$db_exists" = "false" ] || [ "$db_initialized" = "false" ]; then
        if [ ! -f "$DB_READY_MARKER" ]; then
            echo "🆕 Database chưa sẵn sàng, thực hiện khởi tạo..."
            if ! initialize_database; then
                handle_error "Lỗi khi khởi tạo database"
            fi
        else
            echo "✅ Database marker tồn tại, bỏ qua khởi tạo"
        fi
    else
        echo "✅ Database đã sẵn sàng, bỏ qua khởi tạo"
    fi
fi

# Kiểm tra filestore nhanh
echo "🔄 Bước 6: Kiểm tra filestore..."
if ! quick_filestore_check; then
    echo "⚠️ Lỗi khi kiểm tra filestore, nhưng sẽ tiếp tục..."
fi

# Tạo marker tổng thể
touch "$INIT_MARKER"

echo "🚀 Khởi động Odoo với HTTP server được tối ưu..."

# Kiểm tra file config một lần cuối
if [ ! -f "/etc/odoo/odoo.conf" ]; then
    handle_error "File cấu hình không tồn tại"
fi

echo "✅ Tất cả các bước kiểm tra đã hoàn thành!"
echo "💡 Bắt đầu khởi động Odoo server..."

# Chạy Odoo với tham số HTTP server được tối ưu
if [ "$(id -u)" = "0" ]; then
    if [[ "$1" == "odoo" ]] || [[ "$1" == "" ]]; then
        echo "💡 Khởi động Odoo server với workers=0 và proxy_mode..."
        exec gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf --workers=0 --proxy-mode
    elif [[ "$1" == "-"* ]]; then
        exec gosu odoo $ODOO_CMD "$@"
    else
        exec gosu odoo "$@"
    fi
else
    if [[ "$1" == "odoo" ]] || [[ "$1" == "" ]]; then
        echo "💡 Khởi động Odoo server với workers=0 và proxy_mode..."
        exec $ODOO_CMD -c /etc/odoo/odoo.conf --workers=0 --proxy-mode
    elif [[ "$1" == "-"* ]]; then
        exec $ODOO_CMD "$@"
    else
        exec "$@"
    fi
fi