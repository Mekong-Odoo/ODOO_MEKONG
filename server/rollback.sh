#!/bin/bash

# Script rollback thủ công cho Odoo với tối ưu dung lượng
# Sử dụng: ./rollback.sh [backup_folder_name]
# Ví dụ: ./rollback.sh 1128_1430_abc123f

set -e

echo "🔄 ODOO ROLLBACK SCRIPT (Optimized)"
echo "=================================="

# Kiểm tra thư mục backup
BACKUP_BASE_DIR="/home/ec2-user/odoo_backup"
if [ ! -d "$BACKUP_BASE_DIR" ]; then
    echo "❌ Không tìm thấy thư mục backup: $BACKUP_BASE_DIR"
    exit 1
fi

# Hàm hiển thị dung lượng backup
show_backup_info() {
    local backup_dir="$1"
    if [ -f "$backup_dir/size.txt" ]; then
        echo "   📏 $(cat $backup_dir/size.txt | awk '{print $1}')"
    else
        echo "   📏 $(du -sh $backup_dir 2>/dev/null | cut -f1)"
    fi

    if [ -f "$backup_dir/commit.txt" ]; then
        echo "   🔗 $(cat $backup_dir/commit.txt)"
    fi

    if [ -f "$backup_dir/date.txt" ]; then
        echo "   📅 $(cat $backup_dir/date.txt)"
    fi
}

# Nếu không chỉ định backup cụ thể, hiển thị danh sách
if [ -z "$1" ]; then
    echo "📁 Danh sách backup có sẵn:"
    echo "=========================="

    TOTAL_SIZE=0
    for backup in $(ls -t "$BACKUP_BASE_DIR" 2>/dev/null | grep -v "^\.$" | grep -v "^\.\.$" | head -10); do
        if [ -d "$BACKUP_BASE_DIR/$backup" ]; then
            echo "📂 $backup"
            show_backup_info "$BACKUP_BASE_DIR/$backup"
            echo ""
        fi
    done

    echo "📊 Tổng dung lượng tất cả backup: $(du -sh $BACKUP_BASE_DIR 2>/dev/null | cut -f1)"
    echo ""
    echo "💡 Tip: Chỉ hiển thị 10 backup gần nhất"
    echo "🧹 Để dọn dẹp backup cũ: $0 --cleanup"
    echo ""
    echo "Sử dụng: $0 <tên_backup>"
    echo "Ví dụ: $0 1128_1430_abc123f"
    exit 0
fi

# Tính năng cleanup backup cũ
if [ "$1" = "--cleanup" ]; then
    echo "🧹 CLEANUP BACKUP CŨ"
    echo "==================="

    cd "$BACKUP_BASE_DIR"

    # Hiển thị dung lượng hiện tại
    echo "📊 Dung lượng hiện tại: $(du -sh . | cut -f1)"

    # Đếm số backup
    BACKUP_COUNT=$(ls -1 | wc -l)
    echo "📁 Số backup hiện có: $BACKUP_COUNT"

    if [ $BACKUP_COUNT -gt 5 ]; then
        echo ""
        echo "🗑️ Sẽ xóa $(($BACKUP_COUNT - 5)) backup cũ nhất..."
        read -p "Bạn có chắc chắn? (y/N): " -r

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Giữ lại 3 backup gần nhất + 2 backup tuần
            RECENT_BACKUPS=$(ls -t | head -n 3)
            WEEKLY_BACKUPS=$(ls -t | awk 'NR > 3' | head -n 14 | awk 'NR % 7 == 1' | head -n 2)
            KEEP_BACKUPS=$(echo -e "$RECENT_BACKUPS\n$WEEKLY_BACKUPS" | sort -u)

            for backup in $(ls -t); do
                if ! echo "$KEEP_BACKUPS" | grep -q "^$backup$"; then
                    echo "🗑️ Xóa: $backup"
                    rm -rf "$backup"
                fi
            done

            echo "✅ Cleanup hoàn tất!"
            echo "📊 Dung lượng sau cleanup: $(du -sh . | cut -f1)"
        else
            echo "❌ Hủy cleanup"
        fi
    else
        echo "✅ Không cần cleanup (≤5 backup)"
    fi
    exit 0
fi

BACKUP_DIR="$BACKUP_BASE_DIR/$1"

# Kiểm tra backup có tồn tại không
if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Không tìm thấy backup: $BACKUP_DIR"
    echo "📁 Các backup có sẵn (5 gần nhất):"
    ls -lt "$BACKUP_BASE_DIR" | head -6 | grep "^d" | awk '{print $9}' | grep -v "^\.$" | grep -v "^\.\.$"
    exit 1
fi

echo "📂 Backup được chọn: $1"
echo "📍 Đường dẫn: $BACKUP_DIR"

# Hiển thị thông tin backup
show_backup_info "$BACKUP_DIR"

# Xác nhận từ người dùng
echo ""
read -p "⚠️  Bạn có chắc chắn muốn rollback về backup này? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Rollback đã bị hủy"
    exit 0
fi

echo ""
echo "🔄 Bắt đầu quá trình rollback..."

# Tạo backup nhỏ gọn của version hiện tại
CURRENT_BACKUP_DIR="$BACKUP_BASE_DIR/before_rollback_$(date +%m%d_%H%M)"
echo "💾 Tạo backup version hiện tại tại: $CURRENT_BACKUP_DIR"
mkdir -p "$CURRENT_BACKUP_DIR"

if [ -d "/home/ec2-user/odoo_deploy" ]; then
    cd "/home/ec2-user/odoo_deploy"
    # Backup nén để tiết kiệm dung lượng
    find . -type f \
      ! -path "*/node_modules/*" \
      ! -path "*/.git/*" \
      ! -path "*/logs/*" \
      ! -path "*/__pycache__/*" \
      ! -name "*.pyc" \
      ! -name "*.log" \
      -size -10M \
      | tar czf "$CURRENT_BACKUP_DIR/current_backup.tar.gz" -T -

    echo "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" > "$CURRENT_BACKUP_DIR/commit.txt"
    echo "$(date)" > "$CURRENT_BACKUP_DIR/date.txt"
fi

# Dừng Odoo trước khi rollback
echo "⏹️  Dừng Odoo..."
cd "/home/ec2-user/odoo_deploy"
docker-compose down 2>/dev/null || docker stop odoo_app 2>/dev/null || true

# Thực hiện rollback
echo "🔄 Phục hồi files từ backup..."
rm -rf "/home/ec2-user/odoo_deploy"/*

# Kiểm tra xem backup có nén không
if [ -f "$BACKUP_DIR/odoo_backup.tar.gz" ]; then
    echo "📦 Giải nén backup..."
    cd "/home/ec2-user/odoo_deploy"
    tar xzf "$BACKUP_DIR/odoo_backup.tar.gz"
else
    # Backup cũ không nén
    cp -r "$BACKUP_DIR"/* "/home/ec2-user/odoo_deploy/"
fi

# Phân quyền lại
echo "🔧 Thiết lập lại quyền..."
cd "/home/ec2-user/odoo_deploy"
chmod +x *.sh 2>/dev/null || true
find . -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Khởi động lại Odoo
echo "🚀 Khởi động lại Odoo..."
if [ -f "restart-odoo.sh" ]; then
    ./restart-odoo.sh
elif [ -f "docker-compose.yml" ]; then
    docker-compose up -d
else
    echo "⚠️  Không tìm thấy script khởi động. Vui lòng khởi động thủ công"
fi

# Kiểm tra trạng thái
echo "⏳ Kiểm tra trạng thái Odoo..."
sleep 10

for i in {1..12}; do
    if curl -k -sSf https://52.221.232.143:8069 > /dev/null 2>&1 || \
       curl -k -sSf https://mekong-odoo.ddns.net:8069 > /dev/null 2>&1; then
        echo "✅ Rollback thành công! Odoo đã hoạt động"
        break
    else
        echo "⏰ Đang kiểm tra... ($i/12)"
        sleep 10
    fi
done

if [ $i -eq 12 ]; then
    echo "⚠️  Odoo chưa phản hồi. Vui lòng kiểm tra log:"
    echo "   docker logs odoo_app"
    echo "   docker exec odoo_app tail -20 /var/log/odoo/odoo.log"
else
    echo ""
    echo "🎉 ROLLBACK HOÀN TẤT!"
    echo "========================"
    echo "✅ Đã rollback về backup: $1"
    if [ -f "$BACKUP_DIR/commit_hash.txt" ]; then
        echo "🔗 Commit: $(cat $BACKUP_DIR/commit_hash.txt)"
    fi
    echo "🌐 Kiểm tra tại:"
    echo "   - https://52.221.232.143:8069"
    echo "   - https://mekong-odoo.ddns.net:8069"
    echo ""
    echo "💾 Backup version trước đó đã lưu tại: $CURRENT_BACKUP_DIR"
fi