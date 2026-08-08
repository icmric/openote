# Eric's notes — what I want next

> Raw asks, in my own words. Nothing here is a spec; the plans in
> [`docs/planning/`](docs/planning/) are where these turn into work.
> **✅ marks what has since been built** — left in place rather than deleted so
> the original wording stays readable next to what it produced.

PDF/PPTX Thumbnail
    Id like to be able to import a file into my notebook, have a little thumbnail appear in my page with everything, but not have the whole thing always open
    I want to then be able to click it and open it all in a popup window or a side window. Means i can embed my lectures into the page to be able to quickly reference in the future and not have to flick between the notebook and browser

PDF Import
    We currently can import a PDF which is great, it locks in place which is what i want too. However it seems to import them as just a static image rather than the actual PDF. This is only important since id like to be able to highlight and copy text from within it, which isnt currently possible. 
    → Planned as storage wave 1c: store the PDF once and render pages on
      demand. Fixes this AND the thumbnail ask above AND the biggest single
      source of disk bloat, which is why it is next.
      See docs/planning/v0.10-responsiveness-and-storage.md §1.3.

Page Format
    By default everything should be infinite and pageless like it currently is, but id like the option to be able to work with pages (ideally being able to set the size too, default is A4, but also setting other metric and american sizes)

Flashcards
    Currently not intuitive how to use them, rather than using the tags, maybe we instead create a new thing in insert, so it inserts a flashcard element onto the page. This can be edited and used in place on the page without having to use the seperate tab, but still maintiang the option to see them all in the one place.

Calander and tasks
    It works currently, however is very limited. This would need a fairly significant UI rework as it would probaly need to replace the page entirley, but having the ability to have a trello like task board would be incredibly helpful for both students and product managers

Content
    Proper password protection for pages and sections

Storage and size
    Installer file size is quite a bit larger than expected (20-50mb depending on version), would like the total file size to be smaller as many students dont have much space on their laptops
    File sizes are still very large too for notebooks, media will always make it large but it still feels much larger than it should, please investigate optimising the file size and potentially compression to save space.

Cloud storage and saving
    Currently got syncing using pre installed cloud folders, works but feels a bit janky, fine for now though.
    For those more techincal, maybe we add git/github integration? Would need to all be automated by default as most people wont remeber to save and push changes
    Currently no real way to share a file or page with someone else, would like to address that
    In time, live editing (including cursor positions) would be awesome, although that will be quite complex and is not worth the effort at the moment.

Templates
    clicking on the button brings up a series of options, however clicking on any of these does nothing, even on a totally fresh page.

Page Linking
    We curerntly have a basic link system in place to link between pages which is fine, i would however like the ability to have a read-only version of one page visible inside another. I cant edit the other page through this, however edits made to this other page are visible later.

Inking
    Works, although id like it to auto detect when a pen is in proximity of the page and always assume to use it for inking rather than selecting (unless the user specifically selects another option)
    Pre mapped buttons on the pen also not registering, i have 2 buttons on my pen (many have more or less, or slightly different styles) but the idea is the same, pressing the button is configured in the os to do something (i.e. switch to eraser or whatever), this should be implemented

Navigation
    On touch screens, by default draging with a finger should pan around the page, it shouldnt be the selector tool.