# Magnific MCP Login Fix

## Symptom

Running:

```powershell
codex mcp login magnific
```

may finish the browser approval and then fail with:

```text
Error: failed to handle OAuth callback
Caused by:
    Authorization server response missing required issuer: expected https://auth.magnific.com/realms/mcp
```

## Cause

This is a Codex CLI OAuth callback regression, not a missing Magnific
configuration. Newer Codex versions can discard the OAuth `iss` callback
parameter that Magnific sends. The error appeared after the Codex OAuth
client changed its issuer validation behavior.

The Magnific MCP endpoint is:

```text
https://mcp.magnific.com
```

## Working fix

Use Codex `0.142.5` only for the login flow. It writes the credentials to the
same Codex profile used by the normal installation:

```powershell
npx -y @openai/codex@0.142.5 mcp login magnific
```

Complete the Magnific browser approval. A successful login ends with:

```text
Successfully logged in to MCP server 'magnific'.
```

The normal Codex installation can then reuse the saved credentials. Verify
the result with:

```powershell
codex mcp list
```

The Magnific row should show:

```text
Status   enabled
Auth     OAuth
```

This workaround does not replace or downgrade the installed Codex version;
it only uses the compatible CLI version for authentication.

## Persistence and updates

The credentials are stored in the active Codex profile, so a normal Codex
restart should not require another login. Re-authentication may be required
if the credentials are revoked, Codex data is cleared, `CODEX_HOME` changes,
or an update starts a fresh OAuth flow.

If the same issuer error returns after an update, repeat the compatible login
command above. The current Codex installation can continue using the saved
credentials after that.

## Alternative workaround

If the compatible CLI cannot be downloaded, use `mcp-remote` as a local stdio
bridge. Remove the direct Magnific entry and add the bridge instead:

```powershell
codex mcp remove magnific
codex mcp add magnific -- npx -y mcp-remote https://mcp.magnific.com
```

The bridge performs the OAuth flow independently of Codex's broken callback
handler. Use only one of the two configurations; do not keep both entries
with the same name.

## References

- [Magnific MCP documentation](https://www.magnific.com/ai/docs/magnific-mcp)
- [Codex MCP OAuth issuer issue](https://github.com/openai/codex/issues/34684)
- [mcp-remote](https://github.com/geelen/mcp-remote)
