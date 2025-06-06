const Supplier = require("../models/supplier.model.js");
const {body, validationResult} = require("express-validator");

 exports.findAll = (req, res) => {
     Supplier.getAll((err, data) => {
         if (err)
             res.render("500", {message: "The was a problem retrieving the list of suppliers"});
         else res.render("supplier-list-all", {suppliers: data});
     });
 };

 exports.findOne = (req, res) => {
     Supplier.findById(req.params.id, (err, data) => {
         if (err) {
             if (err.kind === "not_found") {
                 res.status(404).send({
                     message: `Not found Supplier with id ${req.params.id}.`
                 });
             } else {
                 res.render("500", {message: `Error retrieving Supplier with id ${req.params.id}`});
             }
         } else res.render("supplier-update", {supplier: data});
     });
 };