# Silly Bus AI — install

A homework dashboard for a Brophy student's Mac. Everything runs locally;
nothing is uploaded anywhere.

Open Terminal and paste this:

```
curl -fsSL https://jomonkey22.github.io/schooldash-install/install.sh | bash
```

It installs to your own `~/Applications` folder and never asks for an
administrator password, which matters on a school Mac where you are not an
admin. The first launch takes a few minutes while it downloads what it needs,
then opens on the Setup screen — save your school Google sign-in there and
press Connect.

Rather not use Terminal? Download **SillyBusAI-Installer.dmg** from this repo
and read the READ ME FIRST inside; that route shows a Gatekeeper warning and
explains the one-time override.

This repo holds only the installer. Version 0.21.17.0.

- [`install.sh`](install.sh) — read it before you run it
- [`sillybus-chrome.zip`](sillybus-chrome.zip) — the optional Chrome
  extension. Unzip, then Chrome → `chrome://extensions` → Developer mode →
  Load unpacked. It lets the browser you are already signed in to hand your
  Canvas and Veracross pages to Silly Bus AI, instead of Silly Bus AI signing in
  itself.
- [`diagnose.sh`](diagnose.sh) — what a broken install reports
- [`uninstall.sh`](uninstall.sh) — removes it completely
