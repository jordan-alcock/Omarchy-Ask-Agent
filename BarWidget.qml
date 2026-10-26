import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.jordan-alcock.ask-agent"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩  Ask agent…"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle io.github.jordan-alcock.ask-agent '{}'")
    }
  }
}
