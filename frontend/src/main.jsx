// The starting point of the React app: sign in with Cognito, then show the app.
import React from "react";
import ReactDOM from "react-dom/client";
import { AuthProvider } from "react-oidc-context";

import { CognitoSignIn } from "./SignIn.jsx";
import "./styles.css";

// Amazon Cognito, using the authorization code flow with PKCE.
const cognitoSettings = {
  authority: import.meta.env.VITE_COGNITO_AUTHORITY,
  client_id: import.meta.env.VITE_COGNITO_CLIENT_ID,
  redirect_uri: window.location.origin,
  response_type: "code",
  scope: "openid email",
  // After signing in, remove ?code=... from the address bar
  onSigninCallback: () => window.history.replaceState({}, document.title, window.location.pathname),
};

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <AuthProvider {...cognitoSettings}>
      <CognitoSignIn />
    </AuthProvider>
  </React.StrictMode>
);
