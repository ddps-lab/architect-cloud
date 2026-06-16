// SRE Incident Copilot — chat SPA.
// Saves the agent API endpoint in localStorage and talks to POST {endpoint}/chat
// with {message, session_id}. session_id persists so multi-turn incidents map to
// the agent's DynamoDB timeline (M3).

const LS_ENDPOINT = "copilot.endpoint";
const LS_SESSION = "copilot.session";

const $ = (id) => document.getElementById(id);

function getEndpoint() {
	return (localStorage.getItem(LS_ENDPOINT) || "").replace(/\/+$/, "");
}
function getSession() {
	let s = localStorage.getItem(LS_SESSION);
	if (!s) {
		s = "INC-" + Math.random().toString(36).slice(2, 8).toUpperCase();
		localStorage.setItem(LS_SESSION, s);
	}
	return s;
}
function setSessionLabel() {
	$("session-label").textContent = "세션: " + getSession();
}

function addMessage(text, cls) {
	const div = document.createElement("div");
	div.className = "msg " + cls;
	div.textContent = text;
	$("chat").appendChild(div);
	$("chat").scrollTop = $("chat").scrollHeight;
	return div;
}

async function send(message) {
	const endpoint = getEndpoint();
	if (!endpoint) {
		addMessage("먼저 ⚙︎ 설정에서 에이전트 API 주소를 저장하세요.", "error");
		$("settings").classList.remove("hidden");
		return;
	}
	addMessage(message, "user");
	const typing = addMessage("조사 중…", "agent typing");

	try {
		const res = await fetch(endpoint + "/chat", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ message, session_id: getSession() }),
		});
		const data = await res.json().catch(() => ({}));
		typing.remove();
		if (!res.ok) {
			addMessage("오류 " + res.status + ": " + (data.error || JSON.stringify(data)), "error");
			return;
		}
		addMessage(data.reply || "(빈 응답)", "agent");
	} catch (e) {
		typing.remove();
		addMessage("네트워크 오류: " + e.message + "\n(CORS 또는 엔드포인트 주소를 확인하세요)", "error");
	}
}

// --- wiring ---
window.addEventListener("DOMContentLoaded", () => {
	$("endpoint").value = getEndpoint();
	setSessionLabel();
	if (!getEndpoint()) $("settings").classList.remove("hidden");

	$("settings-toggle").onclick = () => $("settings").classList.toggle("hidden");

	$("save-endpoint").onclick = () => {
		const v = $("endpoint").value.trim().replace(/\/+$/, "");
		localStorage.setItem(LS_ENDPOINT, v);
		$("endpoint-status").textContent = v ? "저장됨: " + v : "주소가 비어 있습니다.";
	};

	$("new-session").onclick = () => {
		localStorage.removeItem(LS_SESSION);
		getSession();
		setSessionLabel();
		$("chat").innerHTML = "";
		addMessage("새 인시던트 세션을 시작했습니다.", "agent");
	};

	$("composer").onsubmit = (e) => {
		e.preventDefault();
		const msg = $("message").value.trim();
		if (!msg) return;
		$("message").value = "";
		send(msg);
	};
});
