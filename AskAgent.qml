import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ask-agent.js" as Logic

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string homePath: Quickshell.env("HOME")
  property var shell: null
  property var manifest: null

  property bool opened: false
  // "input" while idle or typing, "working" while the agent answers
  property string phase: "input"
  // The conversation so far, one {q, a, failed} per exchange
  property var turns: []
  property string pendingQuestion: ""
  property string agent: ""
  property string sessionId: ""
  property bool sessionStarted: false
  // Bumped to ignore an agent exit that belongs to a cancelled or replaced run.
  property int runToken: 0
  property int lookupToken: 0
  property int killToken: 0
  property bool userMutated: false
  readonly property bool chatting: turns.length > 0
  // The agent picked in the dropdown ("" means the Omarchy default), the default
  // itself, and which of the supported agents are installed.
  property string chosenAgent: ""
  property string defaultAgent: ""
  property var installed: []
  property bool pickerOpen: false
  property bool projectMenuOpen: false
  readonly property var pickerOptions: [""].concat(installed)
  readonly property string transcript: turns.map(function(t) {
    var body = t.a === "" ? "_thinking…_" : Logic.displayMarkdown(t.a)
    return "**›** " + Logic.displayMarkdown(t.q) + "\n\n" + body
  }).join("\n\n---\n\n")

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Commons.Border.surfaceSpec("menu", "border", border, Math.max(1, Commons.Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Commons.Style.cornerRadius
  property string fontFamily: Commons.Style.font.menuFamily
  property int contentMargin: Commons.Style.spacing.panelPadding
  property int rowHeight: Math.max(Commons.Style.space(34), Commons.Style.font.title + Commons.Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Commons.Style.space(720), panel.width - Commons.Style.gapsOut * 2)
  property int answerHeight: Math.min(Commons.Style.space(420), panel.height * 0.55)

  // Omarchy's SUPER+C/V/X send Ctrl+C/V/X (or Ctrl/Shift+Insert in terminals) to the
  // focused surface, and the held SUPER can ride along as Meta, which Qt's own
  // shortcuts ignore. Classify the chord ourselves, whatever else is held.
  function clipboardAction(event) {
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    if (ctrl && event.key === Qt.Key_V) return "paste"
    if (shift && event.key === Qt.Key_Insert) return "paste"
    if (ctrl && event.key === Qt.Key_C) return "copy"
    if (ctrl && event.key === Qt.Key_Insert) return "copy"
    if (ctrl && event.key === Qt.Key_X) return "cut"
    return ""
  }

  function uuid() {
    uuidFile.reload()
    var id = (uuidFile.text() || "").trim().toLowerCase()
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id))
      return id
    return ""
  }

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (homePath + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy/ask-agent"
  // No project is selected from the bar, so the agent runs in this empty repo
  // instead of $HOME. New chat deletes it. Open in a tiled window keeps it.
  readonly property string workspaceDir: stateDir + "/workspace"
  readonly property string conversationPath: Logic.conversationPath(stateDir)
  readonly property string projectFilePath: Logic.projectPath(stateDir)
  // "" until the person picks, "project" for a chosen folder, "scratch" to skip.
  property string projectChoice: ""
  property string projectDir: ""
  property bool projectReady: false
  property bool projectChosen: false
  property var recentProjects: []
  property string createParent: homePath
  property bool creatingFolder: false
  property bool folderDialogOpen: false
  property string folderDialogMode: "browse"
  property string projectError: ""
  readonly property string activeDir: projectChoice === "project" ? projectDir : workspaceDir
  readonly property string projectButtonLabel: (projectChoice === "project" && projectDir
    ? Logic.baseName(projectDir)
    : projectChoice === "scratch" ? "No project" : "Project") + (chatting ? "" : " ▾")
  readonly property var projectMenuItems: {
    var items = []
    var recent = recentProjects || []
    for (var i = 0; i < recent.length; i++) {
      var dir = Logic.normalizeAbsolute(recent[i])
      if (!dir) continue
      items.push({ kind: "recent", dir: dir, label: Logic.shortProject(dir) })
    }
    items.push({ kind: "scratch", dir: "", label: "No project yet" })
    items.push({ kind: "browse", dir: "", label: "Choose folder…" })
    items.push({ kind: "create", dir: "", label: "Create new folder…" })
    return items
  }

  // The conversation lives here until it is opened in a terminal or cleared, so it
  // survives closing the overlay and restarting the shell.
  function save() {
    if (!root.conversationPath) return
    stateFile.setText(JSON.stringify({
      agent: root.agent,
      sessionId: root.sessionId,
      sessionStarted: root.sessionStarted,
      turns: root.turns
    }))
  }

  function restore(raw) {
    if (root.userMutated) return
    try {
      var data = JSON.parse(raw)
      var turns = (data.turns || []).map(function(t) {
        // A turn still waiting when the shell went away will never be answered
        return t.a === "" ? { q: t.q, a: "(interrupted)", failed: true } : t
      })
      root.agent = data.agent || ""
      root.sessionId = data.sessionId || ""
      root.sessionStarted = !!data.sessionStarted
      root.turns = turns
    } catch (e) {
      root.turns = []
    }
  }

  function execCommand(command) {
    if (command) Quickshell.execDetached(command)
  }

  // Drop a running agent. A later exit from that process is ignored.
  function cancelRun() {
    root.runToken += 1
    root.killToken = root.runToken
    agentTimeout.stop()
    agentProc.timedOut = false
    if (agentProc.running) {
      agentProc.running = false
      killTimer.restart()
    }
  }

  function resetConversation(wipeWorkspace) {
    root.cancelRun()
    root.lookupToken += 1
    if (agentNameProc.running) agentNameProc.running = false
    root.userMutated = true
    root.phase = "input"
    root.turns = []
    root.pendingQuestion = ""
    root.sessionId = ""
    root.sessionStarted = false
    root.agent = ""
    root.execCommand(Logic.removeConversationCommand(root.stateDir))
    if (wipeWorkspace) root.execCommand(Logic.wipeWorkspaceCommand(root.workspaceDir))
  }

  function clearConversation() {
    // A chosen project is theirs. Only the scratch repo is emptied.
    root.resetConversation(root.projectChoice !== "project")
    input.text = ""
  }

  function failCurrent(message) {
    var turns = root.turns.slice()
    if (turns.length === 0) return
    var last = turns[turns.length - 1]
    turns[turns.length - 1] = { q: last.q, a: message, failed: true }
    root.turns = turns
    root.phase = "input"
    root.save()
    root.scrollToEnd()
  }

  // payloadJson is the bar's toggle argument. It is not turned into a question.
  function open(payloadJson) {
    void payloadJson
    root.opened = true
    root.pickerOpen = false
    root.projectMenuOpen = root.projectReady && root.projectChoice === "" && !root.chatting
    defaultProc.running = true
    installedProc.running = true
    root.scrollToEnd()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function useFolder(dir) {
    if (projectCheck.running) return
    dir = Logic.normalizeAbsolute(dir)
    var command = Logic.checkProjectCommand(dir, root.homePath)
    if (!command) {
      root.projectError = "Pick a project folder. Your home directory stays out of reach."
      return
    }
    root.projectError = ""
    projectCheck.command = command
    projectCheck.running = true
  }

  function rememberProject(dir) {
    var next = [dir]
    var list = root.recentProjects || []
    for (var i = 0; i < list.length && next.length < 8; i++) {
      var item = Logic.normalizeAbsolute(list[i])
      if (item && item !== dir) next.push(item)
    }
    root.recentProjects = next
  }

  function acceptProject(dir) {
    dir = Logic.normalizeAbsolute(dir)
    if (!Logic.projectOk(dir, root.homePath)) {
      root.projectError = "Pick a project folder. Your home directory stays out of reach."
      return
    }
    root.projectChosen = true
    root.projectChoice = "project"
    root.projectDir = dir
    root.creatingFolder = false
    root.projectError = ""
    root.rememberProject(dir)
    root.saveProject()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function acceptScratch() {
    root.projectChosen = true
    root.projectChoice = "scratch"
    root.projectDir = ""
    root.creatingFolder = false
    root.projectError = ""
    root.saveProject()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function saveProject() {
    if (!root.projectFilePath) return
    projectFile.setText(JSON.stringify({
      choice: root.projectChoice,
      dir: root.projectChoice === "project" ? root.projectDir : "",
      recent: root.recentProjects || []
    }))
  }

  function applySavedProject(raw) {
    if (root.projectChosen) return
    var parsed = Logic.parseProject(raw, root.homePath)
    root.projectChoice = parsed.choice
    root.projectDir = parsed.dir
    root.recentProjects = parsed.recent || []
  }

  function chooseProjectItem(kind, dir) {
    root.projectMenuOpen = false
    if (kind === "recent") root.useFolder(dir)
    else if (kind === "scratch") root.acceptScratch()
    else if (kind === "browse") root.openFolderDialog("browse")
    else if (kind === "create") root.openFolderDialog("create")
  }

  function openFolderDialog(mode) {
    root.folderDialogMode = mode
    root.projectMenuOpen = false
    root.pickerOpen = false
    var start = mode === "create"
      ? (root.createParent || root.homePath)
      : (root.projectDir || root.homePath)
    folderDialog.currentFolder = Logic.fileUrl(start)
    root.folderDialogOpen = true
    Qt.callLater(function() { folderDialog.open() })
  }

  function createNewFolder() {
    if (mkdirProc.running) return
    var command = Logic.createFolderCommand(root.createParent, newFolderName.text, root.homePath)
    if (!command) {
      root.projectError = "Use a single folder name. The new folder cannot be your home directory."
      return
    }
    root.projectError = ""
    mkdirProc.command = command
    mkdirProc.running = true
  }

  function wrapAgent(command, closeStdin) {
    if (root.projectChoice === "project")
      return Logic.shellWrapProject(root.projectDir, root.homePath, command, closeStdin)
    return closeStdin
      ? Logic.shellWrapHeadless(root.workspaceDir, command)
      : Logic.shellWrapInteractive(root.workspaceDir, command)
  }

  onProjectReadyChanged: {
    if (root.opened && root.projectReady && root.projectChoice === "" && !root.chatting && !root.projectChosen)
      root.projectMenuOpen = true
  }

  function close() {
    root.opened = false
  }

  // Closing only hides the box. An answer still running keeps going and is saved
  // when it finishes. A click on another monitor must not cut the chat off.
  // New chat is what stops an answer.
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.jordan-alcock.ask-agent")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function submit() {
    var text = input.text.trim()
    if (!text || root.phase === "working" || root.creatingFolder) return
    if (root.projectChoice === "" && root.turns.length === 0) return
    root.userMutated = true
    if (!root.agent) root.agent = root.chosenAgent || root.defaultAgent
    root.pendingQuestion = text
    root.turns = root.turns.concat([{ q: text, a: "", failed: false }])
    input.text = ""
    root.phase = "working"
    root.save()
    root.scrollToEnd()
    if (root.agent) root.startAsk()
    else {
      root.lookupToken += 1
      agentNameProc.pendingToken = root.lookupToken
      agentNameProc.running = true
    }
  }

  function startAsk() {
    killTimer.stop()
    var prompt = (root.agent === "claude" || root.agent === "copilot")
      ? root.pendingQuestion
      : Logic.promptWithHistory(root.turns, root.pendingQuestion)
    if ((root.agent === "claude" || root.agent === "copilot") && !root.sessionStarted) {
      root.sessionId = root.uuid()
      if (!root.sessionId) {
        root.failCurrent("Could not start a session id.")
        return
      }
    }
    var command = Logic.headlessCommand(root.agent, root.activeDir, root.homePath, root.sessionId, root.sessionStarted, prompt)
    if (!command) {
      root.failCurrent(Logic.unsupportedAgentMessage(root.agent))
      return
    }
    var wrapped = root.wrapAgent(command, true)
    if (!wrapped) {
      root.failCurrent("Could not prepare the project folder for the agent.")
      return
    }
    root.runToken += 1
    agentProc.pendingToken = root.runToken
    agentProc.timedOut = false
    agentProc.command = wrapped
    agentProc.running = true
    agentTimeout.restart()
  }

  function finish() {
    var result = Logic.finishTurn(root.turns, agentProc.lastExit, outCollector.text, errCollector.text, agentProc.timedOut)
    agentProc.timedOut = false
    if (!result.applied) {
      root.phase = "input"
      return
    }
    root.turns = result.turns
    if (!result.failed) root.sessionStarted = true
    root.phase = "input"
    root.save()
    root.scrollToEnd()
    if (root.opened) Qt.callLater(function() { input.forceActiveFocus() })
  }

  // The selection if there is one, otherwise the latest answer.
  function copyAnswer() {
    var text = answerText.selectedText
    if (!text && root.turns.length > 0) text = root.turns[root.turns.length - 1].a
    if (text) Quickshell.execDetached(["wl-copy", "--", text])
  }

  function scrollToEnd() {
    Qt.callLater(function() {
      answerView.contentY = Math.max(0, answerView.contentHeight - answerView.height)
    })
  }

  function openTiled() {
    var last = root.turns.length > 0 ? root.turns[root.turns.length - 1].q : root.pendingQuestion
    var agent = root.agent
    var resumable = (agent === "claude" || agent === "copilot") && root.sessionStarted
    var prompt = (agent === "claude" || agent === "copilot")
      ? last
      : Logic.promptWithHistory(root.turns, last)
    var command = Logic.tiledCommand(agent, root.activeDir, root.homePath, root.sessionId, resumable, prompt)
    if (!command) {
      root.failCurrent(Logic.unsupportedAgentMessage(agent))
      return
    }
    var wrapped = root.wrapAgent(command, false)
    if (!wrapped) {
      root.failCurrent("Could not prepare the project folder for the agent.")
      return
    }
    var launch = [root.omarchyPath + "/bin/omarchy-launch-tui", "--app-id=org.omarchy.agent"].concat(wrapped)
    // Keep the scratch folder so the terminal sees files from this chat, and
    // drop the overlay history. The terminal session continues on its own.
    root.resetConversation(false)
    root.dismiss()
    Quickshell.execDetached(launch)
  }

  FileView {
    id: uuidFile
    path: "/proc/sys/kernel/random/uuid"
    blockAllReads: true
    preload: false
    printErrors: false
  }

  FileView {
    id: stateFile
    path: root.conversationPath
    printErrors: false
    // Rename over the destination so a symlink at conversation.json is replaced
    // rather than followed.
    atomicWrites: true
    onLoaded: root.restore(text())
    onSaved: root.execCommand(["chmod", "600", "--", root.conversationPath])
  }

  FileView {
    id: projectFile
    path: root.projectFilePath
    printErrors: false
    atomicWrites: true
    onLoaded: {
      root.applySavedProject(text())
      root.projectReady = true
    }
    onLoadFailed: root.projectReady = true
    onSaved: root.execCommand(["chmod", "600", "--", root.projectFilePath])
  }

  // Owner-only. chmod also tightens a folder an earlier version created with
  // the default mode. The workspace is the scratch repo agents run in.
  Component.onCompleted: root.execCommand(Logic.ensureStateCommand(root.stateDir, root.workspaceDir))

  Process {
    id: defaultProc
    command: [root.omarchyPath + "/bin/omarchy-default-agent"]
    stdout: StdioCollector { onStreamFinished: root.defaultAgent = text.trim() }
  }

  Process {
    id: installedProc
    command: ["sh", "-c", 'for a in claude copilot cursor-agent codex gemini opencode; do command -v "$a" >/dev/null 2>&1 && echo "$a"; done']
    stdout: StdioCollector {
      onStreamFinished: root.installed = text.trim().split("\n").filter(function(a) { return a })
    }
  }

  Process {
    id: agentNameProc
    property int pendingToken: 0
    property int liveToken: 0
    command: [root.omarchyPath + "/bin/omarchy-default-agent"]
    onStarted: liveToken = pendingToken
    stdout: StdioCollector {
      onStreamFinished: {
        var token = agentNameProc.liveToken
        agentNameProc.liveToken = 0
        if (token !== root.lookupToken || root.phase !== "working") return
        root.agent = text.trim()
        root.startAsk()
      }
    }
  }

  Process {
    id: agentProc
    property int pendingToken: 0
    property int liveToken: 0
    property int lastExit: 0
    property bool timedOut: false
    stdout: StdioCollector { id: outCollector }
    stderr: StdioCollector { id: errCollector }
    onStarted: liveToken = pendingToken
    // Quickshell delivers stdout and stderr to the collectors before exited.
    onExited: function(exitCode, exitStatus) {
      agentTimeout.stop()
      killTimer.stop()
      var token = liveToken
      liveToken = 0
      lastExit = exitCode
      if (!Logic.shouldApplyExit(token, root.runToken)) return
      root.finish()
    }
  }

  Timer {
    id: agentTimeout
    // 10 minutes. ask-agent.js agentTimeoutMs is the same value.
    interval: 600000
    onTriggered: {
      if (!agentProc.running) return
      agentProc.timedOut = true
      root.killToken = root.runToken
      agentProc.running = false
      killTimer.restart()
    }
  }

  Timer {
    id: killTimer
    interval: 2000
    onTriggered: {
      if (root.killToken !== root.runToken) return
      if (agentProc.running) agentProc.signal(9)
    }
  }

  Process {
    id: projectCheck
    stdout: StdioCollector { id: projectOut }
    stderr: StdioCollector { id: projectErr }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.projectError = projectErr.text.trim() || "That folder can't be used."
        return
      }
      root.acceptProject(projectOut.text.trim())
    }
  }

  Process {
    id: mkdirProc
    stdout: StdioCollector { id: mkdirOut }
    stderr: StdioCollector { id: mkdirErr }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.projectError = mkdirErr.text.trim() || "Could not create that folder."
        return
      }
      newFolderName.text = ""
      root.useFolder(mkdirOut.text.trim())
    }
  }

  FolderDialog {
    id: folderDialog
    title: root.folderDialogMode === "create" ? "Where should the new folder go?" : "Choose a project folder"
    acceptLabel: root.folderDialogMode === "create" ? "Choose" : "Use this folder"
    rejectLabel: "Cancel"
    onAccepted: {
      root.folderDialogOpen = false
      var dir = Logic.pathFromUrl(selectedFolder)
      if (!dir) {
        root.projectError = "That folder can't be used."
        return
      }
      if (root.folderDialogMode === "create") {
        root.createParent = dir
        root.creatingFolder = true
        root.projectError = ""
        Qt.callLater(function() { newFolderName.forceActiveFocus() })
      } else {
        root.useFolder(dir)
      }
    }
    onRejected: root.folderDialogOpen = false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-ask-agent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.folderDialogOpen ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: 0.4
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: projectMenu
      visible: root.projectMenuOpen && !root.chatting
      z: 10
      width: Commons.Style.space(280)
      height: projectMenuColumn.height + Commons.Style.spacing.md * 2
      x: card.x + root.contentMargin
      y: card.y + card.height + Commons.Style.spacing.md
      radius: root.cornerRadius
      color: root.background
      border.width: 1
      border.color: root.border

      Column {
        id: projectMenuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Commons.Style.spacing.md
        spacing: 2

        Repeater {
          model: root.projectMenuItems

          Rectangle {
            required property var modelData
            width: projectMenuColumn.width
            height: root.rowHeight * 0.8
            radius: root.cornerRadius
            color: projectOption.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Commons.Style.spacing.md
              anchors.rightMargin: Commons.Style.spacing.md
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: {
                var chosen = (modelData.kind === "recent" && root.projectChoice === "project" && modelData.dir === root.projectDir)
                  || (modelData.kind === "scratch" && root.projectChoice === "scratch")
                return (chosen ? "✓ " : "   ") + modelData.label
              }
              color: projectOption.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              id: projectOption
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.chooseProjectItem(modelData.kind, modelData.dir)
            }
          }
        }
      }
    }

    // Agent picker, shown under the card; the card's own click area closes it.
    Rectangle {
      id: pickerPopup
      visible: root.pickerOpen && !root.chatting && !root.projectMenuOpen
      z: 10
      width: Commons.Style.space(240)
      height: pickerColumn.height + Commons.Style.spacing.md * 2
      x: card.x + card.width - width - root.contentMargin
      y: card.y + card.height + Commons.Style.spacing.md
      radius: root.cornerRadius
      color: root.background
      border.width: 1
      border.color: root.border

      Column {
        id: pickerColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Commons.Style.spacing.md
        spacing: 2

        Repeater {
          model: root.pickerOptions

          Rectangle {
            required property string modelData
            width: pickerColumn.width
            height: root.rowHeight * 0.8
            radius: root.cornerRadius
            color: optionArea.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Commons.Style.spacing.md
              textFormat: Text.PlainText
              text: (modelData === root.chosenAgent ? "✓ " : "   ")
                + (modelData === "" ? "Default (" + (root.defaultAgent || "none") + ")" : modelData)
              color: optionArea.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              id: optionArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.chosenAgent = modelData
                root.pickerOpen = false
                input.forceActiveFocus()
              }
            }
          }
        }
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: (root.chatting
          ? root.answerHeight + root.rowHeight * 2 + root.contentMargin * 2 + Commons.Style.spacing.md * 2
          : root.rowHeight + root.contentMargin * 2)
        + (root.creatingFolder ? root.rowHeight * 2 + Commons.Style.spacing.md * 2 : 0)
        + (root.projectError !== "" ? root.rowHeight : 0)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: Commons.Style.space(48)
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {
          root.pickerOpen = false
          root.projectMenuOpen = false
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Commons.Style.spacing.md

        Column {
          visible: root.creatingFolder
          width: parent.width
          spacing: Commons.Style.spacing.md

          Text {
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            text: "New folder in " + root.createParent + "  · change"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.title

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openFolderDialog("create")
            }
          }

          Row {
            width: parent.width
            height: root.rowHeight
            spacing: Commons.Style.spacing.md

            TextInput {
              id: newFolderName
              width: parent.width - createButton.width - cancelCreate.width - Commons.Style.spacing.md * 2
              height: parent.height
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              selectionColor: root.foreground
              selectedTextColor: root.background
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.heading
              clip: true

              Text {
                visible: !newFolderName.text
                anchors.fill: parent
                textFormat: Text.PlainText
                text: "Folder name"
                color: root.foreground
                opacity: 0.58
                font: newFolderName.font
                verticalAlignment: Text.AlignVCenter
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.createNewFolder()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.creatingFolder = false
                  root.projectError = ""
                  input.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            Rectangle {
              id: createButton
              width: createLabel.implicitWidth + Commons.Style.spacing.md * 4
              height: parent.height
              radius: root.cornerRadius
              color: root.selectedBackground

              Text {
                id: createLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Create"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.title
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.createNewFolder()
              }
            }

            Rectangle {
              id: cancelCreate
              width: cancelCreateLabel.implicitWidth + Commons.Style.spacing.md * 4
              height: parent.height
              radius: root.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: root.border

              Text {
                id: cancelCreateLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Cancel"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.title
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.creatingFolder = false
                  root.projectError = ""
                  input.forceActiveFocus()
                }
              }
            }
          }
        }

        Text {
          visible: root.projectError !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.projectError
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.title
        }

        Flickable {
          id: answerView
          visible: root.chatting
          width: parent.width
          height: root.answerHeight
          contentWidth: width
          contentHeight: answerText.contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          // Selectable so answers can be copied; Ctrl+C copies the selection.
          TextEdit {
            id: answerText
            width: answerView.width
            readOnly: true
            selectByMouse: true
            persistentSelection: true
            textFormat: TextEdit.MarkdownText
            wrapMode: TextEdit.Wrap
            text: root.transcript
            color: root.foreground
            selectionColor: root.foreground
            selectedTextColor: root.background
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.title

            Keys.onPressed: function(event) {
              var ctrl = event.modifiers & Qt.ControlModifier
              var clip = root.clipboardAction(event)
              if (clip === "copy") {
                root.copyAnswer()
                event.accepted = true
              } else if (clip === "paste") {
                input.forceActiveFocus()
                input.paste()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_T) {
                root.openTiled()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_N) {
                root.clearConversation()
                event.accepted = true
              } else if (ctrl) {
                // Leave Ctrl+A and friends to the text itself
              } else if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
                // Printable typing goes back to the reply box. Modifier-only presses
                // such as SUPER (the first half of SUPER+C) carry no text and must
                // not steal focus, or the selection is lost before the copy.
                input.forceActiveFocus()
                input.insert(input.cursorPosition, event.text)
                event.accepted = true
              }
            }
          }
        }

        Item {
          width: parent.width
          height: root.rowHeight

          Rectangle {
            id: projectPicker
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - Commons.Style.spacing.md
            width: Math.min(projectPickerLabel.implicitWidth, Commons.Style.space(180)) + Commons.Style.spacing.md * 3
            radius: root.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: root.border

            Text {
              id: projectPickerLabel
              anchors.centerIn: parent
              width: Math.min(implicitWidth, Commons.Style.space(180))
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.projectButtonLabel
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              enabled: !root.chatting && root.phase !== "working"
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.pickerOpen = false
                root.projectMenuOpen = !root.projectMenuOpen
              }
            }
          }

          Rectangle {
            id: picker
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - Commons.Style.spacing.md
            width: pickerLabel.implicitWidth + Commons.Style.spacing.md * 3
            radius: root.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: root.border

            Text {
              id: pickerLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.chatting ? (root.agent || root.chosenAgent || root.defaultAgent || "agent")
                : ((root.chosenAgent || root.defaultAgent || "agent") + (root.installed.length > 1 ? " ▾" : ""))
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              enabled: !root.chatting && root.phase !== "working" && root.installed.length > 1
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.projectMenuOpen = false
                root.pickerOpen = !root.pickerOpen
              }
            }
          }

          TextInput {
            id: input
            anchors.left: projectPicker.right
            anchors.leftMargin: Commons.Style.spacing.md
            anchors.right: picker.left
            anchors.rightMargin: Commons.Style.spacing.md
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            enabled: root.phase !== "working"
            verticalAlignment: TextInput.AlignVCenter
            color: root.foreground
            selectionColor: root.foreground
            selectedTextColor: root.background
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.heading
            clip: true
            focus: true

            Keys.onPressed: function(event) {
              var clip = root.clipboardAction(event)
              if (clip === "paste") {
                input.paste()
                event.accepted = true
              } else if (clip === "copy") {
                // Nothing selected in the box: copy the latest answer instead
                if (input.selectedText) input.copy()
                else root.copyAnswer()
                event.accepted = true
              } else if (clip === "cut") {
                input.cut()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submit()
                event.accepted = true
              } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier) && root.chatting) {
                root.clearConversation()
                event.accepted = true
              } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier) && root.chatting) {
                root.openTiled()
                event.accepted = true
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: !input.text
              anchors.fill: parent
              text: root.phase === "working" ? "Waiting for " + (root.agent || "agent") + "…"
                  : root.chatting ? "Reply…" : "Ask your agent…"
              color: root.foreground
              opacity: 0.58
              font: input.font
              verticalAlignment: Text.AlignVCenter
            }
          }
        }

        Row {
          visible: root.chatting
          width: parent.width
          height: root.rowHeight
          spacing: Commons.Style.spacing.md
          layoutDirection: Qt.RightToLeft

          Rectangle {
            width: tiledLabel.implicitWidth + Commons.Style.spacing.md * 4
            height: parent.height
            radius: root.cornerRadius
            color: root.selectedBackground

            Text {
              id: tiledLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "Open in tiled window  ^T"
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openTiled()
            }
          }

          Rectangle {
            width: copyLabel.implicitWidth + Commons.Style.spacing.md * 4
            height: parent.height
            radius: root.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: root.border

            Text {
              id: copyLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "Copy answer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyAnswer()
            }
          }

          Rectangle {
            width: newLabel.implicitWidth + Commons.Style.spacing.md * 4
            height: parent.height
            radius: root.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: root.border

            Text {
              id: newLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "New chat  ^N"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearConversation()
            }
          }

          Rectangle {
            width: closeLabel.implicitWidth + Commons.Style.spacing.md * 4
            height: parent.height
            radius: root.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: root.border

            Text {
              id: closeLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "Close  Esc"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss()
            }
          }
        }
      }
    }
  }
}
