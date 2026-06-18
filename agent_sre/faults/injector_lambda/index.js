/**
 * Fault injector / SQL helper Lambda (runs INSIDE the VPC, so it can reach the
 * private RDS instance). Used by faults/inject.sh and faults/restore.sh, and
 * also reused by the agent's apply_recovery tool for DB-level actions.
 *
 * Invoke payload: { "action": "<name>", "sql": "<optional raw sql>" }
 *
 * Actions:
 *   seed_overflow        -> ALTER TABLE suppliers AUTO_INCREMENT = 2147483647   (F1 inject)
 *   restore_id_bigint    -> ALTER TABLE suppliers MODIFY id BIGINT NOT NULL AUTO_INCREMENT (F1 fix)
 *   alter_phone_int      -> ALTER TABLE suppliers MODIFY phone INT              (F4 inject)
 *   restore_phone_varchar-> ALTER TABLE suppliers MODIFY phone VARCHAR(255)     (F4 fix)
 *   ensure_table         -> create suppliers table if missing
 *   describe             -> SHOW CREATE TABLE suppliers + status
 *   run_sql              -> execute provided `sql` (admin escape hatch)
 */
const mysql = require("mysql2/promise");

const cfg = {
	host: process.env.APP_DB_HOST,
	user: process.env.APP_DB_USER || "nodeapp",
	password: process.env.APP_DB_PASSWORD || "lab-password",
	database: process.env.APP_DB_NAME || "COFFEE",
	multipleStatements: true,
};

const CREATE_TABLE = `CREATE TABLE IF NOT EXISTS suppliers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  address VARCHAR(255),
  city VARCHAR(255),
  state VARCHAR(255),
  email VARCHAR(255),
  phone VARCHAR(255)
);`;

const ACTIONS = {
	ensure_table: [CREATE_TABLE],
	seed_overflow: ["ALTER TABLE suppliers AUTO_INCREMENT = 2147483647;"],
	restore_id_bigint: ["ALTER TABLE suppliers MODIFY id BIGINT NOT NULL AUTO_INCREMENT;"],
	alter_phone_int: ["ALTER TABLE suppliers MODIFY phone INT;"],
	restore_phone_varchar: ["ALTER TABLE suppliers MODIFY phone VARCHAR(255);"],
	describe: ["SHOW CREATE TABLE suppliers;", "SELECT MAX(id) AS max_id, COUNT(*) AS rows_count FROM suppliers;"],
};

exports.handler = async (event) => {
	const action = (event && event.action) || "describe";
	let statements;
	if (action === "run_sql") {
		if (!event.sql) return resp(400, { error: "run_sql requires `sql`" });
		statements = [event.sql];
	} else {
		statements = ACTIONS[action];
		if (!statements) return resp(400, { error: `unknown action: ${action}`, known: Object.keys(ACTIONS) });
	}

	const conn = await mysql.createConnection(cfg);
	try {
		const results = [];
		for (const sql of statements) {
			const [rows] = await conn.query(sql);
			results.push({ sql, rows });
		}
		return resp(200, { action, results });
	} catch (err) {
		console.error("injector error:", err);
		return resp(500, { action, error: err.message, code: err.code });
	} finally {
		await conn.end();
	}
};

function resp(statusCode, body) {
	return { statusCode, body: JSON.stringify(body, null, 2) };
}
