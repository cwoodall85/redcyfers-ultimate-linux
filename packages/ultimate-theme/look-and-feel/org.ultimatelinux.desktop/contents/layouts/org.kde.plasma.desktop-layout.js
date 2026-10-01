// The Ultimate desktop, laid out on a user's first login: the standard
// bottom panel, the Claude bar across the top, the Cognition brain
// wallpaper, and the Ultimate widgets: a clock / CPU / memory / network /
// disk stack clipped together down the right edge, and the Claude tile on
// the left. They are ordinary desktop widgets: move them, drop them flush
// against each other (they share one width and the 16 px grid), or remove
// them.

loadTemplate("org.kde.plasma.desktop.defaultPanel");

// The application menu button shows the Ultimate Linux mark.
panels().forEach(function (p) {
    p.widgets("org.kde.plasma.kickoff").forEach(function (w) {
        w.currentConfigGroup = ["General"];
        w.writeConfig("icon", "ultimate-linux-mark");
    });
});

// The Claude bar: a thin panel across the top with the prompt in the
// middle. Meta+Space focuses it; Claude's work appears over the desktop.
var claudePanel = new Panel;
claudePanel.location = "top";
claudePanel.height = 40;
claudePanel.addWidget("org.kde.plasma.panelspacer");
var claudeBar = claudePanel.addWidget("org.ultimatelinux.claudebar");
claudeBar.globalShortcut = "Meta+Space";
claudePanel.addWidget("org.kde.plasma.panelspacer");

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    var d = desktopsArray[j];
    d.wallpaperPlugin = "org.ultimatelinux.cognition";
    var g = screenGeometry(d.screen);
    var W = 320, x = g.width - W - 40, y = 64;
    [["org.ultimatelinux.clock", 144], ["org.ultimatelinux.cpu", 176], ["org.ultimatelinux.memory", 96],
     ["org.ultimatelinux.network", 128], ["org.ultimatelinux.disk", 144]].forEach(function (t) {
        d.addWidget(t[0], x, y, W, t[1]);
        y += t[1];
    });
    d.addWidget("org.ultimatelinux.claude", 160, 64, 480, 560);
}
