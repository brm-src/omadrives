import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.brm-src.omadrives"

  property string uiLanguage: Qt.locale().name.toLowerCase().startsWith("es") ? "es" : "en"
  readonly property bool isSpanish: uiLanguage === "es"
  function words(es, en) { return root.isSpanish ? es : en }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  // Bar icon lights up while a removable drive is mounted (something to eject).
  readonly property bool hasMountedRemovable: {
    var panel = panelLoader.item
    if (!panel || !panel.drives) return false
    for (var i = 0; i < panel.drives.length; i++) {
      if (panel.drives[i].removable && panel.drives[i].mounted) return true
    }
    return false
  }

  readonly property string panelTooltip: {
    var panel = panelLoader.item
    if (!panel || !panel.drives || panel.drives.length === 0)
      return root.words("OmaDrives · sin unidades", "OmaDrives · no drives")
    var removable = 0
    for (var i = 0; i < panel.drives.length; i++)
      if (panel.drives[i].removable) removable++
    return root.words("OmaDrives · " + panel.drives.length + " unidades",
                      "OmaDrives · " + panel.drives.length + " drives") +
      (removable > 0 ? " · " + removable + " " + root.words("extraíble(s)", "removable") : "")
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: true

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋊"
    slotSize: Style.bar.statusSlot
    opticalSize: 17
    tooltipText: root.panelTooltip
    active: root.opened || root.hasMountedRemovable
    useActiveColor: true
    activeColor: Color.accent

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
