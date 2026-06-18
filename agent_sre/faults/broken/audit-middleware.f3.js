// ---- F3 (Tarsnap) FAULT: unbounded local-disk logging -> ENOSPC ----
// Injected near the top of the express app in index.js. Every request appends
// to /tmp/audit.log with NO rotation. Lambda /tmp defaults to 512MB; under
// load the filesystem fills and further writes fail with:
//   ENOSPC: no space left on device
// Recovery = remove this middleware (log to stdout/CloudWatch) and clear /tmp,
// matching Tarsnap's "recovered by deleting logs".
const fs = require("fs");
handler.use((req, _res, next) => {
	try {
		fs.appendFileSync("/tmp/audit.log", JSON.stringify({ t: Date.now(), h: req.headers, u: req.url }) + "\n");
	} catch (e) {
		console.error("audit log write failed:", e.code || e.message);
		throw e; // surface ENOSPC as a request failure (fault behaviour)
	}
	next();
});
// ---- end F3 fault ----
