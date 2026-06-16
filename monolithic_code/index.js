const express = require("express");
const fetch = require("node-fetch");
const bodyParser = require("body-parser");
const cors = require("cors");
const supplier = require("./app/controller/supplier.controller");
const app = express();
const mustacheExpress = require("mustache-express");
const favicon = require("serve-favicon");
const https = require("https");

// --- 캐시 데이터 저장을 위한 변수 ---
// 서버 정보를 저장할 객체를 선언합니다.
let serverInfoCache = {};

// parse requests of content-type: application/json
app.use(bodyParser.json());
// parse requests of content-type: application/x-www-form-urlencoded
app.use(bodyParser.urlencoded({ extended: true }));
app.use(cors());
app.options("*", cors());
app.engine("html", mustacheExpress());
app.set("view engine", "html");
app.set("views", __dirname + "/views");
app.use(express.static("public"));
app.use(favicon(__dirname + "/public/img/favicon.ico"));

// --- 데이터 가져오는 함수들 (기존과 동일) ---

// 메타데이터 토큰을 가져오는 함수
async function fetchToken() {
	// IMDSv2를 사용하기 위해 토큰을 먼저 요청합니다.
	const response = await fetch("http://169.254.169.254/latest/api/token", {
		method: "PUT",
		headers: {
			"X-aws-ec2-metadata-token-ttl-seconds": "21600",
		},
	});
	return response.text();
}

// 주어진 메타데이터 경로에서 데이터를 가져오는 함수
async function fetchMetadata(path, token) {
	try {
		const response = await fetch(`http://169.254.169.254/latest/meta-data/${path}`, {
			headers: {
				"X-aws-ec2-metadata-token": token,
			},
		});

		if (!response.ok) {
			// 메타데이터를 가져오지 못했을 경우, 'N/A'를 반환하여 에러를 방지합니다.
			console.warn(`Failed to fetch metadata for ${path}: ${response.statusText}. Returning 'N/A'.`);
			return "N/A";
		}

		return await response.text();
	} catch (error) {
		console.error(`Error fetching metadata for ${path}:`, error.message);
		return "N/A"; // 에러 발생 시에도 'N/A'를 반환합니다.
	}
}

// 외부 IP 및 지역 정보를 가져오는 함수
function fetchIpInfo() {
	return new Promise((resolve, reject) => {
		const options = {
			path: "/json/",
			host: "ipapi.co",
			port: 443,
			headers: { "User-Agent": "nodejs-ipapi-v1.02" },
		};

		https
			.get(options, (resp) => {
				let body = "";
				resp.on("data", (data) => {
					body += data;
				});

				resp.on("end", () => {
					try {
						const loc = JSON.parse(body);
						const result = {
							ip: loc.ip || "N/A",
							country: loc.country_name || "N/A",
							region: loc.region || "N/A",
							lat_long: (loc.latitude && loc.longitude) ? `${loc.latitude}, ${loc.longitude}`: "N/A",
							timezone: loc.timezone || "N/A",
						};
						resolve(result);
					} catch (error) {
						// JSON 파싱 에러 처리
						console.error("Error parsing IP info:", error);
						reject(error);
					}
				});
			})
			.on("error", (error) => {
				console.error("Error fetching IP info:", error);
				reject(error);
			});
	});
}

// --- 서버 시작 시 캐시 초기화 ---
// 서버가 시작될 때 한 번만 실행되어 메타데이터를 캐시에 저장합니다.
async function initializeCache() {
	console.log("Initializing metadata cache...");
	try {
		const token = await fetchToken();
		const ipInfo = await fetchIpInfo();

		// 각 메타데이터 항목에 대한 요청을 병렬로 처리합니다.
		const [instance_id, instance_type, avail_zone] = await Promise.all([
			fetchMetadata("instance-id", token),
			fetchMetadata("instance-type", token),
			fetchMetadata("placement/availability-zone", token),
		]);

		// 가져온 정보를 serverInfoCache 객체에 저장합니다.
		serverInfoCache = {
			public_ip: ipInfo.ip,
			instance_id: instance_id,
			instance_type: instance_type,
			avail_zone: avail_zone,
			geo_country_name: ipInfo.country,
			geo_region_name: ipInfo.region,
			geo_lat_long: ipInfo.lat_long,
			geo_timezone: ipInfo.timezone,
		};

		console.log("Metadata cache initialized successfully.");
		console.log(serverInfoCache);

	} catch (error) {
		// 초기화 중 에러가 발생하면 콘솔에 로그를 남깁니다.
		// 이 경우 앱은 빈 데이터로 시작하거나, 에러 처리를 추가할 수 있습니다.
		console.error("Fatal error during cache initialization:", error);
		// 필요한 경우, 프로세스를 종료할 수도 있습니다. process.exit(1);
	}
}


// --- 라우터 설정 ---

// list all the suppliers
app.get("/", (req, res) => {
	// 이제 네트워크 요청 대신 캐시된 객체에서 바로 데이터를 읽어옵니다.
	res.render("home", serverInfoCache);
});

app.get("/health", (req, res) => {
	res.render("health", {});
});
app.get("/suppliers/", supplier.findAll);
// show the add suppler form
app.get("/supplier-add", (req, res) => {
	res.render("supplier-add", {});
});
// receive the add supplier POST
app.post("/supplier-add", supplier.create);
// show the update form
app.get("/supplier-update/:id", supplier.findOne);
// receive the update POST
app.post("/supplier-update", supplier.update);
// receive the POST to delete a supplier
app.post("/supplier-remove/:id", supplier.remove);
// handle 404
app.use(function (req, res, next) {
	res.status(404).render("404", {});
});

// --- 서버 시작 ---
const app_port = process.env.APP_PORT || 80;

// 서버 리스닝을 시작하기 전에 캐시를 먼저 초기화합니다.
initializeCache().then(() => {
	app.listen(app_port, () => {
		console.log(`Server is running on port ${app_port}.`);
	});
});
