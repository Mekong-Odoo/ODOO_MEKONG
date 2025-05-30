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

# Cài đặt thư viện Python cần thiết một cách an toàn không gỡ cài đặt gói hệ thống
RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed \
    geoip2 \
    num2words \
    python-ldap \
    psycopg2-binary \
    werkzeug \
    pydot \
    pyparsing \
    greenlet \
    gevent \
    xlrd \
    xlwt \
    passlib \
    pillow \
    polib \
    lxml \
    reportlab \
    qrcode \
    vobject \
    python-dateutil \
    Babel>=2.9.1 \
    chardet>=5.0.0 \
    decorator>=5.1.1 \
    docutils>=0.14 \
    gevent>=22.10.2 \
    greenlet>=2.0.0 \
    idna>=3.4 \
    Jinja2>=3.0.0 \
    lxml>=4.9.1 \
    MarkupSafe>=2.0.0 \
    ofxparse>=0.21 \
    Pillow>=9.3.0 \
    psutil>=5.9.4 \
    pydot>=1.4.2 \
    pyserial>=3.5 \
    python-stdnum>=1.17 \
    pytz>=2022.6 \
    qrcode>=7.3.1 \
    reportlab>=3.6.11 \
    requests>=2.28.1 \
    urllib3>=1.26.12 \
    vobject>=0.9.6.1 \
    Werkzeug>=2.0.0 \
    XlsxWriter>=3.0.3 \
    zeep>=4.2.1

# Tạo các thư mục cần thiết
RUN mkdir -p /mnt/custom_modules \
    && mkdir -p /usr/share/geoip \
    && mkdir -p /var/lib/odoo/sessions \
    && mkdir -p /var/lib/odoo/filestore \
    && mkdir -p /var/log/odoo \
    && mkdir -p /var/run/odoo

# Thiết lập quyền truy cập cho user odoo (root -> user odoo)
RUN chown -R odoo:odoo /mnt/custom_modules \
    && chown -R odoo:odoo /usr/share/geoip \
    && chown -R odoo:odoo /var/lib/odoo \
    && chown -R odoo:odoo /var/log/odoo \
    && chown -R odoo:odoo /var/run/odoo \
    && chmod -R 775 /var/lib/odoo

# Copy file sửa lỗi tham chiếu
COPY fix_file_references.py /usr/local/bin/
RUN chmod +x /usr/local/bin/fix_file_references.py

# Copy cấu hình template và entrypoint
COPY odoo.conf.template /etc/odoo/odoo.conf.template
COPY entrypoint.sh /entrypoint.sh

# Gán quyền thực thi
RUN chmod +x /entrypoint.sh

# Cổng expose (8069: Giao diện web chính của Odoo/ 8072: Cổng longpolling (thông báo thời gian thực, chat...))
EXPOSE 8069 8072

# Dùng entrypoint thay cho mặc định
ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]