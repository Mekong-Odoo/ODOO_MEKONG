#!/bin/bash

# Replace biến môi trường trong odoo.conf.template → odoo.conf thực tế
envsubst < /etc/odoo/odoo.conf.template > /etc/odoo/odoo.conf

# Gọi Odoo như bình thường
exec "$@"
