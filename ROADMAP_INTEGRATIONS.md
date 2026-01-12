# Future Integrations Roadmap

## Current (Implemented)
- [x] Confluence - Documentation search
- [x] Jira - Ticket/issue search (same Atlassian OAuth)

---

## Phase 2: Google Workspace

### Google Calendar
**Value:** Auto-detect meeting context, show attendees, agenda
**API:** https://developers.google.com/workspace/calendar/api/v3/reference/events/list
**Auth:** Google OAuth 2.0
**Scopes:** `calendar.readonly`
**Effort:** Medium

### Google Docs
**Value:** Search PRDs, specs, reports
**API:** https://developers.google.com/docs/api/reference/rest/v1/documents/get
**Auth:** Same Google OAuth
**Scopes:** `documents.readonly`
**Effort:** Low (once Google OAuth exists)

### Google Drive
**Value:** Search files, PDFs, spreadsheets
**API:** https://developers.google.com/drive/api/v3/reference
**Auth:** Same Google OAuth
**Scopes:** `drive.readonly`
**Effort:** Low (once Google OAuth exists)

---

## Phase 3: Communication & Microsoft

### Slack
**Value:** Search channel discussions, decisions made in threads
**API:** https://api.slack.com/methods/conversations.history
**Auth:** Slack OAuth (separate provider)
**Scopes:** `channels:read`, `channels:history`, `groups:history`
**Effort:** High
**Challenges:**
- User must create Slack app OR we publish to Marketplace
- Bot must be added to each channel to read it
- Rate limits: 1 req/min for non-Marketplace apps (as of 2025)
- Marketplace publishing requires Slack review process

### Microsoft SharePoint
**Value:** Enterprise document storage (common in large orgs)
**API:** Microsoft Graph API
**Auth:** Microsoft OAuth 2.0 (Azure AD)
**Scopes:** `Sites.Read.All`
**Effort:** Medium

### Microsoft Teams (Calendar)
**Value:** Meeting context for Teams users
**API:** Microsoft Graph API
**Auth:** Same Microsoft OAuth
**Scopes:** `Calendars.Read`
**Effort:** Low (once Microsoft OAuth exists)

---

## Phase 4: Specialized

### Notion
**Value:** Popular in startups for docs/wikis
**API:** https://developers.notion.com/
**Auth:** Notion OAuth 2.0
**Effort:** Medium

### Linear
**Value:** Issue tracking (alternative to Jira, popular in startups)
**API:** https://developers.linear.app/docs/graphql/working-with-the-graphql-api
**Auth:** Linear OAuth 2.0
**Effort:** Medium

### Zendesk
**Value:** Support ticket history, help center articles
**API:** https://developer.zendesk.com/api-reference/
**Auth:** Zendesk OAuth 2.0
**Effort:** Medium

### Intercom
**Value:** Customer conversation history, help articles
**API:** https://developers.intercom.com/
**Auth:** Intercom OAuth 2.0
**Effort:** Medium

---

## Architecture Notes

### Multiple OAuth Providers
Each provider needs:
1. OAuth configuration (client ID, scopes, URLs)
2. Token storage in Keychain
3. Refresh token handling
4. UI in Settings for connect/disconnect

### Suggested Settings UI
```
┌─────────────────────────────────────────────────────────────┐
│ Data Sources                                                │
├─────────────────────────────────────────────────────────────┤
│ 🔵 Atlassian (Confluence + Jira)              [Connected]   │
│ 🟢 Google (Calendar + Docs + Drive)           [Connect]     │
│ 🟣 Slack                                      [Connect]     │
│ 🔷 Microsoft (SharePoint + Teams)             [Connect]     │
│ ⬛ Notion                                      [Connect]     │
└─────────────────────────────────────────────────────────────┘
```

### Search Priority
When answering questions, search sources in this order:
1. Most recently used sources
2. Sources matching detected keywords (e.g., "ticket" → Jira first)
3. All enabled sources in parallel

---

## Implementation Checklist Template

For each new integration:
- [ ] Research API capabilities and limits
- [ ] Implement OAuth flow (or add to existing provider)
- [ ] Create Client class in `Infrastructure/Tools/Clients/`
- [ ] Add to `ToolExecutor` and `ToolDefinitions`
- [ ] Add UI in Settings for configuration
- [ ] Test with real data
- [ ] Document required scopes/permissions
