import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

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
  readonly property bool chatting: turns.length > 0
  readonly property string transcript: turns.map(function(t) {
    return "**›** " + t.q + "\n\n" + (t.a === "" ? "_thinking…_" : t.a)
  }).join("\n\n---\n\n")

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  property int answerHeight: Math.min(Style.space(420), panel.height * 0.55)

  // Agents whose non-interactive flags are known. Anything else skips the answer
  // window and opens straight in a tiled terminal, as `omarchy agent prompt` does.
  readonly property var headless: ({
    "claude": ["claude", "-p"],
    "copilot": ["copilot", "-s", "--no-ask-user"],
    "cursor-agent": ["cursor-agent", "-p", "--trust"],
    "codex": ["codex", "exec"],
    "gemini": ["gemini", "-p"],
    "opencode": ["opencode", "run"]
  })

  function uuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
      var r = Math.random() * 16 | 0
      return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
    })
  }

  readonly property string stateDir: homePath + "/.local/state/omarchy/ask-agent"

  // The conversation lives here until it is opened in a terminal or cleared, so it
  // survives closing the overlay and restarting the shell.
  function save() {
    stateFile.setText(JSON.stringify({
      agent: root.agent,
      sessionId: root.sessionId,
      sessionStarted: root.sessionStarted,
      turns: root.turns
    }))
  }

  function restore(raw) {
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

  function clearConversation() {
    agentProc.running = false
    finishTimer.stop()
    root.phase = "input"
    root.turns = []
    root.pendingQuestion = ""
    root.sessionId = ""
    root.sessionStarted = false
    root.agent = ""
    input.text = ""
    Quickshell.execDetached(["rm", "-f", root.stateDir + "/conversation.json"])
  }

  function open(payloadJson) {
    root.opened = true
    root.scrollToEnd()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // Closing keeps the conversation; an answer still in flight lands in the history.
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
    if (!text || root.phase === "working") return
    root.pendingQuestion = text
    root.turns = root.turns.concat([{ q: text, a: "", failed: false }])
    input.text = ""
    root.phase = "working"
    root.save()
    root.scrollToEnd()
    if (root.agent) root.startAsk()
    else agentNameProc.running = true
  }

  // Agents without a resumable headless session get the conversation replayed.
  function promptWithHistory(question) {
    var done = root.turns.slice(0, root.turns.length - 1).filter(function(t) { return !t.failed })
    if (done.length === 0) return question
    var out = "Earlier in this conversation:\n\n"
    done.forEach(function(t) { out += "User: " + t.q + "\nAssistant: " + t.a + "\n\n" })
    return out + "Continue it. The user now asks:\n" + question
  }

  function startAsk() {
    var base = root.headless[root.agent]
    if (!base) {
      root.openTiled()
      return
    }
    var command = base.slice()
    var question = root.pendingQuestion
    if (root.agent === "claude") {
      if (root.sessionStarted) {
        command.push("--resume", root.sessionId)
      } else {
        root.sessionId = root.uuid()
        command.push("--session-id", root.sessionId)
      }
      command.push("--")
      command.push(question)
    } else if (root.agent === "copilot") {
      // --session-id starts a session the first time and resumes it afterwards
      if (!root.sessionStarted) root.sessionId = root.uuid()
      command.push("--session-id", root.sessionId)
      command.push("--prompt=" + question)
    } else {
      command.push(root.promptWithHistory(question))
    }
    agentProc.command = command
    agentProc.running = true
  }

  function finish() {
    var text = outCollector.text.trim()
    var failed = false
    if (agentProc.lastExit !== 0 && !text) {
      failed = true
      text = errCollector.text.trim() || ("The agent exited with code " + agentProc.lastExit)
    }
    var turns = root.turns.slice()
    turns[turns.length - 1] = { q: turns[turns.length - 1].q, a: text || "(no answer)", failed: failed }
    root.turns = turns
    if (!failed) root.sessionStarted = true
    root.phase = "input"
    root.save()
    root.scrollToEnd()
    Qt.callLater(function() { input.forceActiveFocus() })
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
    var session = root.sessionId
    var resumable = (agent === "claude" || agent === "copilot") && root.sessionStarted
    var prompt = root.promptWithHistory(last)
    root.clearConversation()
    root.dismiss()
    if (resumable) {
      var resume = agent === "claude"
        ? ["claude", "--permission-mode", "auto", "--resume", session]
        : ["copilot", "--allow-all", "--session-id", session]
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-launch-tui", "--app-id=org.omarchy.agent"].concat(resume))
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-agent-prompt", prompt])
    }
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/conversation.json"
    printErrors: false
    onLoaded: root.restore(text())
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

  Process {
    id: agentNameProc
    command: [root.omarchyPath + "/bin/omarchy-default-agent"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.agent = text.trim()
        root.startAsk()
      }
    }
  }

  Process {
    id: agentProc
    property int lastExit: 0
    workingDirectory: root.homePath
    stdout: StdioCollector { id: outCollector }
    stderr: StdioCollector { id: errCollector }
    onExited: function(exitCode, exitStatus) {
      lastExit = exitCode
      finishTimer.restart()
    }
  }

  // The collectors can still be flushing when the process exits.
  Timer {
    id: finishTimer
    interval: 120
    onTriggered: root.finish()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-ask-agent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.chatting
        ? root.answerHeight + root.rowHeight * 2 + root.contentMargin * 2 + Style.spacing.md * 2
        : root.rowHeight + root.contentMargin * 2
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(48)
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

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
            textFormat: TextEdit.MarkdownText
            wrapMode: TextEdit.Wrap
            text: root.transcript
            color: root.foreground
            selectionColor: root.foreground
            selectedTextColor: root.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.title

            Keys.onPressed: function(event) {
              var ctrl = event.modifiers & Qt.ControlModifier
              if (event.key === Qt.Key_Escape) {
                root.dismiss()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_T) {
                root.openTiled()
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_N) {
                root.clearConversation()
                event.accepted = true
              } else if (ctrl || event.key === Qt.Key_Shift || event.key === Qt.Key_Control) {
                // Leave Ctrl+C, Ctrl+A and friends to the text itself
              } else {
                // Anything else is typing: hand it back to the reply box
                input.forceActiveFocus()
                if (event.text) input.insert(input.cursorPosition, event.text)
                event.accepted = true
              }
            }
          }
        }

        Item {
          width: parent.width
          height: root.rowHeight

          TextInput {
            id: input
            anchors.fill: parent
            enabled: root.phase !== "working"
            verticalAlignment: TextInput.AlignVCenter
            color: root.foreground
            selectionColor: root.foreground
            selectedTextColor: root.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            clip: true
            focus: true

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
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
          spacing: Style.spacing.md
          layoutDirection: Qt.RightToLeft

          Rectangle {
            width: tiledLabel.implicitWidth + Style.spacing.md * 4
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
              font.pixelSize: Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openTiled()
            }
          }

          Rectangle {
            width: copyLabel.implicitWidth + Style.spacing.md * 4
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
              font.pixelSize: Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyAnswer()
            }
          }

          Rectangle {
            width: newLabel.implicitWidth + Style.spacing.md * 4
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
              font.pixelSize: Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearConversation()
            }
          }

          Rectangle {
            width: closeLabel.implicitWidth + Style.spacing.md * 4
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
              font.pixelSize: Style.font.title
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
