// The page after signing in: the list of chats on the left, the conversation on the right.
import { useEffect, useMemo, useRef, useState } from "react";
import Markdown from "react-markdown";

import { makeApi } from "./api.js";

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

  // 1. When the page opens: who is signed in, and which chats do they have?
  useEffect(() => {
    api.me().then(setMe).catch((err) => setError(err.message));
    api.conversations().then(setChats).catch(() => {});
  }, [api]);

  // Keep the newest message in view
  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, waiting]);

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
  }

  // 3. Ask a question: show it straight away, then add the answer when it arrives
  async function ask(event) {
    event.preventDefault();
    const text = question.trim();
    if (!text || waiting) return;

    setQuestion("");
    setError("");
    setMessages((current) => [...current, { role: "user", content: text }]);
    setWaiting(true);

    try {
      const reply = await api.chat(text, conversationId);
      setMessages((current) => [...current, { role: "assistant", content: reply.answer, sources: reply.sources }]);
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

  // Signed in with Cognito, but not an employee in our database
  if (error && !me) {
    return (
      <div className="login">
        <h1>Northwind HR Assistant</h1>
        <p className="error">{error}</p>
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
          <strong>{me.full_name}</strong>
          <span>
            {me.job_title} · {me.department}
          </span>
        </div>

        <button className="new-chat" onClick={newChat}>
          + New chat
        </button>

        <nav aria-label="Your chats">
          <p className="label">Your chats</p>
          {chats.length === 0 && <p className="muted">No chats yet.</p>}
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

        <button className="sign-out" onClick={onSignOut}>
          Sign out
        </button>
      </aside>

      <main className="conversation">
        <h1>Northwind HR Assistant</h1>

        <div className="messages">
          {messages.length === 0 && !waiting && (
            <p className="muted">Ask about company policy, or about your own pay and time off.</p>
          )}

          {messages.map((message, index) => (
            <div key={index} className={`message ${message.role}`}>
              <Markdown>{message.content}</Markdown>
              {message.sources?.length > 0 && (
                <details>
                  <summary>Sources</summary>
                  <ul>
                    {message.sources.map((source) => (
                      <li key={source}>{source}</li>
                    ))}
                  </ul>
                </details>
              )}
            </div>
          ))}

          {waiting && (
            <div className="message assistant thinking" role="status">
              <span className="spinner" aria-hidden="true" /> Looking for the answer…
            </div>
          )}
          <div ref={bottom} />
        </div>

        {error && <p className="error">{error}</p>}

        <form className="ask" onSubmit={ask}>
          <label htmlFor="question" className="visually-hidden">
            Your question
          </label>
          <input
            id="question"
            value={question}
            onChange={(event) => setQuestion(event.target.value)}
            placeholder="How many vacation days do I have left?"
            autoComplete="off"
          />
          <button type="submit" disabled={waiting || !question.trim()}>
            Ask
          </button>
        </form>
      </main>
    </div>
  );
}
