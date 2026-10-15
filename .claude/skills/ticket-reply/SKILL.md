---
name: ticket-reply
description: Draft a customer-facing reply to a support ticket, for the user to copy and paste. Use when the user asks for a reply, response, or message to send to a customer or to post in a ticket.
---

# Ticket reply

You only draft text. Never send it. No tool here can write to Pylon or Slack.

## Pick the syntax from the ticket source

Check the ticket's `source` field from Pylon `get_issue`, then use that channel's syntax:
- `slack`: `*bold*`, `_italics_`, `` `code` ``, bullets with `-`, plain URLs.
- `email`: plain text only. No Markdown.
- Anything else or unknown: ask which applies.

## Register

Short, direct, casual, like a colleague typing fast. Not a formal support agent. Target example:

```
Hi, working on the temp license bit. In the meantime, heads up for serialization:
1. Need to be on the same major version
2. DB/table/schema names across the two systems should match. If not, might need manual YAML manipulation to avoid errors during import of questions/dashboards
```

## Rules

- Do not restate what the customer said. No "thanks, that's clear" or "since you want X".
- Do not announce structure ("two things to line up"). Just number the items.
- Describe your own actions as status: "working on X", not "let me confirm X, I'll follow up".
- Use bare numbers (1, 2) for lists of discrete requirements, steps, or questions. This is the one place lists beat prose.
- Cut every clause that does not carry a fact or a question.
- Opening with just "Hi," or "Hi [name]," and then going straight to content is fine.
- Never use the em dash character. Links are plain URLs only.
- Never include internal-only content: Slack thread links, Linear issue links, Notion pages, other customers' names, or log lines with customer data. Say what you found, not where it came from.

## Before you hand it over

1. No em dash character.
2. All links are plain URLs.
3. No filler framing.
4. The syntax matches the ticket's source channel.
5. No internal-only links or customer data.

Fix any failure first. Then give the draft in one block the user can copy.
