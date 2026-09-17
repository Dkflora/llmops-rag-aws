// Signing in. Amazon Cognito does the work; this ends by showing <Chat>.
import { useAuth } from "react-oidc-context";

import Chat from "./Chat.jsx";

// Cognito signs people in, and we pass its ID token to the chat.
export function CognitoSignIn() {
  const auth = useAuth();

  if (auth.isLoading) {
    return <p className="status-page">Signing you in…</p>;
  }

  if (auth.error) {
    return (
      <div className="login">
        <div className="mark" aria-hidden="true">N</div>
        <h1>Northwind HR Assistant</h1>
        <p>Sign-in didn't work: {auth.error.message}</p>
        <button onClick={() => auth.signinRedirect()}>Try again</button>
      </div>
    );
  }

  if (!auth.isAuthenticated) {
    return (
      <div className="login">
        <div className="mark" aria-hidden="true">N</div>
        <h1>Northwind HR Assistant</h1>
        <p>Sign in with your work account to start chatting.</p>
        <button onClick={() => auth.signinRedirect()}>Sign in</button>
      </div>
    );
  }

  // Signing out has two parts: forget the token here, and end the session at Cognito
  function signOut() {
    auth.removeUser();
    const cognitoDomain = import.meta.env.VITE_COGNITO_DOMAIN;
    const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
    const returnTo = encodeURIComponent(window.location.origin);
    window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${returnTo}`;
  }

  return <Chat signIn={{ token: auth.user.id_token }} onSignOut={signOut} />;
}
