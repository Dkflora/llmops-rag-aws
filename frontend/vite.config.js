import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Vite runs the React app while you develop, and builds the files that go to S3.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // `npm run dev` still works, against the deployed API. Set API_URL to the
    // API Gateway endpoint that Terraform prints:
    //   API_URL=$(terraform output -raw api_endpoint) npm run dev
    // Sign-in still goes to the real Cognito, which is why localhost:5173 is a
    // permitted callback URL. In production CloudFront does this routing.
    proxy: process.env.API_URL ? { "/api": process.env.API_URL } : undefined,
  },
});
