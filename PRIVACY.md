# Privacy

*Last updated 13 November 2026. The same text is published at
<https://openote.org/privacy>.*

## The app

The Openote desktop app does not collect, store or sell personal data. The
project runs no servers that receive information from the app, and the app
contains no analytics, advertising, crash reporting or account system.

Your notes are files on your own disk. They leave your computer only if you set
up a sync or backup location yourself, and then only to the place you chose.

### Connections the app makes

| When | Where to | What is sent |
|---|---|---|
| Each time the app starts | GitHub (`api.github.com`) | A request for the latest release, to see whether an update exists. GitHub receives your IP address and the app version, as with any web request. |
| You choose to install an update, or add the video player | GitHub (`github.com`) | A download request for the installer or player, checked against its published checksum before use. |
| You subscribe to a calendar | The address you enter | A request for that calendar. |
| You import from OneNote online | Microsoft (`login.microsoftonline.com`, Microsoft Graph) | The requests needed to read your notebooks. You sign in through your web browser, so your password is never entered into Openote. |
| You set up Git sync | The Git server you choose | Your notebook's change history, as Git normally does. |

The app makes no other connections. If you use a cloud folder such as Google
Drive, OneDrive or Dropbox for sync, that provider's own software moves the
files and its privacy policy applies.

The optional integration server for AI tools listens only on your own computer
(`127.0.0.1`) and is off unless you turn it on.

## This website

openote.org is hosted on Cloudflare. It sets no cookies and loads no third-party
scripts, fonts or trackers. Like any web host, Cloudflare handles each request, including
the visitor's IP address.

The download page normally learns the latest release through openote.org
itself, so your address is not passed on to GitHub for that. If that route is
unavailable it asks GitHub directly from your browser.

The in-browser demo at openote.org/demo counts page loads so that we can see
roughly how many people try it. Each load records the date, the visitor's
country, the referring site's name, the page requested, and a one-way code made
from the date, IP address and browser details. The code changes every day and
cannot be reversed, and the IP address itself is not stored. Nothing you type
into the demo is sent to us.

## Contact

Questions about this statement can be raised as an issue at
<https://github.com/icmric/openote/issues>. Changes to it are recorded in this
repository's history.
