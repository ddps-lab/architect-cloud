var express = require("express");
var payload = require("../utils/payload-util");
var router = express.Router();
var supplier = require("../app/controller/supplier.controller");
/* GET home page. */
router.get("/", function (req, res, next) {
	res.json(payload.success("home", {}));
});

router.get("/api/v1/supplier-list", supplier.findAll);
router.get("/api/v1/supplier-info", supplier.findOne);

module.exports = router;
