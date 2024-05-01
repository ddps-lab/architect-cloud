const express = require("express");
const fetch = require("node-fetch");
const bodyParser = require("body-parser");
const cors = require("cors");
const supplier = require("./app/controller/supplier.controller");
const app = express();
const mustacheExpress = require("mustache-express");
const favicon = require("serve-favicon");
const https = require("https");
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

// 메타데이터 토큰을 가져오는 함수
async function fetchToken() {
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
			throw new Error(`Failed to fetch metadata: ${response.statusText}`);
		}

		return await response.text();
	} catch (error) {
		console.error("Error fetching metadata:", error.message);
		throw error;
	}
}

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
							ip: loc.ip,
							country: loc.country_name,
							region: loc.region,
							lat_long: `${loc.latitude}, ${loc.longitude}`,
							timezone: loc.timezone,
						};
						resolve(result);
					} catch (error) {
						reject(error);
					}
				});
			})
			.on("error", (error) => {
				reject(error);
			});
	});
}

// list all the suppliers
app.get("/", async (req, res) => {
	try {
		const token = await fetchToken(); // 토큰 가져옴
		// 각 메타데이터 항목에 대한 요청을 비동기적으로 처리
		const [instance_id, instance_type, avail_zone] = await Promise.all([
			fetchMetadata("instance-id", token),
			fetchMetadata("instance-type", token),
			fetchMetadata("placement/availability-zone", token),
		]);

		const ipInfo = await fetchIpInfo();

		// 모든 메타데이터를 받은 후 응답을 렌더링
		res.render("home", {
			public_ip: ipInfo.ip,
			instance_id: instance_id,
			instance_type: instance_type,
			avail_zone: avail_zone,
			geo_country_name: ipInfo.country,
			geo_region_name: ipInfo.region,
			geo_lat_long: ipInfo.lat_long,
			geo_timezone: ipInfo.timezone,
		});
	} catch (error) {
		console.error("Error fetching EC2 metadata:", error);
		res.status(500).send("Internal Server Error");
	}
});

app.get("/health", (req, res) => {
	res.render("health", {});
});
app.get("/suppliers/", supplier.findAll);

// handle 404
app.use(function (req, res, next) {
	res.status(404).render("404", {});
});

// set port, listen for requests
const app_port = process.env.APP_PORT || 8080;
app.listen(app_port, () => {
	console.log(`Server is running on port ${app_port}.`);
});
