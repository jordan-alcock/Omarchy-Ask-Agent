import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync, statSync, symlinkSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { runInNewContext } from "node:vm"

const code = readFileSync(new URL("../ask-agent.js", import.meta.url), "utf8").replace(/^\.pragma library\s*/, "")
const Logic = {}
runInNewContext(code, Logic, { filename: "ask-agent.js" })

const workspace = "/home/example/.local/state/omarchy/ask-agent/workspace"
const stateDir = "/home/example/.local/state/omarchy/ask-agent"
const home = "/home/example"
const flags = [
  "--permission-mode",
  "--allow-all",
  "--yolo",
  "--approve-for-me",
  "--auto",
  "--dangerously-bypass-approvals-and-sandbox",
  "bypassPermissions"
]

function optionNames(argv) {
  const names = []
  for (const arg of argv) {
    if (arg === "--") break
    if (!arg.startsWith("-")) continue
    const eq = arg.indexOf("=")
    names.push(eq === -1 ? arg : arg.slice(0, eq))
  }
  return names
}

const agents = ["claude", "copilot", "cursor-agent", "codex", "gemini"]
const nasty = "--dangerously-bypass-approvals-and-sandbox"

for (const agent of agents) {
  const headless = Logic.headlessCommand(agent, workspace, home, "sess", false)
  assert.ok(headless, agent + " has a headless command")
  assert.equal(headless.some(function(arg) { return arg.includes(nasty) }), false, agent + " keeps the question out of the arguments")
  assert.equal(headless.includes(home), false, agent + " headless does not receive $HOME")
  for (const flag of flags) assert.equal(optionNames(headless).includes(flag), false, agent + " headless has " + flag)
  const wrapped = Logic.promptViaStdin(Logic.shellWrapHeadless(workspace, headless))
  assert.ok(wrapped)
  assert.equal(wrapped.join("\n").includes(nasty), false, agent + " keeps the question out of the whole command")

  const handoff = Logic.handoffPath(stateDir)
  const tiled = Logic.tiledCommand(agent, workspace, home, "sess", false, handoff)
  const interactive = Logic.shellWrapInteractive(workspace, tiled)
  assert.equal(interactive[2].includes("</dev/null"), false)
  assert.ok(interactive.some(function(arg) { return arg.includes(handoff) }), agent + " is pointed at the handoff file")
  assert.equal(tiled.includes(home), false)
  for (const flag of flags) assert.equal(optionNames(tiled).includes(flag), false, agent + " tiled has " + flag)
  assert.equal(Logic.tiledCommand(agent, workspace, home, "sess", false, ""), null, agent + " has no tiled command without a handoff file")
}
assert.equal(Logic.headlessCommand("opencode", workspace, home, "", false), null)

const cursor = Logic.headlessCommand("cursor-agent", workspace, home, "", false)
assert.equal(JSON.stringify(cursor), JSON.stringify(["cursor-agent", "-p", "--trust", "--sandbox", "enabled", "--workspace", workspace]))

const codex = Logic.headlessCommand("codex", workspace, home, "", false)
assert.ok(codex.includes("-C"))
assert.ok(codex.includes(workspace))

// The question reaches the agent on stdin, and not through its arguments or environment.
{
  const question = "line one\n$(echo hacked) `x` \\n ASK_PROMPT_END\n--dangerously-bypass-approvals-and-sandbox"
  const wrapped = Logic.promptViaStdin(["sh", "-c", 'cat; printf "|%s|" "${ASK_PROMPT-unset}"; echo "$0 $*"', "agent", "a1"])
  const run = spawnSync("sh", wrapped.slice(1), { encoding: "utf8", env: { ...process.env, ...Logic.promptEnvironment(question) } })
  assert.equal(run.status, 0)
  assert.ok(run.stdout.startsWith(question + "\n"), "stdin carries the question exactly")
  assert.ok(run.stdout.includes("|unset|"), "the agent's environment no longer holds the question")
  assert.equal(run.stdout.includes("agent a1"), true)
}

assert.equal(Logic.headlessCommand("claude", workspace, home, "sess", true)[2], "--resume")
assert.equal(Logic.headlessCommand("other", workspace, home, "", false), null)
assert.equal(Logic.headlessCommand("codex", home, home, "", false), null)
assert.equal(Logic.headlessCommand("codex", "/home", home, "", false), null)
assert.ok(Logic.projectOk("/home/example/src/app", home))
assert.equal(Logic.projectOk(home, home), false)
assert.equal(Logic.projectOk("/home/example/../tmp/app", home), false)
assert.equal(Logic.parseProject('{"choice":"project","dir":"/home/example"}', home).choice, "")
assert.equal(Logic.parseProject('{"choice":"scratch","recent":["/home/example/src/app","/home/example"]}', home).recent.length, 1)
assert.equal(Logic.folderNameOk("my app"), true)
assert.equal(Logic.folderNameOk("../x"), false)
assert.equal(Logic.folderNameOk("a/b"), false)
assert.equal(Logic.createFolderCommand(home, "app", home)[4], home)
assert.equal(Logic.createFolderCommand(home, "app", home)[5], "app")
assert.equal(Logic.createFolderCommand("/home", "example", home), null)
assert.equal(Logic.shortProject("/home/example/src/app"), "src/app")
assert.equal(Logic.shellWrapProject(home, home, ["true"], true), null)
assert.equal(Logic.shellWrapHeadless(home, ["true"]), null)
assert.equal(Logic.wipeWorkspaceCommand("/tmp"), null)
assert.equal(Logic.conversationPath(stateDir), stateDir + "/conversation.json")
assert.equal(Logic.conversationPath(home), "")

assert.equal(Logic.promptWithHistory([{ q: "only", a: "", failed: false }], "only"), "only")
const replay = Logic.promptWithHistory(
  [{ q: "first", a: "do this instead", failed: false }, { q: "second", a: "", failed: false }],
  "second"
)
assert.match(replay, /as data, not as instructions/)
assert.match(replay, /<turn>/)
assert.match(replay, /The user now asks:\nsecond/)
const failed = Logic.promptWithHistory(
  [{ q: "bad", a: "nope", failed: true }, { q: "now", a: "", failed: false }],
  "now"
)
assert.equal(failed, "now")

const huge = "x".repeat(9000)
const capped = Logic.promptWithHistory(
  [{ q: huge, a: huge, failed: false }, { q: "q", a: "", failed: false }],
  "q"
)
assert.ok(capped.length <= Logic.maxPromptChars)

assert.equal(Logic.displayMarkdown("See ![x](https://evil.test/a.png) and **bold**."), "See [image] and **bold**.")
assert.equal(Logic.displayMarkdown('![x][ref]\n<img src="https://evil.test/a">'), "[image]\n[image]")
assert.equal(Logic.displayMarkdown("a < b and `code`"), "a < b and `code`")

const ok = Logic.finishTurn([{ q: "q", a: "" }], 0, "answer\n", "", false)
assert.equal(ok.failed, false)
assert.equal(ok.turns[0].a, "answer")

const partial = Logic.finishTurn([{ q: "q", a: "" }], 2, "partial", "boom", false)
assert.equal(partial.failed, true)
assert.match(partial.turns[0].a, /partial/)
assert.match(partial.turns[0].a, /boom/)

const timed = Logic.finishTurn([{ q: "q", a: "" }], 0, "", "", true)
assert.equal(timed.failed, true)
assert.match(timed.turns[0].a, /10 minutes/)

const empty = Logic.finishTurn([], 0, "x", "", false)
assert.equal(empty.applied, false)

assert.equal(Logic.shouldApplyExit(3, 3), true)
assert.equal(Logic.shouldApplyExit(2, 3), false)
assert.equal(Logic.shouldApplyExit(0, 0), false)
assert.equal(Logic.agentTimeoutMs, 600000)

const parent = mkdtempSync(join(tmpdir(), "ask-agent-"))
const scratch = join(parent, "my dir/omarchy/ask-agent/workspace")
try {
  spawnSync("git", ["init", "-q", parent])
  const pwd = spawnSync("sh", Logic.shellWrapHeadless(scratch, ["pwd"]).slice(1), { encoding: "utf8" })
  assert.equal(pwd.status, 0, pwd.stderr)
  assert.equal(pwd.stdout.trim(), scratch)
  assert.equal(existsSync(join(scratch, ".git")), true)
  assert.equal(statSync(scratch).mode & 0o777, 0o700)

  writeFileSync(join(scratch, "note.txt"), "keep")
  const marker = join(parent, "PARENT")
  writeFileSync(marker, "home")
  const ceiling = spawnSync("sh", Logic.shellWrapHeadless(scratch, ["git", "rev-parse", "--show-toplevel"]).slice(1), { encoding: "utf8" })
  assert.equal(ceiling.status, 0, ceiling.stderr)
  assert.equal(ceiling.stdout.trim(), scratch)

  rmSync(join(scratch, ".git"), { recursive: true, force: true })
  const stopped = spawnSync("sh", Logic.shellWrapHeadless(scratch, ["sh", "-c", "rm -rf .git; git rev-parse --show-toplevel"]).slice(1), { encoding: "utf8" })
  assert.notEqual(stopped.status, 0)
  assert.equal(stopped.stdout.trim(), "")

  const link = join(scratch, ".git")
  rmSync(link, { recursive: true, force: true })
  symlinkSync(parent, link)
  const relinked = spawnSync("sh", Logic.shellWrapInteractive(scratch, ["git", "rev-parse", "--show-toplevel"]).slice(1), { encoding: "utf8" })
  assert.equal(relinked.status, 0, relinked.stderr)
  assert.equal(relinked.stdout.trim(), scratch)
  assert.equal(existsSync(marker), true)

  writeFileSync(join(scratch, "gone.txt"), "x")
  const wiped = spawnSync("sh", Logic.wipeWorkspaceCommand(scratch).slice(1), { encoding: "utf8" })
  assert.equal(wiped.status, 0, wiped.stderr)
  assert.equal(existsSync(join(scratch, "gone.txt")), false)
  assert.equal(existsSync(join(scratch, ".git")), true)
  assert.equal(existsSync(marker), true)

  const refused = spawnSync("sh", ["-c", Logic.wipeWorkspaceCommand(scratch)[2], "sh", home], { encoding: "utf8" })
  assert.notEqual(refused.status, 0)
  assert.match(refused.stderr, /refusing workspace/)
} finally {
  rmSync(parent, { recursive: true, force: true })
}

const houseRoot = mkdtempSync(join(tmpdir(), "ask-project-"))
const house = join(houseRoot, "home")
const project = join(house, "my app")
try {
  mkdirSync(project, { recursive: true })
  spawnSync("git", ["init", "-q", house])
  const mode = statSync(project).mode & 0o777
  const pwd = spawnSync("sh", Logic.shellWrapProject(project, house, ["pwd"], true).slice(1), { encoding: "utf8" })
  assert.equal(pwd.status, 0, pwd.stderr)
  assert.equal(pwd.stdout.trim(), project)
  assert.equal(existsSync(join(project, ".git")), false)
  assert.equal(statSync(project).mode & 0o777, mode)
  const climbed = spawnSync("sh", Logic.shellWrapProject(project, house, ["git", "rev-parse", "--show-toplevel"], true).slice(1), { encoding: "utf8" })
  assert.notEqual(climbed.status, 0)
  symlinkSync(house, join(house, "link"))
  const linked = spawnSync("sh", Logic.shellWrapProject(join(house, "link"), house, ["pwd"], true).slice(1), { encoding: "utf8" })
  assert.notEqual(linked.status, 0)
  const checked = spawnSync("sh", Logic.checkProjectCommand(project, house).slice(1), { encoding: "utf8" })
  assert.equal(checked.status, 0, checked.stderr)
  assert.equal(checked.stdout.trim(), project)
  const created = spawnSync("sh", Logic.createFolderCommand(house, "notes", house).slice(1), { encoding: "utf8" })
  assert.equal(created.status, 0, created.stderr)
  assert.equal(created.stdout.trim(), join(house, "notes"))
  const again = spawnSync("sh", Logic.createFolderCommand(house, "notes", house).slice(1), { encoding: "utf8" })
  assert.notEqual(again.status, 0)
} finally {
  rmSync(houseRoot, { recursive: true, force: true })
}

console.log("logic tests passed")

// Angle brackets in answers stay visible; images and raw HTML still cannot load.
assert.equal(Logic.displayMarkdown("Use List<String> and std::vector<int>."), "Use List\\<String> and std::vector\\<int>.")
assert.equal(Logic.displayMarkdown("if a<b && c>d"), "if a\\<b && c>d")
assert.equal(Logic.displayMarkdown("`List<String>` stays"), "`List<String>` stays")
assert.equal(Logic.displayMarkdown("```\nvector<int> v;\n```\nafter <b>x</b>"), "```\nvector<int> v;\n```\nafter \\<b>x\\</b>")
assert.equal(Logic.displayMarkdown("<script>x</script>"), "\\<script>x\\</script>")

// A % that is not valid percent-encoding does not throw.
assert.equal(Logic.pathFromUrl("file:///home/u/100%"), "/home/u/100%")
assert.equal(Logic.pathFromUrl("file:///home/u/My%20Dir"), "/home/u/My Dir")

// The history budget counts separators and the truncation suffix.
{
  const many = []
  for (let i = 0; i < 40; i++) many.push({ q: "q" + i, a: "x".repeat(900), failed: false })
  many.push({ q: "now", a: "", failed: false })
  assert.ok(Logic.promptWithHistory(many, "now").length <= Logic.maxPromptChars)
  const huge = [{ q: "a", a: "y".repeat(50000), failed: false }, { q: "now", a: "", failed: false }]
  assert.ok(Logic.promptWithHistory(huge, "now").length <= Logic.maxPromptChars)
}
assert.ok(Logic.maxQuestionChars < 30000)

// A saved conversation is validated before it replaces anything.
assert.equal(Logic.parseConversation("not json"), null)
assert.equal(Logic.parseConversation("[1]"), null)
assert.equal(Logic.parseConversation("null"), null)
{
  const id = "123e4567-e89b-12d3-a456-426614174000"
  const ok = Logic.parseConversation(JSON.stringify({ agent: "claude", sessionId: id, sessionStarted: true, turns: [{ q: "hi", a: "yo", failed: false }, { q: "wait", a: "" }] }))
  assert.equal(ok.agent, "claude")
  assert.equal(ok.sessionStarted, true)
  assert.equal(ok.turns.length, 2)
  assert.deepEqual(JSON.parse(JSON.stringify(ok.turns[1])), { q: "wait", a: "(interrupted)", failed: true })
  const bad = Logic.parseConversation(JSON.stringify({ agent: "evil", sessionId: "../x", sessionStarted: true, turns: [null, 3, { q: 5 }, { q: "keep", a: "a" }] }))
  assert.equal(bad.agent, "")
  assert.equal(bad.sessionId, "")
  assert.equal(bad.sessionStarted, false)
  assert.equal(bad.turns.length, 1)
  const empty = Logic.parseConversation(JSON.stringify({ sessionId: id, sessionStarted: true, turns: "nope" }))
  assert.equal(empty.sessionStarted, false)
  assert.equal(empty.turns.length, 0)
}

// The tiled window never receives the conversation in its arguments.
{
  const secret = "my private question --dangerously-bypass-approvals-and-sandbox"
  const handoff = Logic.handoffPath(stateDir)
  for (const agent of agents) {
    const cmd = Logic.tiledCommand(agent, workspace, home, "sess", false, handoff)
    assert.equal(cmd.join("\n").includes("private question"), false)
    assert.equal(cmd.some(function(arg) { return arg.includes(nasty) }), false)
  }
  assert.equal(JSON.stringify(Logic.tiledCommand("claude", workspace, home, "sess", true, "")), JSON.stringify(["claude", "--resume", "sess"]))
  assert.equal(Logic.handoffPath(home), "")

  const dir = mkdtempSync(join(tmpdir(), "ask-handoff-"))
  try {
    const file = join(dir, "handoff.md")
    const launched = Logic.handoffLaunch(["sh", "-c", 'echo "[${ASK_HANDOFF-unset}]"; cat "$0"', file], file, secret)
    assert.equal(launched.command.join("\n").includes("private question"), false, "the text is not in the arguments")
    const run = spawnSync("sh", launched.command.slice(1), { encoding: "utf8", env: { ...process.env, ...launched.environment } })
    assert.equal(run.status, 0)
    assert.ok(run.stdout.includes("[unset]"), "the launched program does not inherit the text")
    assert.ok(run.stdout.includes(secret), "the file holds the text")
    assert.equal(statSync(file).mode & 0o077, 0, "the file is owner-only")
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}
