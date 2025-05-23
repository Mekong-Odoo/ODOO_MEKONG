#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import psycopg2
import logging
from datetime import datetime

# Cấu hình logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("FilestoreChecker")


def check_filestore_consistency(db_host, db_port, db_user, db_password, db_name, filestore_path):
    """
    Kiểm tra tính nhất quán của filestore và database
    """
    logger.info(f"Kiểm tra filestore consistency cho database: {db_name}")

    # Kiểm tra thư mục filestore
    db_filestore_path = os.path.join(filestore_path, db_name)
    if not os.path.exists(db_filestore_path):
        logger.warning(f"Thư mục filestore không tồn tại: {db_filestore_path}")
        return False

    # Thống kê file trong filestore
    file_count = 0
    total_size = 0
    for root, dirs, files in os.walk(db_filestore_path):
        file_count += len(files)
        for file in files:
            file_path = os.path.join(root, file)
            try:
                total_size += os.path.getsize(file_path)
            except:
                pass

    logger.info(f"Filestore stats: {file_count} files, {total_size / 1024 / 1024:.2f} MB")

    # Kết nối database để kiểm tra
    try:
        conn = psycopg2.connect(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_password,
            dbname=db_name
        )
        cursor = conn.cursor()

        # Đếm attachment records
        cursor.execute("""
            SELECT 
                COUNT(*) as total_attachments,
                COUNT(store_fname) as file_attachments,
                COUNT(*) - COUNT(store_fname) as db_attachments
            FROM ir_attachment
        """)
        stats = cursor.fetchone()
        logger.info(f"Database stats: {stats[0]} total attachments, {stats[1]} file-based, {stats[2]} db-stored")

        # Kiểm tra file bị thiếu
        cursor.execute("""
            SELECT store_fname 
            FROM ir_attachment 
            WHERE store_fname IS NOT NULL
        """)
        missing_count = 0
        for (store_fname,) in cursor.fetchall():
            full_path = os.path.join(db_filestore_path, store_fname)
            if not os.path.exists(full_path):
                missing_count += 1
                if missing_count <= 5:  # Chỉ log 5 file đầu tiên
                    logger.warning(f"Missing file: {store_fname}")

        if missing_count > 5:
            logger.warning(f"... và {missing_count - 5} file khác bị thiếu")

        logger.info(f"Kết quả: {missing_count} file bị thiếu trong filestore")

        # Tạo file timestamp để track lần kiểm tra cuối
        timestamp_file = os.path.join(db_filestore_path, '.last_check')
        with open(timestamp_file, 'w') as f:
            f.write(datetime.now().isoformat())

        conn.close()
        return missing_count == 0

    except Exception as e:
        logger.error(f"Lỗi khi kiểm tra database: {e}")
        return False


def create_startup_check_script():
    """
    Tạo script để chạy mỗi khi container khởi động
    """
    startup_script = """#!/bin/bash
# Chạy kiểm tra filestore mỗi khi container khởi động
echo "=== Kiểm tra Filestore Consistency ===" 
python3 /opt/filestore_checker.py

# Tiếp tục khởi động Odoo bình thường
exec "$@"
"""
    return startup_script


if __name__ == "__main__":
    # Đọc tham số từ biến môi trường
    db_host = os.environ.get('DB_HOST', 'localhost')
    db_port = os.environ.get('DB_PORT', '5432')
    db_user = os.environ.get('DB_USER', 'odoo')
    db_password = os.environ.get('DB_PASSWORD', 'odoo')
    db_name = os.environ.get('DB_NAME', 'odoo')
    filestore_path = os.environ.get('FILESTORE_PATH', '/var/lib/odoo/filestore')

    is_consistent = check_filestore_consistency(db_host, db_port, db_user, db_password, db_name, filestore_path)

    if is_consistent:
        logger.info("✅ Filestore nhất quán với database")
        sys.exit(0)
    else:
        logger.warning("⚠️ Có vấn đề với filestore consistency")
        sys.exit(1)