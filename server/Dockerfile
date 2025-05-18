FROM odoo:18.0

USER root

# Cài đặt các dependencies cần thiết
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    git \
    libldap2-dev \
    libsasl2-dev \
    libssl-dev \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    libjpeg-dev \
    zlib1g-dev \
    python3-dev \
    python3-wheel \
    python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cài thêm thư viện Python
RUN pip3 install --break-system-packages \
    geoip2 \
    num2words \
    python-ldap

# Tạo các thư mục cần thiết
RUN mkdir -p /mnt/custom_modules \
    && mkdir -p /usr/share/geoip \
    && mkdir -p /var/lib/odoo/sessions \
    && mkdir -p /var/log/odoo

# Thiết lập quyền truy cập cho user odoo
RUN chown -R odoo:odoo /mnt/custom_modules \
    && chown -R odoo:odoo /usr/share/geoip \
    && chown -R odoo:odoo /var/lib/odoo \
    && chown -R odoo:odoo /var/log/odoo

# Copy cấu hình template và entrypoint
COPY --chown=odoo:odoo odoo.conf.template /etc/odoo/odoo.conf.template
COPY --chown=odoo:odoo entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Quay về user odoo
USER odoo

# Cổng expose
EXPOSE 8069 8072

# Dùng entrypoint thay cho mặc định
ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
