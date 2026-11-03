# Design and security

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

- **No Az / Microsoft.Graph modules.** Every Azure call is a plain REST call
  to Azure Resource Manager, Resource Graph and Cost Management, through one
  pooled `HttpClient`. Independent calls run in parallel, within each API's
  limits: Resource Manager 12 at a time, Resource Graph 4, Cost Management 3.
  Throttled calls wait as long as Azure's retry headers ask.
- **No app registration and no secrets.** The sign-in uses the authorization
  code flow with PKCE (RFC 7636) and a one-shot localhost listener. Tokens stay
  in memory for the session and are never written to disk.
- **Read-only.** No command or check changes anything in Azure. Key Vault keys
  and secrets are listed as metadata only, never their values.
- **Pinned bundled libraries.** [Spectre.Console](https://spectreconsole.net)
  (console UI) and PDFsharp + MigraDoc (PDF) ship in `lib\`, all MIT-licensed.
  Each DLL is checked against a pinned SHA-256 hash before it loads. See
  `lib\pdf\SOURCES.md`.
