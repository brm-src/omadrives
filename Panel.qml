import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.brm-src.omadrives"
  ipcTarget: "io.github.brm-src.omadrives"
  manageIpc: true

  property string uiLanguage: Qt.locale().name.toLowerCase().startsWith("es") ? "es" : "en"
  readonly property bool isSpanish: uiLanguage === "es"
  function words(es, en) { return root.isSpanish ? es : en }

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string helperPath: Qt.resolvedUrl("omadrives.py").toString().replace("file://", "")

  property var drives: []
  property string statusMessage: ""
  property string busyDev: ""
  property bool scanning: false
  property string pendingDev: ""
  property string pendingAction: ""

  function refresh() {
    if (root.scanning) return
    root.scanning = true
    listProc.command = ["python3", root.helperPath, "--lang", root.uiLanguage, "list"]
    listProc.running = true
  }

  function rescan() {
    if (root.busyDev !== "" || root.scanning) return
    root.scanning = true
    root.statusMessage = root.words("Buscando hardware nuevo…", "Looking for new hardware…")
    rescanProc.command = ["python3", root.helperPath, "--lang", root.uiLanguage, "rescan"]
    rescanProc.running = true
  }

  function openFromHotkey() {
    open()
    refresh()
  }

  function runAction(dev, action) {
    if (root.busyDev !== "") return
    root.busyDev = dev
    root.statusMessage = root.words("Trabajando…", "Working…")
    actionProc.command = ["python3", root.helperPath, "--lang", root.uiLanguage, action, "--dev", dev]
    actionProc.running = true
  }

  function requestAction(dev, action) {
    if (action === "poweroff" || action === "repair") {
      pendingDev = dev
      pendingAction = action
      confirmDialog.message = action === "repair"
        ? root.words("Repair can change filesystem metadata. Continue?", "Repair can change filesystem metadata. Continue?")
        : root.words("The drive will be unmounted and powered off. Unplug it only after confirmation.", "The drive will be unmounted and powered off. Unplug it only after confirmation.")
      confirmDialog.opened = true
      return
    }
    root.runAction(dev, action)
  }

  function confirmPending() {
    var dev = pendingDev
    var action = pendingAction
    pendingDev = ""
    pendingAction = ""
    confirmDialog.opened = false
    root.runAction(dev, action)
  }

  function openDrive(path) {
    if (!path) return
    root.statusMessage = root.words("Abriendo…", "Opening…")
    openProc.command = ["python3", root.helperPath, "--lang", root.uiLanguage, "open", "--path", path]
    openProc.running = true
  }

  function applyList(raw) {
    root.scanning = false
    try {
      var payload = JSON.parse(String(raw || "{}"))
      drives = payload.drives || []
      if (payload.ok === false) statusMessage = payload.error || ""
    } catch (error) {
      drives = []
      statusMessage = root.words("No se pudo leer el estado de las unidades.", "Could not read drive state.")
    }
  }

  function applyAction(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      statusMessage = payload.message || payload.error || root.words("Listo.", "Done.")
    } catch (error) {
      statusMessage = root.words("Respuesta ilegible del sistema.", "Unreadable system response.")
    }
    busyDev = ""
    Qt.callLater(refresh)
  }

  function kindIcon(drive) {
    return drive.removable ? "󰌟" : "󰋋"
  }

  function kindLabel(drive) {
    return drive.removable ? root.words("EXTRAÍBLE", "REMOVABLE") : root.words("INTERNO", "INTERNAL")
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 8000
    repeat: true
    running: root.opened
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyList(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAction(text)
    }
  }

  Process {
    id: rescanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.scanning = false
        root.applyAction(text)
      }
    }
  }

  Process {
    id: openProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAction(text)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: scroll.width
        spacing: Style.spacing.md

        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Column {
            width: parent.width - panelActions.width - Style.spacing.sm
            spacing: 1
            Text { text: "OMADRIVES"; color: Color.accent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.5 }
            Text {
              width: parent.width
              text: root.drives.length > 0
                ? root.drives.length + " " + root.words("unidades detectadas", "drives detected")
                : root.words("GESTIÓN DE UNIDADES", "DRIVE MANAGEMENT")
              color: Util.alpha(Color.menu.text, 0.45)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
          Row {
            id: panelActions
            spacing: Style.spacing.xs
            Button { iconText: "⌕"; foreground: Color.menu.text; tooltipText: root.words("Detectar hardware nuevo", "Detect new hardware"); enabled: !root.scanning; onClicked: root.rescan() }
            Button { iconText: "↻"; foreground: Color.menu.text; tooltipText: root.words("Buscar unidades (R)", "Rescan drives (R)"); enabled: !root.scanning; onClicked: root.refresh() }
            Button { iconText: "×"; foreground: Color.menu.text; tooltipText: root.words("Cerrar", "Close"); onClicked: root.close() }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.accent, 0.45) }

        Text {
          visible: root.statusMessage !== ""
          width: parent.width
          text: root.statusMessage
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          visible: root.drives.length === 0 && !root.scanning
          width: parent.width
          text: root.words("No hay particiones montables ahora mismo.\nConecta un disco o pendrive y pulsa ↻.",
                           "No mountable partitions right now.\nPlug a drive in and press ↻.")
          color: Util.alpha(Color.menu.text, 0.55)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Repeater {
          model: root.drives

          delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool busy: root.busyDev === modelData.dev

            width: contentColumn.width
            height: cardBody.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Util.alpha(Color.menu.text, 0.06)
            border.width: 1
            border.color: modelData.mounted ? Util.alpha(Color.accent, 0.5) : Util.alpha(Color.menu.text, 0.14)
            opacity: busy ? 0.6 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Column {
              id: cardBody
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(7)

              Row {
                width: parent.width
                spacing: Style.space(9)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.kindIcon(card.modelData)
                  color: Color.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.subtitle
                }
                Column {
                  width: parent.width - Style.space(32)
                  spacing: 1
                  Row {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      text: card.modelData.label || card.modelData.name
                      color: Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      width: Math.min(implicitWidth + 2, parent.width / 2)
                    }
                    Text {
                      text: card.modelData.name + " · " + String(card.modelData.fstype).toUpperCase() + " · " + card.modelData.size +
                        (card.modelData.readonly ? " · " + root.words("solo lectura", "read-only") : "")
                      color: Util.alpha(Color.menu.text, 0.45)
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width - (parent.children[0].width + parent.spacing)
                    }
                  }
                  Text {
                    width: parent.width
                    text: (card.modelData.model ? card.modelData.model + " · " : "") + root.kindLabel(card.modelData) +
                      (card.modelData.mounted && card.modelData.mountpoint ? "  ·  " + card.modelData.mountpoint : "")
                    color: Util.alpha(Color.menu.text, 0.55)
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.menu.text, 0.10) }

              Row {
                width: parent.width
                spacing: Style.spacing.xs

                component DriveButton: Button {
                  height: 26
                  fontSize: Style.font.caption
                  fontFamily: Style.font.menuFamily
                  foreground: Color.menu.text
                  accent: Color.accent
                }

                DriveButton {
                  visible: !card.modelData.mounted
                  text: root.words("Montar", "Mount")
                  bordered: true
                  enabled: !card.busy && !card.modelData.readonly && card.modelData.mountable
                  tooltipText: root.words("Monta la partición en /run/media.", "Mount the partition under /run/media.")
                  onClicked: root.runAction(card.modelData.dev, "mount")
                }
                DriveButton {
                  visible: card.modelData.mounted
                  text: root.words("Abrir", "Open")
                  bordered: true
                  enabled: !card.busy
                  tooltipText: root.words("Abre la carpeta en el gestor de archivos.", "Open the folder in the file manager.")
                  onClicked: root.openDrive(card.modelData.mountpoint)
                }
                DriveButton {
                  visible: card.modelData.mounted
                  text: root.words("Desmontar", "Unmount")
                  bordered: true
                  enabled: !card.busy
                  onClicked: root.runAction(card.modelData.dev, "unmount")
                }
                DriveButton {
                  visible: card.modelData.removable
                  text: root.words("Extraer", "Eject")
                  background: Color.accent
                  foreground: Color.background
                  enabled: !card.busy
                  tooltipText: root.words("Desmonta y apaga la unidad para desconectarla con seguridad.", "Unmounts and powers off the drive so you can unplug it safely.")
                  onClicked: root.requestAction(card.modelData.dev, "poweroff")
                }
                DriveButton {
                  visible: card.modelData.repairable
                  text: root.words("Reparar", "Repair")
                  bordered: true
                  enabled: !card.busy
                  tooltipText: root.words("Corrige errores del sistema de archivos (NTFS, FAT, ext). Puede pedir tu contraseña una vez.", "Fixes filesystem errors (NTFS, FAT, ext). May ask for your password once.")
                  onClicked: root.requestAction(card.modelData.dev, "repair")
                }
              }

              Text {
                visible: card.modelData.removable
                width: parent.width
                text: root.words("Extraer desmonta todo el disco y lo apaga.",
                                 "Eject unmounts the whole disk and powers it off.")
                color: Util.alpha(Color.menu.text, 0.38)
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }
          }
        }

        Item { width: 1; height: Style.space(2) }

        Text {
          width: parent.width
          text: "OMADRIVES 1.0"
          color: Util.alpha(Color.menu.text, 0.28)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.0
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      z: 20
      background: Color.menu.background
      foreground: Color.menu.text
      selectedText: Color.accent
      cancelText: root.words("Cancel", "Cancel")
      confirmText: root.words("Continue", "Continue")
      onCanceled: { opened = false; root.pendingDev = ""; root.pendingAction = "" }
      onConfirmed: root.confirmPending()
    }
  }
}
