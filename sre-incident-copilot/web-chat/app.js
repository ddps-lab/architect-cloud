// SRE Incident Copilot — chat SPA with streaming + tool trace.
// Talks to POST {endpoint}/chat and reads a text/event-stream (SSE) response:
//   {type:"module",module}  {type:"tool",name,input}  {type:"text",delta}
//   {type:"done"}           {type:"error",message}
// session_id persists so multi-turn incidents map to the agent timeline (M3).

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
function scroll() {
	$("chat").scrollTop = $("chat").scrollHeight;
}

function addUser(text) {
	const d = document.createElement("div");
	d.className = "msg user";
	d.textContent = text;
	$("chat").appendChild(d);
	scroll();
}
function addError(text) {
	const d = document.createElement("div");
	d.className = "msg error";
	d.textContent = text;
	$("chat").appendChild(d);
	scroll();
}

// An agent turn: optional module badge + a trace list + a streaming text body.
function newAgentTurn() {
	const wrap = document.createElement("div");
	wrap.className = "msg agent";
	const badge = document.createElement("span");
	badge.className = "badge hidden";
	const trace = document.createElement("div");
	trace.className = "trace";
	const body = document.createElement("div");
	body.className = "body";
	wrap.append(badge, trace, body);
	$("chat").appendChild(wrap);
	body.textContent = "조사 중…";
	body.classList.add("thinking");
	scroll();
	const clearThinking = () => {
		if (body.classList.contains("thinking")) {
			body.classList.remove("thinking");
			body.textContent = "";
		}
	};
	return {
		setModule: (m) => {
			badge.textContent = "MODULE " + m;
			badge.classList.remove("hidden");
		},
		addTool: (name, input) => {
			clearThinking();
			const t = document.createElement("div");
			t.className = "tool";
			let arg = "";
			try {
				arg = input && Object.keys(input).length ? JSON.stringify(input) : "";
			} catch (e) { arg = ""; }
			t.textContent = "🔧 " + name + (arg ? " " + arg : "");
			trace.appendChild(t);
			scroll();
		},
		appendText: (delta) => {
			clearThinking();
			body.textContent += delta;
			scroll();
		},
	};
}

async function send(message) {
	const endpoint = getEndpoint();
	if (!endpoint) {
		addError("먼저 ⚙︎ 설정에서 에이전트 API 주소를 저장하세요.");
		$("settings").classList.remove("hidden");
		return;
	}
	addUser(message);
	const turn = newAgentTurn();

	try {
		const res = await fetch(endpoint + "/chat", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ message, session_id: getSession() }),
		});
		if (!res.ok || !res.body) {
			const txt = await res.text().catch(() => "");
			addError("오류 " + res.status + ": " + txt);
			return;
		}
		const reader = res.body.getReader();
		const decoder = new TextDecoder();
		let buf = "";
		while (true) {
			const { value, done } = await reader.read();
			if (done) break;
			buf += decoder.decode(value, { stream: true });
			// SSE frames are separated by a blank line
			let idx;
			while ((idx = buf.indexOf("\n\n")) >= 0) {
				const frame = buf.slice(0, idx);
				buf = buf.slice(idx + 2);
				const line = frame.split("\n").find((l) => l.startsWith("data:"));
				if (!line) continue;
				let ev;
				try { ev = JSON.parse(line.slice(5).trim()); } catch (e) { continue; }
				if (ev.type === "module") turn.setModule(ev.module);
				else if (ev.type === "tool") turn.addTool(ev.name, ev.input);
				else if (ev.type === "text") turn.appendText(ev.delta);
				else if (ev.type === "error") addError("에이전트 오류: " + ev.message);
			}
		}
	} catch (e) {
		addError("네트워크 오류: " + e.message + "\n(CORS 또는 엔드포인트 주소를 확인하세요)");
	}
}

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
	};
	$("composer").onsubmit = (e) => {
		e.preventDefault();
		const msg = $("message").value.trim();
		if (!msg) return;
		$("message").value = "";
		send(msg);
	};
});
