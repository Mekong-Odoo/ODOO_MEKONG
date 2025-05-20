FROM odoo:18.0

USER root

# Cài đặt các dependencies cần thiết và locale
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
    gettext \
    postgresql-client \
    curl \
    gosu \
    locales \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

# Thiết lập locale
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Cài thêm thư viện Python
RUN pip3 install --no-cache-dir --break-system-packages \
    geoip2 \
    num2words \
    python-ldap \
    psycopg2-binary

# Tạo các thư mục cần thiết
RUN mkdir -p /mnt/custom_modules \
    && mkdir -p /usr/share/geoip \
    && mkdir -p /var/lib/odoo/sessions \
    && mkdir -p /var/log/odoo \
    && mkdir -p /var/run/odoo

# Thiết lập quyền truy cập cho user odoo
RUN chown -R odoo:odoo /mnt/custom_modules \
    && chown -R odoo:odoo /usr/share/geoip \
    && chown -R odoo:odoo /var/lib/odoo \
    && chown -R odoo:odoo /var/log/odoo \
    && chown -R odoo:odoo /var/run/odoo

# Copy cấu hình template và entrypoint
COPY odoo.conf.template /etc/odoo/odoo.conf.template
COPY entrypoint.sh /entrypoint.sh

# Gán quyền thực thi
RUN chmod +x /entrypoint.sh

# Cổng expose
EXPOSE 8069 8072

# Dùng entrypoint thay cho mặc định
ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]