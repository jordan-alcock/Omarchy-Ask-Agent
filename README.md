# Ask agent

![Ask agent overlay answering a question, with the agent picker, New chat, Copy answer and Open in tiled window buttons](preview.png)

Ask your AI agent a question without leaving what you are doing. Ask agent adds an
"Ask agent…" button to the Omarchy bar. Click it, type a question, and the answer appears
in a small overlay under the bar. Reply to keep the conversation going, or open it in a
tiled terminal window.

It uses the agent you have set with `omarchy default agent`. Before a chat starts, two
menus on the reply box let you pick a different installed agent and the folder it works in.

## Models

Ask agent currently works with **cloud-hosted models** through the agent CLIs you already
have installed:

| Agent | Status |
|---|---|
| Claude Code | Supported |
| Cursor CLI | Supported |
| Codex | Supported |
| GitHub Copilot | Supported |
| Gemini CLI | Should work, not yet verified |

**Local models are planned.** Support for running against local LLMs (for example through
Ollama) is on the roadmap, so your questions can stay on your own machine. It is not
available yet.

## Using it

1. Click **Ask agent…** in the bar (or use a keyboard shortcut, see below).
2. Type your question and press `Enter`.
3. Read the answer. Type a reply and press `Enter` to continue.
4. Press `Ctrl+T` to continue in a tiled terminal window, or `Esc` to close.

Your conversation is kept when you close the box. An answer still in progress finishes
and is there when you open it again. `Ctrl+N` stops that answer and clears the chat.
Opening a tiled window also clears the overlay history. Restarting the shell stops an
answer that has not finished yet.

| Key | Action |
|---|---|
| `Enter` | Send |
| `Ctrl+T` | Open in tiled window |
| `Ctrl+N` | New chat |
| `Esc` | Close |

### Project menu

The menu on the left sets the folder the agent works in. It locks once a chat has started.
Your home directory cannot be the project itself.

- **Recent folders** switch back to a folder you used before. Up to eight are kept. They are not deleted.
- **No project yet** uses a private empty folder at `~/.local/state/omarchy/ask-agent/workspace`. New chat empties it. A folder you picked is left alone.
- **Choose folder…** opens a folder window. The folder you pick becomes the project.
- **Create new folder…** opens a folder window for the parent, then asks for a name and creates that folder.

Open in a tiled window uses the same folder. There, the agent asks before it acts.

### Agent menu

The menu on the right picks which installed agent answers. It locks once a chat has started. Start a new chat to switch. With only one agent installed, the name is shown and the menu stays closed.

- **Default (name)** uses the agent from `omarchy default agent`.
- **An agent name** uses that agent for this chat.

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
- At least one of `claude`, `copilot`, `cursor-agent`, `codex` or `gemini`
  installed and signed in
- `wl-clipboard` (`wl-copy`), used by **Copy answer**. Included with Omarchy.
- `git`, used to keep the agent from searching above its folder and to create the
  **No project yet** scratch repo. Included with Omarchy.
- `omarchy-launch-tui`, used by **Open in tiled window**. Part of Omarchy.

## Outside the plugin

Ask agent does not change your default agent, theme, Hyprland config, other plugins, or
anything in `/usr/share/omarchy`.

- The install commands add the bar button to `~/.config/omarchy/shell.json`. A keybinding
  is added only if you edit `bindings.lua` yourself.
- While the box is open it takes the keyboard, so other windows do not receive keys until
  you close it. The keyboard goes to the folder window while that window is open.
- **Copy answer** replaces the Wayland clipboard.
- Its own files live in `~/.local/state/omarchy/ask-agent` (or under `$XDG_STATE_HOME`),
  readable only by you. **No project yet** creates a private Git repo in `workspace` and
  empties that repo when you start a new chat.
- A folder you pick is not turned into a Git repo, and its permissions are left alone.
  The agent runs inside it and can change files there, the same as if you started that
  agent yourself. For that run only, Git is kept from searching above the folder.
- **Create new folder…** creates the one directory you name.
- **Open in tiled window** opens a terminal with `omarchy-launch-tui`. In that terminal
  the agent asks before it acts.

## Privacy

Your questions go only to the agent you chose, the same as if you typed them into that
agent yourself. Because the supported agents are cloud-hosted, they are sent to that
provider.

Questions and **Copy answer** text are not put in command-line arguments, where other
users on the same machine could read them from `/proc`. Questions reach the agent on stdin
and copied text reaches `wl-copy` on stdin.

**Open in tiled window** also keeps the conversation out of the arguments. Claude and
Copilot resume their session with no prompt. For other agents (and for Claude or Copilot
before their first answer), the conversation is written to `handoff.md` in the owner-only
state folder, and the terminal agent is told to read that file. The agent asks your
permission to read it, because it sits outside the project folder. The file is removed when
you start a new chat.

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
