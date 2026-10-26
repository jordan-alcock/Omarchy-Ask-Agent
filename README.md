# Ask agent

![Ask agent overlay answering a question, with the agent picker, New chat, Copy answer and Open in tiled window buttons](preview.png)

Ask your AI agent a question without leaving what you are doing. Ask agent adds an
"Ask agent…" button to the Omarchy bar. Click it, type a question, and the answer appears
in a small overlay under the bar. Reply to keep the conversation going, or open it in a
tiled terminal window.

It uses the agent you have set with `omarchy default agent`, and you can pick a different
installed agent from a dropdown at any time.

## Models

Ask agent currently works with **cloud-hosted models** through the agent CLIs you already
have installed:

| Agent | Status |
|---|---|
| Claude Code | Supported |
| Cursor CLI | Supported |
| Codex | Supported |
| GitHub Copilot | Supported |
| Gemini CLI, opencode | Should work, not yet verified |

**Local models are planned.** Support for running against local LLMs (for example through
Ollama) is on the roadmap, so your questions can stay on your own machine. It is not
available yet.

## Using it

1. Click **Ask agent…** in the bar (or use a keyboard shortcut, see below).
2. Type your question and press `Enter`.
3. Read the answer. Type a reply and press `Enter` to continue.
4. Press `Ctrl+T` to continue in a tiled terminal window, or `Esc` to close.

Your conversation is kept when you close the box or restart the shell. It is cleared when
you open a tiled window or start a new chat.

| Key | Action |
|---|---|
| `Enter` | Send |
| `Ctrl+T` | Open in tiled window |
| `Ctrl+N` | New chat |
| `Esc` | Close |

### Choosing an agent

The dropdown at the right of the reply box lists the agents installed on your machine. It
defaults to your Omarchy default agent and locks once a chat has started. Start a new chat
to switch.

### Choosing a project folder

The project menu on the left of the box sets the folder the agent works in:

- **Choose folder…** picks an existing folder.
- **Create new folder…** picks a location, then asks for a name.
- **No project yet** uses an empty scratch folder, which is deleted when you start a new chat.
- Recent folders are remembered. A folder you picked is never deleted.

Your home directory cannot be used as the project itself. "Open in tiled window" uses the
same folder and starts the agent with its normal permission prompts.

### Copy and paste

Select answer text with the mouse and copy it, or use **Copy answer** for the latest reply.
Paste works in the reply box. Omarchy's `SUPER + C`, `SUPER + V` and `SUPER + X` work, as
do `Ctrl+C/V/X` and `Ctrl/Shift+Insert`. With nothing selected, copy takes the latest answer.

### Keyboard shortcut

Add a binding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + A", "Ask agent", "omarchy-shell shell toggle io.github.jordan-alcock.ask-agent '{}'")
```

It then shows up under Setup → Keybindings, where you can change it.

## Install

```bash
omarchy plugin add https://github.com/jordan-alcock/Omarchy-Ask-Agent.git --enable
omarchy bar move io.github.jordan-alcock.ask-agent --section center --index 0
omarchy restart shell
```

Restart the shell after installing or updating.

## Requirements

- Omarchy 4 (Quattro)
- A default agent, set with `omarchy default agent <name>`
- At least one of `claude`, `copilot`, `cursor-agent`, `codex`, `gemini` or `opencode`
  installed and signed in

## Privacy

Your questions go only to the agent you chose, the same as if you typed them into that
agent yourself. Because the supported agents are cloud-hosted, they are sent to that
provider.

The current conversation is saved, unencrypted, to
`~/.local/state/omarchy/ask-agent/conversation.json` (or under `$XDG_STATE_HOME`) until you
open it in a terminal or start a new chat. The folder is readable only by you. Answers are
shown as markdown with images and raw HTML left out.

## Removal

```bash
omarchy plugin remove io.github.jordan-alcock.ask-agent
rm -rf ~/.local/state/omarchy/ask-agent
omarchy restart shell
```

## License

MIT, see [LICENSE](LICENSE).
