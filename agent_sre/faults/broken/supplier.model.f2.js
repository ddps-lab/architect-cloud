/**
 * F2 (incident.io) BROKEN variant — connection pool exhaustion.
 *
 * Mechanism reproduced from the incident.io post-mortem:
 *   - tiny pool (connectionLimit: 5)
 *   - every read is wrapped in an UNNECESSARY explicit transaction
 *   - every request re-runs `SHOW TABLES` while holding the connection
 * Individually fast, but under concurrency connections are held long enough
 * that requests queue waiting for a free connection -> Task timed out.
 *
 * Recovery = restore the clean model (no transaction, table-check cached once,
 * larger pool) by redeploying the original lambda_code source.
 *
 * Exported API is identical to the clean model so routes keep working.
 */
const mysql = require("mysql2");
const dbConfig = require("../config/config");

// FAULT: tiny pool
const db_connection = mysql.createPool({
	host: dbConfig.APP_DB_HOST,
	user: dbConfig.APP_DB_USER,
	password: dbConfig.APP_DB_PASSWORD,
	database: dbConfig.APP_DB_NAME,
	connectionLimit: 5,
});

const Supplier = function (supplier) {
	this.id = supplier.id;
	this.name = supplier.name;
	this.address = supplier.address;
	this.city = supplier.city;
	this.state = supplier.state;
	this.email = supplier.email;
	this.phone = supplier.phone;
};

// FAULT: grab a dedicated connection, open an unnecessary transaction, run
// SHOW TABLES every time, then the real query, then commit/release. Holds the
// connection far longer than needed.
function withUselessTxn(runQuery, result) {
	db_connection.getConnection((err, c) => {
		if (err) return result(err, null);
		c.beginTransaction((txErr) => {
			if (txErr) {
				c.release();
				return result(txErr, null);
			}
			c.query("SHOW TABLES LIKE 'suppliers'", (showErr) => {
				if (showErr) {
					c.rollback(() => c.release());
					return result(showErr, null);
				}
				runQuery(c, (qErr, res) => {
					c.commit(() => {
						c.release();
						result(qErr, res);
					});
				});
			});
		});
	});
}

Supplier.create = (newSupplier, result) => {
	withUselessTxn(
		(c, cb) => c.query("INSERT INTO suppliers SET ?", newSupplier, (e, r) => cb(e, r && { id: r.insertId, ...newSupplier })),
		result
	);
};

Supplier.getAll = (result) => {
	withUselessTxn((c, cb) => c.query("SELECT * FROM suppliers", cb), result);
};

Supplier.findById = (supplierId, result) => {
	withUselessTxn(
		(c, cb) =>
			c.query(`SELECT * FROM suppliers WHERE id = ${supplierId}`, (e, r) => {
				if (e) return cb(e, null);
				if (r && r.length) return cb(null, r[0]);
				cb({ kind: "not_found" }, null);
			}),
		result
	);
};

Supplier.updateById = (id, supplier, result) => {
	withUselessTxn(
		(c, cb) =>
			c.query(
				"UPDATE suppliers SET name = ?, city = ?, address = ?, email = ?, phone = ?, state = ? WHERE id = ?",
				[supplier.name, supplier.city, supplier.address, supplier.email, supplier.phone, supplier.state, id],
				(e, r) => {
					if (e) return cb(e, null);
					if (r.affectedRows === 0) return cb({ kind: "not_found" }, null);
					cb(null, { id, ...supplier });
				}
			),
		result
	);
};

Supplier.delete = (id, result) => {
	withUselessTxn(
		(c, cb) =>
			c.query("DELETE FROM suppliers WHERE id = ?", id, (e, r) => {
				if (e) return cb(e, null);
				if (r.affectedRows === 0) return cb({ kind: "not_found" }, null);
				cb(null, r);
			}),
		result
	);
};

Supplier.removeAll = (result) => {
	withUselessTxn((c, cb) => c.query("DELETE FROM suppliers", cb), result);
};

module.exports = Supplier;
