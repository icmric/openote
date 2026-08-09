# Eric's notes — what I want next

> Raw asks, in my own words, **in priority order — top first**. Nothing here
> is a spec; the plans in [`docs/planning/`](docs/planning/) are where these
> turn into work. Done items are removed as they ship — CHANGELOG.md is the
> record of what landed and when.
>
> Removed as completed so far: page format (canvas + paged with real paper
> sizes), password protection, the storage/size overhaul, templates,
> git/GitHub sync with join-by-link, page linking + live page windows,
> finger-drag panning, and boxes stopping at the screen edge.

PDF Import
    We currently can import a PDF which is great, it locks in place which is what i want too. However it seems to import them as just a static image rather than the actual PDF. This is only important since id like to be able to highlight and copy text from within it, which isnt currently possible.
    → Planned as storage wave 1c: store the PDF once and render pages on
      demand. Fixes this AND the thumbnail ask below AND the biggest single
      source of disk bloat, which is why it is next.
      See docs/planning/v0.10-responsiveness-and-storage.md §1.3.

PDF/PPTX Thumbnail
    Id like to be able to import a file into my notebook, have a little thumbnail appear in my page with everything, but not have the whole thing always open
    I want to then be able to click it and open it all in a popup window or a side window. Means i can embed my lectures into the page to be able to quickly reference in the future and not have to flick between the notebook and browser
    → Same plan as PDF Import above — the stored-once PDF is what a
      thumbnail card and a popup viewer both render from.

Inking
    Works, although id like it to auto detect when a pen is in proximity of the page and always assume to use it for inking rather than selecting (unless the user specifically selects another option)
    Pre mapped buttons on the pen also not registering, i have 2 buttons on my pen (many have more or less, or slightly different styles) but the idea is the same, pressing the button is configured in the os to do something (i.e. switch to eraser or whatever), this should be implemented
    → Note: what a pen button reports is platform- and driver-dependent;
      Flutter surfaces a stylus "barrel button" flag but not arbitrary OS
      mappings, so the second half needs a capability check per platform.

Calander and tasks
    It works currently, however is very limited. This would need a fairly significant UI rework as it would probaly need to replace the page entirley, but having the ability to have a trello like task board would be incredibly helpful for both students and product managers

Cloud storage and saving
    Currently no real way to share a file or page with someone else, would like to address that
    In time, live editing (including cursor positions) would be awesome, although that will be quite complex and is not worth the effort at the moment.
