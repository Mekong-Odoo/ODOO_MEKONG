#!/bin/bash

echo "🔄 Dừng các container Odoo hiện tại..."
docker-compose down

echo "🗑️ Xóa container và image cũ..."
docker rm -f odoo_app 2>/dev/null || true
docker rmi -f $(docker images | grep odoo | awk '{print $3}') 2>/dev/null || true

echo "🔄 Xây dựng lại container Odoo..."
docker-compose build --no-cache

echo "🚀 Khởi động container với cổng mới (8080)..."
docker-compose up -d

echo "⏳ Đợi 10 giây để container khởi động..."
sleep 10

echo "📋 Logs của container:"
docker logs odoo_app

echo -e "\n✅ Hoàn thành! Truy cập Odoo tại: http://localhost:8080"
echo "👉 Để xem logs liên tục: docker logs -f odoo_app"
echo "👉 Nếu gặp vấn đề, thử vào container để kiểm tra: docker exec -it odoo_app bash"