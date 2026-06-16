// SRE Incident Copilot — chat SPA with streaming + tool trace.
// Talks to POST {endpoint}/chat and reads a text/event-stream (SSE) response:
//   {type:"module",module}  {type:"tool",name,input}  {type:"text",delta}
//   {type:"done"}           {type:"error",message}
// session_id persists so multi-turn incidents map to the agent timeline (M3).

const LS_ENDPOINT = "copilot.endpoint";
const LS_SESSION = "copilot.session";
const $ = (id) => document.getElementById(id);

// --- minimal, safe Markdown -> HTML (covers what the agent emits) ---
function escapeHtml(s) {
	return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function mdInline(s) {
	// inline code first (protect its contents)
	const codes = [];
	s = s.replace(/`([^`]+)`/g, (_, c) => {
		codes.push(c);
		return "\u0000" + (codes.length - 1) + "\u0000";
	});
	s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
	s = s.replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
	s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
	s = s.replace(/\u0000(\d+)\u0000/g, (_, i) => "<code>" + codes[+i] + "</code>");
	return s;
}
function renderMarkdown(md) {
	const lines = escapeHtml(md).split("\n");
	let html = "";
	let i = 0;
	let inCode = false, codeBuf = [];
	let listType = null, listBuf = [];
	const flushList = () => {
		if (listType) {
			html += "<" + listType + ">" + listBuf.map((x) => "<li>" + mdInline(x) + "</li>").join("") + "</" + listType + ">";
			listType = null; listBuf = [];
		}
	};
	while (i < lines.length) {
		const line = lines[i];
		// fenced code
		const fence = line.match(/^```(.*)$/);
		if (fence) {
			if (!inCode) { flushList(); inCode = true; codeBuf = []; }
			else { html += "<pre><code>" + codeBuf.join("\n") + "</code></pre>"; inCode = false; }
			i++; continue;
		}
		if (inCode) { codeBuf.push(line); i++; continue; }
		// table: header row + separator row
		if (/\|/.test(line) && i + 1 < lines.length && /^\s*\|?[\s:|-]+\|?\s*$/.test(lines[i + 1]) && /-/.test(lines[i + 1])) {
			flushList();
			const splitRow = (r) => r.replace(/^\s*\|/, "").replace(/\|\s*$/, "").split("|").map((c) => c.trim());
			const head = splitRow(line);
			i += 2;
			let rows = "";
			while (i < lines.length && /\|/.test(lines[i]) && lines[i].trim() !== "") {
				const cells = splitRow(lines[i]);
				rows += "<tr>" + cells.map((c) => "<td>" + mdInline(c) + "</td>").join("") + "</tr>";
				i++;
			}
			html += "<table><thead><tr>" + head.map((c) => "<th>" + mdInline(c) + "</th>").join("") +
				"</tr></thead><tbody>" + rows + "</tbody></table>";
			continue;
		}
		// heading
		const h = line.match(/^(#{1,6})\s+(.*)$/);
		if (h) { flushList(); html += "<h" + h[1].length + ">" + mdInline(h[2]) + "</h" + h[1].length + ">"; i++; continue; }
		// hr
		if (/^\s*([-*_])\1{2,}\s*$/.test(line)) { flushList(); html += "<hr>"; i++; continue; }
		// blockquote
		if (/^\s*>\s?/.test(line)) { flushList(); html += "<blockquote>" + mdInline(line.replace(/^\s*>\s?/, "")) + "</blockquote>"; i++; continue; }
		// list items
		const ul = line.match(/^\s*[-*]\s+(.*)$/);
		const ol = line.match(/^\s*\d+\.\s+(.*)$/);
		if (ul) { if (listType !== "ul") flushList(); listType = "ul"; listBuf.push(ul[1]); i++; continue; }
		if (ol) { if (listType !== "ol") flushList(); listType = "ol"; listBuf.push(ol[1]); i++; continue; }
		// blank line
		if (line.trim() === "") { flushList(); i++; continue; }
		// paragraph (merge consecutive non-empty, non-special lines)
		flushList();
		let para = [line];
		i++;
		while (i < lines.length && lines[i].trim() !== "" && !/^(#{1,6}\s|```|\s*[-*]\s|\s*\d+\.\s|\s*>)/.test(lines[i]) && !/\|/.test(lines[i])) {
			para.push(lines[i]); i++;
		}
		html += "<p>" + para.map(mdInline).join("<br>") + "</p>";
	}
	flushList();
	if (inCode) html += "<pre><code>" + codeBuf.join("\n") + "</code></pre>";
	return html;
}

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
	let raw = "";
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
			raw += delta;
			body.innerHTML = renderMarkdown(raw);
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
