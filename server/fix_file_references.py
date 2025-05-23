#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import psycopg2
import logging
from pathlib import Path

# Cấu hình logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("FileStoreFixer")


def fix_file_references(db_host, db_port, db_user, db_password, db_name, filestore_path):
    """
    Sửa lỗi tham chiếu đến file không tồn tại trong filestore
    """
    logger.info(f"Đang kết nối tới database {db_name}...")

    # Kết nối đến database
    try:
        conn = psycopg2.connect(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_password,
            dbname=db_name
        )
        conn.autocommit = False
        cursor = conn.cursor()
        logger.info("Kết nối database thành công!")
    except Exception as e:
        logger.error(f"Không thể kết nối tới database: {e}")
        return False

    try:
        # Kiểm tra bảng ir_attachment có tồn tại không
        cursor.execute("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'ir_attachment')")
        if not cursor.fetchone()[0]:
            logger.warning("Bảng ir_attachment không tồn tại, có thể database chưa được khởi tạo đúng cách")
            conn.close()
            return False

        # Lấy tất cả các tham chiếu đến file trong filestore
        logger.info("Lấy danh sách tất cả các file attachments...")
        cursor.execute("""
            SELECT id, store_fname 
            FROM ir_attachment 
            WHERE store_fname IS NOT NULL
        """)
        attachments = cursor.fetchall()
        logger.info(f"Tìm thấy {len(attachments)} attachments có tham chiếu file")

        # Kiểm tra từng file và sửa lỗi
        fixed_count = 0
        for att_id, store_fname in attachments:
            full_path = os.path.join(filestore_path, db_name, store_fname)
            if not os.path.exists(full_path):
                logger.warning(f"File không tồn tại: {full_path} (ID: {att_id})")

                # Tạo thư mục nếu cần
                directory = os.path.dirname(full_path)
                if not os.path.exists(directory):
                    logger.info(f"Tạo thư mục: {directory}")
                    os.makedirs(directory, exist_ok=True)

                # Tùy chọn 1: Tạo file trống
                # open(full_path, 'wb').close()
                # logger.info(f"Đã tạo file trống: {full_path}")

                # Tùy chọn 2: Set store_fname về NULL (sẽ làm mất tham chiếu file)
                cursor.execute("""
                    UPDATE ir_attachment
                    SET store_fname = NULL, db_datas = NULL
                    WHERE id = %s
                """, (att_id,))
                logger.info(f"Đã reset attachment ID {att_id} (xóa tham chiếu đến file)")
                fixed_count += 1

        # Commit các thay đổi
        conn.commit()
        logger.info(f"Đã sửa {fixed_count} attachment records")

        # Kiểm tra cụ thể file bị lỗi
        check_file = '1d/1d2e3399968f850385bfc0f16fca94d05d78e482'
        cursor.execute("""
            SELECT id, name FROM ir_attachment 
            WHERE store_fname = %s
        """, (check_file,))
        results = cursor.fetchall()
        if results:
            logger.info(f"Tìm thấy {len(results)} attachment trỏ đến file lỗi {check_file}:")
            for att_id, att_name in results:
                logger.info(f"  - ID: {att_id}, Name: {att_name}")

        return True
    except Exception as e:
        logger.error(f"Lỗi khi sửa tham chiếu file: {e}")
        conn.rollback()
        return False
    finally:
        conn.close()


if __name__ == "__main__":
    # Đọc tham số từ biến môi trường
    db_host = os.environ.get('DB_HOST', 'localhost')
    db_port = os.environ.get('DB_PORT', '5432')
    db_user = os.environ.get('DB_USER', 'odoo')
    db_password = os.environ.get('DB_PASSWORD', 'odoo')
    db_name = os.environ.get('DB_NAME', 'odoo')
    filestore_path = os.environ.get('FILESTORE_PATH', '/var/lib/odoo/filestore')

    logger.info(f"Bắt đầu sửa lỗi file references cho database: {db_name}")
    success = fix_file_references(db_host, db_port, db_user, db_password, db_name, filestore_path)

    if success:
        logger.info("Quá trình sửa lỗi hoàn tất thành công")
        sys.exit(0)
    else:
        logger.error("Quá trình sửa lỗi không thành công")
        sys.exit(1)