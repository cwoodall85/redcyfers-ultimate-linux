/*
 * Claude Bar -- ask Claude from the top panel.
 *
 * Type and press Enter: `ultimate-claude-bar ask` starts Claude in the
 * background. Its steps and answer are drawn over the desktop by the
 * Cognition wallpaper; this widget shows a one-line status. Esc (or the
 * clear button) dismisses the answer. Meta+Space focuses the field.
 *
 * Commands run through Plasma's executable data engine; the question is
 * passed single-quoted, so nothing typed here is interpreted by a shell.
 *
 * The mode button switches between Ask (read-only: Claude looks and tells
 * you what to run) and Assistant (Claude acts). In Assistant mode anything
 * that changes something waits here as a question with Allow / Deny.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var run: ({})
    // The text field lives inside fullRepresentation, a separate component:
    // its id isn't visible from here, so it registers itself.
    property Item field: null
    readonly property bool busy: run.status === "thinking" || run.status === "listening"
    readonly property bool listening: run.status === "listening"
    readonly property bool speaking: !!run.speak
    readonly property bool assistant: run.mode === "assistant"
    readonly property var pending: run.pending || null

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            if (source === root.stateCmd) {
                try { root.run = JSON.parse(data["stdout"] || "{}") } catch (e) {}
            } else if (source === root.historyCmd) {
                try { root.history = JSON.parse(data["stdout"] || "[]") } catch (e) {}
            }
            disconnectSource(source)
        }
    }
    readonly property string stateCmd: "ultimate-claude-bar state"
    readonly property string historyCmd: "ultimate-claude-bar history 50"

    // Earlier answers: the desktop panel shows one run at a time and can't
    // scroll, so every finished run is kept and readable here.
    property var history: []
    property bool historyOpen: false
    function loadHistory() { shell.connectSource(root.historyCmd) }
    onHistoryOpenChanged: if (historyOpen) loadHistory()
    property string lastStatus: ""
    onRunChanged: {
        if (run.status !== lastStatus && (run.status === "done" || run.status === "error") && historyOpen)
            loadHistory()
        lastStatus = run.status || ""
    }

    Timer {
        interval: root.busy ? 400 : 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.connectSource(root.stateCmd)
    }

    function ask(text) {
        if (!text.trim())
            return
        shell.connectSource("ultimate-claude-bar ask -- " + quote(text.trim()))
        root.run = { status: "thinking", prompt: text, steps: [] }
    }

    function setMode(m) {
        shell.connectSource("ultimate-claude-bar mode " + m)
        root.run = Object.assign({}, root.run, { mode: m })
    }

    function answer(decision) {
        if (!root.pending)
            return
        shell.connectSource("ultimate-claude-bar " + decision + " " + quote(root.pending.id))
        root.run = Object.assign({}, root.run, { pending: null })
    }

    function listen() {
        shell.connectSource("ultimate-claude-bar listen")
        root.run = Object.assign({}, root.run, { status: "listening", steps: [], pending: null })
    }

    function setSpeak(on) {
        shell.connectSource("ultimate-claude-bar speak " + (on ? "on" : "off"))
        root.run = Object.assign({}, root.run, { speak: on })
    }

    function dismiss() {
        shell.connectSource("ultimate-claude-bar clear")
        root.run = {}
    }

    // A panel only takes keyboard focus while a widget declares it is
    // accepting input; without this, Meta+Space activated the widget but
    // typing went to the desktop (and on to KRunner's type-to-search).
    function takeFocus() {
        Plasmoid.status = PlasmaCore.Types.AcceptingInputStatus
        if (root.field) {
            root.field.forceActiveFocus()
            root.field.selectAll()
        }
    }
    function releaseFocus() {
        Plasmoid.status = PlasmaCore.Types.ActiveStatus
    }

    Connections {
        target: Plasmoid
        function onActivated() { root.takeFocus() }
    }

    // The assistant's question, big enough to read: what it wants to do, the
    // exact command or change (scrolls), and Allow / Deny. It opens under the
    // bar whenever a new question arrives.
    // Declarative on purpose: the first question can arrive before the bar's
    // own item exists, and a dialog shown with no visual parent never
    // appears. "Later" hides one question until the ⚑ button asks again.
    property string laterQuestion: ""
    readonly property bool askOpen: !!root.pending && root.pending.id !== root.laterQuestion
                                    && root.fullRepresentationItem !== null

    PlasmaCore.Dialog {
        id: askDialog
        visible: root.askOpen
        visualParent: root.fullRepresentationItem
        location: Plasmoid.location
        type: PlasmaCore.Dialog.Normal
        flags: Qt.WindowStaysOnTopHint
        hideOnWindowDeactivate: false

        // A Dialog takes its size from mainItem's width and height, not the
        // implicit ones: without them it cut off after two lines.
        mainItem: Item {
            width: Kirigami.Units.gridUnit * 36
            height: askColumn.implicitHeight

            // opaque: the question must be readable over whatever is behind
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Kirigami.Units.smallSpacing
                color: Kirigami.Theme.backgroundColor
                radius: Kirigami.Units.cornerRadius
            }

          ColumnLayout {
            id: askColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                level: 3
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.pending ? i18n("Claude would like to: %1", root.pending.title) : ""
            }
            PC3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                visible: !!root.pending && root.pending.tool !== "Bash"
                text: root.pending ? root.pending.tool : ""
            }
            PC3.ScrollView {
                clip: true
                Layout.fillWidth: true
                // one line of the command per line, 3 to 14 of them; it scrolls beyond
                readonly property int lines: root.pending && root.pending.detail
                                             ? root.pending.detail.split("\n").length : 0
                Layout.preferredHeight: Math.round(Math.min(14, Math.max(3, lines + 1)) * detailText.font.pixelSize * 1.45
                                                   + Kirigami.Units.largeSpacing * 2)
                visible: !!root.pending && !!root.pending.detail
                PC3.TextArea {
                    id: detailText
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    font.family: "JetBrains Mono"
                    text: root.pending ? root.pending.detail : ""
                    // start at the top: the first line is usually the one that matters
                    onTextChanged: cursorPosition = 0
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                PC3.Button {
                    text: i18n("Deny")
                    icon.name: "dialog-cancel"
                    onClicked: root.answer("deny")
                }
                PC3.Button {
                    text: i18n("Just this step")
                    visible: !root.pending || !root.pending.risky
                    PC3.ToolTip.text: i18n("Allow only this step; Claude asks again for the next change")
                    PC3.ToolTip.visible: hovered
                    onClicked: root.answer("allow-once")
                }
                PC3.Button {
                    text: root.pending && root.pending.risky ? i18n("Allow this") : i18n("Allow")
                    icon.name: "dialog-ok-apply"
                    PC3.ToolTip.text: root.pending && root.pending.risky
                        ? i18n("This one always asks (sudo, disks, force-push): allows just this step")
                        : i18n("Allow this and the rest of this task; Claude tells you if it had to do anything different")
                    PC3.ToolTip.visible: hovered
                    onClicked: root.answer("allow")
                }
                PC3.Button {
                    text: i18n("Later")
                    icon.name: "window-minimize"
                    PC3.ToolTip.text: i18n("Hide this; the ⚑ button in the bar brings it back")
                    PC3.ToolTip.visible: hovered
                    onClicked: root.laterQuestion = root.pending ? root.pending.id : ""
                }
            }
          }
        }
    }

    // History: every answer, newest at the bottom, scrollable, text selectable
    // for copying. A real window, so it scrolls where the wallpaper can't.
    PlasmaCore.Dialog {
        id: historyDialog
        visible: root.historyOpen && root.fullRepresentationItem !== null
        visualParent: root.fullRepresentationItem
        location: Plasmoid.location
        type: PlasmaCore.Dialog.Normal
        // stays open while you type the next question; the history button closes it
        hideOnWindowDeactivate: false

        mainItem: Item {
            width: Kirigami.Units.gridUnit * 42
            height: Kirigami.Units.gridUnit * 34

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Kirigami.Units.smallSpacing
                color: Kirigami.Theme.backgroundColor
                radius: Kirigami.Units.cornerRadius
            }

            PC3.ScrollView {
                id: historyScroll
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: historyColumn
                    width: historyScroll.availableWidth
                    spacing: Kirigami.Units.largeSpacing * 2
                    // open at the newest answer
                    onImplicitHeightChanged: Qt.callLater(() => {
                        const f = historyScroll.contentItem
                        f.contentY = Math.max(0, f.contentHeight - f.height)
                    })

                    PC3.Label {
                        Layout.fillWidth: true
                        visible: root.history.length === 0
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                        text: i18n("No answers yet. Everything Claude answers from now on is kept here.")
                    }

                    Repeater {
                        model: root.history
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                Layout.fillWidth: true
                                opacity: 0.6
                                font.family: "JetBrains Mono"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                text: {
                                    const d = modelData.finished ? new Date(modelData.finished * 1000) : null
                                    let s = d ? Qt.formatDateTime(d, "ddd d MMM · hh:mm") : ""
                                    if (modelData.status === "stopped") s += " · " + i18n("stopped")
                                    else if (modelData.steps) s += " · " + i18n("%1 steps", modelData.steps)
                                    return s
                                }
                            }
                            Kirigami.SelectableLabel {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.italic: true
                                font.weight: Font.DemiBold
                                text: "› " + (modelData.prompt || "")
                            }
                            Kirigami.SelectableLabel {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: TextEdit.MarkdownText
                                color: modelData.error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                text: modelData.error ? "⚠ " + modelData.error : (modelData.text || "")
                            }
                            Kirigami.Separator { Layout.fillWidth: true; opacity: 0.4 }
                        }
                    }
                }
            }
        }
    }

    fullRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth: Kirigami.Units.gridUnit * 40
        Layout.fillWidth: true

        // Ask (read-only) or Assistant (acts, asking first).
        PC3.ToolButton {
            checkable: true
            checked: root.assistant
            icon.name: root.assistant ? "system-run" : "system-search"
            text: root.assistant ? i18n("Assistant") : i18n("Ask")
            display: PC3.AbstractButton.TextBesideIcon
            font.family: "JetBrains Mono"
            onClicked: root.setMode(root.assistant ? "ask" : "assistant")
            PC3.ToolTip.text: root.assistant
                ? i18n("Assistant: Claude acts for you, asking before any change. Click for read-only Ask.")
                : i18n("Ask: read-only, Claude looks and tells you what to run. Click to let it act.")
            PC3.ToolTip.visible: hovered
        }

        // A small mark that pulses while Claude works.
        Rectangle {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.6
            Layout.preferredHeight: width
            radius: width / 2
            color: root.run.status === "error" ? Kirigami.Theme.negativeTextColor
                                              : Kirigami.Theme.highlightColor
            opacity: root.run.status ? 0.9 : 0.35
            SequentialAnimation on opacity {
                running: root.busy
                loops: Animation.Infinite
                NumberAnimation { from: 0.25; to: 1; duration: 700 }
                NumberAnimation { from: 1; to: 0.25; duration: 700 }
            }
        }

        // Talk instead of typing (also Meta+Shift+Space, from anywhere).
        PC3.ToolButton {
            icon.name: "audio-input-microphone"
            checkable: true
            checked: root.listening
            display: PC3.AbstractButton.IconOnly
            text: i18n("Talk to Claude")
            onClicked: root.listening ? root.dismiss() : root.listen()
            PC3.ToolTip.text: root.listening ? i18n("Listening… click to stop") : i18n("Talk to Claude (Meta+Shift+Space)")
            PC3.ToolTip.visible: hovered
        }

        PC3.TextField {
            id: input
            Layout.fillWidth: true
            placeholderText: root.assistant ? i18n("Tell Claude what to do…   (Meta+Space)")
                                            : i18n("Ask Claude…   (Meta+Space)")
            Component.onCompleted: root.field = input
            font.family: "JetBrains Mono"
            onAccepted: { root.ask(text); text = ""; root.releaseFocus() }
            Keys.onEscapePressed: { text = ""; root.dismiss(); focus = false; root.releaseFocus() }
            onPressed: root.takeFocus()
            onActiveFocusChanged: if (!activeFocus) root.releaseFocus()
        }

        // The assistant's question lives in a pop-up under the bar (below);
        // here, only a small button that brings it back if it was closed.
        PC3.Button {
            id: askButton
            visible: !!root.pending
            text: i18n("⚑ Needs your OK")
            // The window may have been closed some other way (Esc, the
            // compositor), which breaks its binding: re-show it explicitly.
            onClicked: {
                root.laterQuestion = ""
                askDialog.visible = false
                askDialog.visible = Qt.binding(() => root.askOpen)
                askDialog.requestActivate()
            }
        }

        PC3.Label {
            visible: !root.pending
            Layout.maximumWidth: Kirigami.Units.gridUnit * 18
            elide: Text.ElideRight
            opacity: 0.8
            font.family: "JetBrains Mono"
            text: {
                const r = root.run
                if (r.status === "listening")
                    return i18n("listening…")
                if (r.status === "thinking") {
                    const s = r.steps || []
                    return s.length ? "▸ " + s[s.length - 1].name + "()" : i18n("thinking…")
                }
                if (r.status === "done")
                    return i18n("answered · %1 steps", (r.steps || []).length)
                if (r.status === "error")
                    return r.error || i18n("error")
                return ""
            }
        }

        // Read answers aloud.
        PC3.ToolButton {
            icon.name: root.speaking ? "audio-volume-high" : "audio-volume-muted"
            checkable: true
            checked: root.speaking
            display: PC3.AbstractButton.IconOnly
            text: root.speaking ? i18n("Answers are read aloud") : i18n("Read answers aloud")
            onClicked: root.setSpeak(!root.speaking)
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
        }

        PC3.ToolButton {
            icon.name: "view-history"
            checkable: true
            checked: root.historyOpen
            display: PC3.AbstractButton.IconOnly
            text: i18n("Earlier answers")
            onClicked: root.historyOpen = !root.historyOpen
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
        }

        PC3.ToolButton {
            visible: !!root.run.status
            icon.name: "window-close"
            display: PC3.AbstractButton.IconOnly
            text: i18n("Dismiss")
            onClicked: root.dismiss()
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
        }
    }
}
