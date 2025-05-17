# custom_homepage/controllers/main.py
from odoo import http
from odoo.http import request

class CustomHomePageController(http.Controller):
    @http.route('/home', auth='user', website=True)
    def homepage(self, **kw):
        return request.render("custom_homepage.homepage_template", {})
