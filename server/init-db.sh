#!/bin/bash

echo "🔄 Khởi tạo hoặc reset cơ sở dữ liệu Odoo..."
echo "⚠️ CẢNH BÁO: Script này sẽ xóa và tạo lại cơ sở dữ liệu ${DB_NAME}!"
echo "⏳ Đang thực hiện... "

# Xóa database hiện tại nếu tồn tại
PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c "DROP DATABASE IF EXISTS \"${DB_NAME}\";"

# Tạo database mới
PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d postgres -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";"

# Khởi tạo database cho Odoo với module cơ bản
cd /usr/lib/python3/dist-packages/odoo
python3 odoo-bin -c /etc/odoo/odoo.conf -d ${DB_NAME} -i base --stop-after-init

echo "✅ Khởi tạo cơ sở dữ liệu thành công!"
echo "🔍 Bạn có thể truy cập Odoo tại: http://localhost:8069"