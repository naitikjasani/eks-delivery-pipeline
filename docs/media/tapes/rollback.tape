# rollback.tape: records docs/media/rollback.gif (Act 3: broken release contained and rolled back) with vhs (https://github.com/charmbracelet/vhs).
# Recordings are scripted, so they can be regenerated after any change instead of re-recorded by hand.
# Run from the repository root with the kind cluster up:   vhs docs/media/tapes/rollback.tape
Output docs/media/rollback.gif

Require kind
Require kubectl

# Terminal look: readable font size, a dark theme, and a fixed size so the GIF renders crisply on GitHub.
Set Shell "bash"
Set FontSize 15
Set Width 1200
Set Height 720
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
# 10 frames per second, played back at 3x real time: keeps the GIF small while showing the whole act.
Set Framerate 10
Set PlaybackSpeed 3
Set WaitTimeout 8m

# Hidden setup: a short prompt and a clean screen.
Hide
Type "export PS1='\$ ' && clear"
Enter
Show

Type "FAST=1 make demo ACT=rollback"
Sleep 400ms
Enter
# This act is the heaviest (image build + kind load), and polling the screen with Wait made the headless browser
# drop its connection. A fixed Sleep covers the act (~2 min: build, 45 s rollout timeout, rollback) without polling.
Sleep 150s
