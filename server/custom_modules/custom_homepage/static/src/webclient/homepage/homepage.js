/** @odoo-module **/

import { patch } from "@web/core/utils/patch";
import { HomeMenu } from "@web/webclient/home_menu/home_menu";

patch(HomeMenu.prototype, "custom_homepage", {
    setup() {
        super.setup();
        console.log('🏠 Trang chủ tuỳ chỉnh đã được tải!');
    },
});
