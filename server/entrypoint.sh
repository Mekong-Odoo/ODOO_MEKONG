#!/bin/bash
set -e

# Thiết lập locale để tránh cảnh báo
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "🔍 Đang kiểm tra cài đặt Odoo..."

# Tìm đúng đường dẫn tới binary Odoo
if [ -f "/usr/bin/odoo" ]; then
    echo "✅ Tìm thấy binary Odoo tại: /usr/bin/odoo"
    ODOO_CMD="/usr/bin/odoo"
elif [ -f "/usr/local/bin/odoo" ]; then
    echo "✅ Tìm thấy binary Odoo tại: /usr/local/bin/odoo"
    ODOO_CMD="/usr/local/bin/odoo"
elif [ -f "/opt/odoo/odoo-bin" ]; then
    echo "✅ Tìm thấy binary Odoo tại: /opt/odoo/odoo-bin"
    ODOO_CMD="/opt/odoo/odoo-bin"
elif command -v odoo > /dev/null 2>&1; then
    echo "✅ Tìm thấy lệnh 'odoo'"
    ODOO_CMD="odoo"
elif command -v odoo-bin > /dev/null 2>&1; then
    echo "✅ Tìm thấy lệnh 'odoo-bin'"
    ODOO_CMD="odoo-bin"
else
    echo "❌ Không tìm thấy lệnh 'odoo' hoặc 'odoo-bin'"
    echo "📋 Liệt kê thư mục /usr/bin:"
    ls -la /usr/bin | grep -i odoo || echo "Không có file Odoo tại /usr/bin"
    echo "📋 Liệt kê thư mục /usr/local/bin:"
    ls -la /usr/local/bin | grep -i odoo || echo "Không có file Odoo tại /usr/local/bin"

    echo "🔎 Tìm toàn hệ thống (có thể mất thời gian)..."
    ODOO_BIN_PATH=$(find / -name "odoo" -type f -executable 2>/dev/null | head -n 1)
    [ -z "$ODOO_BIN_PATH" ] && ODOO_BIN_PATH=$(find / -name "odoo-bin" -type f -executable 2>/dev/null | head -n 1)

    if [ -n "$ODOO_BIN_PATH" ]; then
        echo "✅ Tìm thấy binary Odoo tại: $ODOO_BIN_PATH"
        ODOO_CMD="$ODOO_BIN_PATH"
    else
        echo "❌ Không tìm thấy binary Odoo!"
        exit 1
    fi
fi

echo "🔧 Sử dụng binary Odoo: $ODOO_CMD"

# Danh sách các module cần thiết
CORE_MODULES="base,mail,web,base_setup,bus,discuss"

# Tạo thư mục nếu là root
if [ "$(id -u)" = "0" ]; then
    echo "🔧 Đang chạy dưới quyền root, tạo thư mục..."
    mkdir -p /var/run/odoo /var/log/odoo /var/lib/odoo
    mkdir -p /var/lib/odoo/filestore/${DB_NAME}
    chown -R odoo:odoo /var/run/odoo /var/log/odoo /var/lib/odoo
    chmod -R 775 /var/lib/odoo
else
    echo "⚠️ Không có quyền root, bỏ qua tạo thư mục..."
fi

# Tạo file cấu hình từ template
echo "🔧 Tạo file cấu hình..."
envsubst < /etc/odoo/odoo.conf.template > /etc/odoo/odoo.conf
chmod 644 /etc/odoo/odoo.conf
chown odoo:odoo /etc/odoo/odoo.conf
echo "✅ File cấu hình:"
cat /etc/odoo/odoo.conf

# Kiểm tra kết nối PostgreSQL
echo "🔍 Kiểm tra kết nối tới PostgreSQL..."
max_retries=3
counter=0
while ! PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c "SELECT 1" > /dev/null 2>&1; do
    counter=$((counter+1))
    if [ $counter -ge $max_retries ]; then
        echo "❌ Không thể kết nối PostgreSQL sau $max_retries lần thử."
        break
    fi
    echo "⏳ Đợi PostgreSQL... ($counter/$max_retries)"
    sleep 5
done

if [ $counter -lt $max_retries ]; then
    echo "✅ Kết nối PostgreSQL thành công."

    if PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
        "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then

        echo "✅ Database ${DB_NAME} đã tồn tại."
        echo "🔍 Kiểm tra bảng ir_module_module..."

        if PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} \
            -c "SELECT 1 FROM pg_tables WHERE tablename = 'ir_module_module';" | grep -q 1; then
            echo "✅ Bảng ir_module_module tồn tại."

            # Kiểm tra module mail đã được cài đặt chưa
            echo "🔍 Kiểm tra cài đặt module mail..."
            MAIL_INSTALLED=$(PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -t \
                -c "SELECT state FROM ir_module_module WHERE name='mail';")

            if [ "$MAIL_INSTALLED" == "installed" ]; then
                echo "✅ Module mail đã được cài đặt."
            else
                echo "⚠️ Module mail chưa được cài đặt hoặc không hoạt động."
                echo "⚙️ Cài đặt các module core..."

                if [ "$(id -u)" = "0" ]; then
                    gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${CORE_MODULES} --stop-after-init
                else
                    $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${CORE_MODULES} --stop-after-init
                fi
            fi
        else
            echo "⚠️ Database chưa có bảng ir_module_module."
            echo "⚙️ Chạy lệnh khởi tạo với các module core..."

            if [ "$(id -u)" = "0" ]; then
                gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${CORE_MODULES} --stop-after-init
            else
                $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${CORE_MODULES} --stop-after-init
            fi
        fi
    else
        echo "⚠️ Database ${DB_NAME} chưa tồn tại. Đang tạo..."
        PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c \
            "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";"
        echo "✅ Đã tạo database ${DB_NAME}."
        echo "⚙️ Khởi tạo database với các module core..."

        if [ "$(id -u)" = "0" ]; then
            gosu odoo $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${CORE_MODULES} --stop-after-init
        else
            $ODOO_CMD -c /etc/odoo/odoo.conf -d ${DB_NAME} -i ${CORE_MODULES} --stop-after-init
        fi
    fi
fi

# Kiểm tra và sửa quyền thư mục filestore
echo "🔍 Kiểm tra quyền thư mục filestore..."
if [ -d "/var/lib/odoo/filestore/${DB_NAME}" ]; then
    echo "✅ Thư mục filestore cho ${DB_NAME} đã tồn tại."
    echo "🔧 Cập nhật quyền thư mục..."
    chown -R odoo:odoo /var/lib/odoo/filestore/${DB_NAME}
    chmod -R 775 /var/lib/odoo/filestore/${DB_NAME}
else
    echo "⚠️ Thư mục filestore cho ${DB_NAME} chưa tồn tại. Đang tạo..."
    mkdir -p /var/lib/odoo/filestore/${DB_NAME}
    chown -R odoo:odoo /var/lib/odoo/filestore/${DB_NAME}
    chmod -R 775 /var/lib/odoo/filestore/${DB_NAME}
fi

# Chạy Odoo hoặc lệnh được truyền vào container
echo "🚀 Khởi động Odoo hoặc lệnh được truyền vào..."
if [ "$(id -u)" = "0" ]; then
    echo "🔄 Đang chạy dưới quyền root..."

    if [[ "$1" == "-"* ]]; then
        echo "💡 Thực thi lệnh: gosu odoo $ODOO_CMD $*"
        exec gosu odoo $ODOO_CMD "$@"
    else
        echo "💡 Thực thi lệnh: gosu odoo $*"
        exec gosu odoo "$@"
    fi
else
    if [[ "$1" == "-"* ]]; then
        echo "💡 Thực thi lệnh: $ODOO_CMD $*"
        exec $ODOO_CMD "$@"
    else
        echo "💡 Thực thi lệnh: $*"
        exec "$@"
    fi
fi
