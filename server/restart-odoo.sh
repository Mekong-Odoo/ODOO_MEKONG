#!/bin/bash

echo "🚀 Bắt đầu triển khai lại Odoo..."
echo "🧹 Dừng và xóa container cũ..."
docker compose down

echo "🔨 Xây dựng lại container..."
docker compose build

echo "🟢 Khởi động lại container..."
docker compose up -d

echo -e "\n✅ Hoàn tất triển khai Odoo!"
echo "👉 Truy cập tại: http://52.221.232.143:8069"
echo "👉 Xem logs: docker compose logs -f"
echo "👉 Xem logs chi tiết: docker compose logs -f"
