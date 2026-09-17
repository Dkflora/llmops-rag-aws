// The page after signing in: the list of chats on the left, the conversation on the right.
import { useEffect, useMemo, useRef, useState } from "react";
import Markdown from "react-markdown";

import { makeApi } from "./api.js";

// Shown on an empty chat. Clicking one asks it, which saves typing in a demo.
const SUGGESTIONS = [
  "How many holiday days can I carry into next year?",
  "What is my salary?",
  "How many vacation days do I have left?",
  "What is the mileage reimbursement rate?",
];

// "Amara Diallo" becomes "AD", for the little circle beside their messages.
function initials(name) {
  return (name || "")
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0].toUpperCase())
    .join("");
}

// A question can take a while when Aurora is waking from zero, so count the
// seconds rather than leave somebody wondering whether it is stuck.
function Thinking() {
  const [seconds, setSeconds] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => setSeconds((n) => n + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="row assistant">
      <div className="mark small" aria-hidden="true">N</div>
      <div className="bubble">
        <div className="thinking" role="status">
          <span className="dots" aria-hidden="true">
            <i /><i /><i />
          </span>
          <span>Looking for the answer</span>
          {seconds >= 4 && <span className="elapsed">{seconds}s</span>}
        </div>
      </div>
    </div>
  );
}

function SendIcon() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="M2 21l21-9L2 3v7l15 2-15 2v7z" fill="currentColor" />
    </svg>
  );
}

export default function Chat({ signIn, onSignOut }) {
  // Rebuild the API helper only when the token or email changes (Cognito renews tokens every hour)
  const api = useMemo(() => makeApi(signIn), [signIn.token, signIn.email]);

  const [me, setMe] = useState(null); // the signed-in employee
  const [chats, setChats] = useState([]); // their saved conversations
  const [conversationId, setConversationId] = useState(null); // the open chat (null = new chat)
  const [messages, setMessages] = useState([]); // messages on screen
  const [question, setQuestion] = useState(""); // what's typed in the box
  const [waiting, setWaiting] = useState(false); // true while the assistant works
  const [error, setError] = useState("");
  const bottom = useRef(null);
  const box = useRef(null);

  // 1. When the page opens: who is signed in, and which chats do they have?
  useEffect(() => {
    api.me().then(setMe).catch((err) => setError(err.message));
    api.conversations().then(setChats).catch(() => {});
  }, [api]);

  // Keep the newest message in view
  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages, waiting]);

  // The box grows with the question instead of scrolling a one line input
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }, [question]);

  // 2. Open a saved chat, or start a new one
  async function openChat(id) {
    setError("");
    setConversationId(id);
    try {
      setMessages(await api.messages(id));
    } catch (err) {
      setError(err.message);
    }
  }

  function newChat() {
    setConversationId(null);
    setMessages([]);
    setError("");
    box.current?.focus();
  }

  // 3. Ask a question: show it straight away, then add the answer when it arrives
  async function send(text) {
    const asked = text.trim();
    if (!asked || waiting) return;

    setQuestion("");
    setError("");
    setMessages((current) => [...current, { role: "user", content: asked }]);
    setWaiting(true);

    try {
      const reply = await api.chat(asked, conversationId);
      setMessages((current) => [
        ...current,
        { role: "assistant", content: reply.answer, sources: reply.sources },
      ]);
      if (conversationId === null) {
        setConversationId(reply.conversation_id);
        setChats(await api.conversations());
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setWaiting(false);
    }
  }

  function onSubmit(event) {
    event.preventDefault();
    send(question);
  }

  // Enter sends, shift and enter starts a new line, which is what people expect
  function onKeyDown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      send(question);
    }
  }

  // Signed in with Cognito, but not an employee in our database
  if (error && !me) {
    return (
      <div className="login">
        <div className="mark" aria-hidden="true">N</div>
        <h1>Northwind HR Assistant</h1>
        <p>{error}</p>
        <button onClick={onSignOut}>Sign out</button>
      </div>
    );
  }

  if (!me) {
    return <p className="status-page">Loading…</p>;
  }

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="who">
          <div className="mark small user" aria-hidden="true">{initials(me.full_name)}</div>
          <div className="who-text">
            <strong>{me.full_name}</strong>
            <span>{me.job_title} · {me.department}</span>
          </div>
        </div>

        <button className="new-chat" onClick={newChat}>
          <span aria-hidden="true">+</span> New chat
        </button>

        <nav aria-label="Your chats">
          <p className="label">Your chats</p>
          {chats.length === 0 && <p className="muted" style={{ padding: "0 6px", fontSize: 14 }}>No chats yet.</p>}
          {chats.map((chat) => (
            <button
              key={chat.id}
              className={chat.id === conversationId ? "chat-link open" : "chat-link"}
              onClick={() => openChat(chat.id)}
            >
              {chat.title}
            </button>
          ))}
        </nav>

        <button className="sign-out" onClick={onSignOut}>Sign out</button>
      </aside>

      <main className="conversation">
        <header className="topbar">
          <div className="mark small" aria-hidden="true">N</div>
          <h1>Northwind HR Assistant</h1>
          <span className="dot" aria-hidden="true" />
          <span className="dot-label">Online</span>
        </header>

        <div className="scroller">
          <div className="messages">
            {messages.length === 0 && !waiting && (
              <div className="empty">
                <div className="mark" aria-hidden="true">N</div>
                <h2>Hello, {me.full_name.split(" ")[0]}</h2>
                <p>Ask about company policy, or about your own pay and time off.</p>
                <div className="suggestions">
                  {SUGGESTIONS.map((text) => (
                    <button key={text} className="suggestion" onClick={() => send(text)}>
                      {text}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {messages.map((message, index) => (
              <div key={index} className={`row ${message.role}`}>
                <div className={message.role === "user" ? "mark small user" : "mark small"} aria-hidden="true">
                  {message.role === "user" ? initials(me.full_name) : "N"}
                </div>
                <div className="bubble">
                  <Markdown>{message.content}</Markdown>
                  {message.sources?.length > 0 && (
                    <div className="sources">
                      {message.sources.map((source) => (
                        <span className="source-chip" key={source}>{source}</span>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            ))}

            {waiting && <Thinking />}
            <div ref={bottom} />
          </div>
        </div>

        <div className="ask-wrap">
          {error && <p className="error-banner">{error}</p>}
          <form className="ask" onSubmit={onSubmit}>
            <label htmlFor="question" className="visually-hidden">Your question</label>
            <textarea
              id="question"
              ref={box}
              rows={1}
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              onKeyDown={onKeyDown}
              placeholder="Ask about policy, pay or time off…"
              autoComplete="off"
            />
            <button className="send" type="submit" disabled={waiting || !question.trim()} aria-label="Send">
              <SendIcon />
            </button>
          </form>
          <p className="hint">Answers come from Northwind's HR policies and your own record. Enter sends, shift and enter for a new line.</p>
        </div>
      </main>
    </div>
  );
}
