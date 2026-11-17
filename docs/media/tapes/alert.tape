# alert.tape: records docs/media/alert.gif (Act 4: error traffic fires the HelloAppHighErrorRate alert) with vhs (https://github.com/charmbracelet/vhs).
# Recordings are scripted, so they can be regenerated after any change instead of re-recorded by hand.
# Run from the repository root with the kind cluster up:   vhs docs/media/tapes/alert.tape
Output docs/media/alert.gif

Require kind
Require kubectl

# Terminal look: readable font size, a dark theme, and a fixed size so the GIF renders crisply on GitHub.
Set Shell "bash"
Set FontSize 15
Set Width 1200
Set Height 560
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
# 10 frames per second, played back at 5x real time: keeps the GIF small while showing the whole act.
Set Framerate 10
Set PlaybackSpeed 5
Set WaitTimeout 8m

# Hidden setup: a short prompt and a clean screen.
Hide
Type "export PS1='\$ ' && clear"
Enter
Show

Type "FAST=1 make demo ACT=alert"
Sleep 400ms
Enter
# Wait until the demo prints its final banner, then hold the last frame for a moment.
Wait+Screen /━━━━ Done ━━━━/
Sleep 3s
