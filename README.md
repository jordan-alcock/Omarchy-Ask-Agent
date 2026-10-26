# Ask agent

An "Ask agent…" button for the Omarchy bar. Click it, type a question, and the
answer appears in a small overlay under the bar. Reply in the same box to keep
going, or open the conversation in a tiled terminal window.

It uses whatever you set with `omarchy default agent`, so no agent is hard-coded.

## How it works

- The bar button opens a prompt overlay (`omarchy-shell shell toggle io.github.jordan-alcock.ask-agent '{}'`).
- Enter sends the question to your default agent in headless mode and shows the answer as markdown.
- **Claude Code:** follow-ups resume the same session, and "Open in tiled window"
  (`Ctrl+T`) resumes it in a terminal with `omarchy-launch-tui`.
- **Other agents** (`cursor-agent`, `codex`, `gemini`, `opencode`): each follow-up
  resends the earlier turns in the prompt. Only Claude Code has been tested so far.
- **Any other default agent:** skips the overlay and runs `omarchy agent prompt "<question>"`.

Keys: `Enter` send · `Ctrl+T` open in tiled window · `Esc` close.

## Install

```bash
omarchy plugin add https://github.com/jordan-alcock/Omarchy-Ask-Agent.git --enable
omarchy bar move io.github.jordan-alcock.ask-agent --section center --index 0
omarchy restart shell
```

The shell keeps this plugin loaded, so restart it after installing or updating.

## Requirements

| Needs | Why |
|---|---|
| Omarchy 4 (Quattro, `omarchy-shell`) | the plugin is a bar widget plus an overlay |
| A default agent: `omarchy default agent <name>` | the agent that answers |
| `claude`, `cursor-agent`, `codex`, `gemini` or `opencode` on `PATH` | headless answers in the overlay |

The plugin reads and stores nothing. It sends your question only to the agent
CLI you already use, and keeps the conversation in memory until you close the box.

## Removal

```bash
omarchy plugin remove io.github.jordan-alcock.ask-agent
omarchy restart shell
```

## License

MIT, see [LICENSE](LICENSE).
