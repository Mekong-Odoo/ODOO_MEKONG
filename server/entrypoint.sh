#!/bin/bash
set -e

# Thiết lập locale để tránh cảnh báo
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

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

# Tạo file cấu hình
setup_config() {
    echo "🔧 Tạo file cấu hình..."
    envsubst < /etc/odoo/odoo.conf.template > /etc/odoo/odoo.conf
    chmod 644 /etc/odoo/odoo.conf

    if [ "$(id -u)" = "0" ]; then
        chown odoo:odoo /etc/odoo/odoo.conf
    fi
    echo "✅ File cấu hình đã được tạo"
}

# Kiểm tra kết nối PostgreSQL với timeout ngắn hơn
check_postgres() {
    echo "🔍 Kiểm tra kết nối PostgreSQL..."
    local max_retries=5
    local counter=0
    local wait_time=3

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

# Khởi tạo database chỉ khi cần thiết
initialize_database() {
    echo "⚙️ Khởi tạo database ${DB_NAME}..."

    # Tạo database nếu chưa tồn tại
    if ! PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
        "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
        echo "📦 Tạo database ${DB_NAME}..."
        PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
            "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";"
    fi

    # Khởi tạo với module cơ bản
    echo "📦 Cài đặt module cơ bản (base, web)..."
    local core_modules="base,web"

    if [ "$(id -u)" = "0" ]; then
        gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${core_modules} --stop-after-init --log-level=warn
    else
        $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${core_modules} --stop-after-init --log-level=warn
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

# Luôn thiết lập thư mục và cấu hình
setup_directories
setup_config

# Kiểm tra PostgreSQL
if ! check_postgres; then
    echo "⚠️ Không thể kết nối PostgreSQL, nhưng sẽ tiếp tục khởi động..."
else
    # Kiểm tra trạng thái database
    db_status=$(check_database_status)
    db_exists=$(echo $db_status | cut -d',' -f1)
    db_initialized=$(echo $db_status | cut -d',' -f2)

    # Chỉ khởi tạo database khi thực sự cần thiết
    if [ "$db_exists" = "false" ] || [ "$db_initialized" = "false" ]; then
        if [ ! -f "$DB_READY_MARKER" ]; then
            echo "🆕 Database chưa sẵn sàng, thực hiện khởi tạo..."
            initialize_database
        else
            echo "✅ Database marker tồn tại, bỏ qua khởi tạo"
        fi
    else
        echo "✅ Database đã sẵn sàng, bỏ qua khởi tạo"
    fi
fi

# Kiểm tra filestore nhanh
quick_filestore_check

# Tạo marker tổng thể
touch "$INIT_MARKER"

echo "🚀 Khởi động Odoo..."

# Chạy Odoo với log level phù hợp
if [ "$(id -u)" = "0" ]; then
    if [[ "$1" == "odoo" ]] || [[ "$1" == "" ]]; then
        echo "💡 Khởi động Odoo server..."
        exec gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf
    elif [[ "$1" == "-"* ]]; then
        exec gosu odoo $ODOO_CMD "$@"
    else
        exec gosu odoo "$@"
    fi
else
    if [[ "$1" == "odoo" ]] || [[ "$1" == "" ]]; then
        echo "💡 Khởi động Odoo server..."
        exec $ODOO_CMD -c /etc/odoo/odoo.conf
    elif [[ "$1" == "-"* ]]; then
        exec $ODOO_CMD "$@"
    else
        exec "$@"
    fi
fi