import QtQuick
import QtQuick.Window
import "../../ask-agent.js" as Logic

Window {
  width: 600; height: 800; visible: true
  property string u: "http://127.0.0.1:8765/"
  property var payloads: [
    ["CONTROL-raw-inline", false, "![x](" + u + "control-inline)"],
    ["CONTROL-raw-img-tag", false, "<img src=\"" + u + "control-imgtag\">"],
    ["filtered-inline", true, "![x](" + u + "f-inline)"],
    ["filtered-shortcut", true, "[x]: " + u + "f-shortcut\n\nsee ![x] here"],
    ["filtered-collapsed", true, "[x]: " + u + "f-collapsed\n\n![x][]"],
    ["filtered-full", true, "[x]: " + u + "f-full\n\n![alt][x]"],
    ["filtered-escbackslash", true, "[x]: " + u + "f-escbs\n\n\\\\![x]"],
    ["filtered-badfence", true, "[x]: " + u + "f-badfence\n\n``` a`b\n![x]\n```"],
    ["filtered-imgtag", true, "<img src=\"" + u + "f-imgtag\">"],
    ["filtered-imgnewline", true, "<img\nsrc=\"" + u + "f-imgnl\">"],
    ["filtered-IMG", true, "<IMG/src=\"" + u + "f-IMG\">"],
    ["filtered-svg", true, "<svg><image href=\"" + u + "f-svg\"/></svg>"],
    ["filtered-link", true, "[click](" + u + "f-link) <" + u + "f-autolink>"],
    ["filtered-html-style", true, "<div style=\"background:url(" + u + "f-css)\">x</div>"],
    ["filtered-table", true, "| a |\n|---|\n| ![x](" + u + "f-table) |"],
    ["filtered-html-block", true, "<p><img src=" + u + "f-block></p>"]
  ]
  Column {
    Repeater {
      model: payloads
      TextEdit {
        required property var modelData
        width: 600; height: 40
        readOnly: true
        textFormat: TextEdit.MarkdownText
        text: modelData[1] ? Logic.displayMarkdown(modelData[2]) : modelData[2]
      }
    }
  }
  Timer { interval: 4000; running: true; onTriggered: Qt.quit() }
}
