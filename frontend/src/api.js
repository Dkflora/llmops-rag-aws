// Every call to the back end goes through here, so "who is signed in" is added in one place.
export function makeApi(signIn) {
  async function request(path, options = {}) {
    const headers = { "Content-Type": "application/json" };
    // The Cognito ID token is the only thing that says who is asking. The API
    // reads the email out of the verified token, never out of a header.
    if (signIn.token) headers.Authorization = `Bearer ${signIn.token}`;

    const response = await fetch(`/api${path}`, { ...options, headers });
    const body = await response.json().catch(() => ({}));

    // The API explains every error in "detail". Show that to the person.
    if (!response.ok) {
      throw new Error(body.detail || `Something went wrong (error ${response.status}).`);
    }
    return body;
  }

  return {
    me: () => request("/me"),
    conversations: () => request("/conversations"),
    messages: (conversationId) => request(`/conversations/${conversationId}/messages`),
    chat: (question, conversationId) =>
      request("/chat", {
        method: "POST",
        body: JSON.stringify({ question, conversation_id: conversationId }),
      }),
  };
}
