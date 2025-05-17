# custom_homepage/__manifest__.py
{
    "name": "Custom Homepage",
    "summary": "Customizable homepage displayed upon opening Odoo",
    "version": "1.0",
    "category": "Tools",
    "author": "Mekong",
    "website": "https://mekongpetro.com/",
    "depends": ["web"],
    "data": [
        "views/homepage.xml",
    ],
    "controllers": [
        "controllers/main.py",
    ],
    "assets": {
        "web.assets_frontend": [
            "custom_homepage/static/src/webclient/homepage/homepage.js",
            "custom_homepage/static/src/webclient/homepage/homepage.scss",
        ],
    },
    "description": """
        This module allows you to create a custom homepage that will be displayed when opening Odoo.
        You can add icons that link to various Odoo modules or pages.
        It provides a simple and clean layout for a better user experience.
    """,
    "license": "AGPL-3",  # Cung cấp giấy phép nếu cần
    "support": "tien.tdm@mekongpetro.com",  # Thêm email hỗ trợ nếu có
    "installable": True,
    "application": True,
    "auto_install": False,
}
