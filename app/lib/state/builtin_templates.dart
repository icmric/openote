/// Built-in page templates (ORG-9).
///
/// The template feature shipped months before any content did, so a fresh
/// install showed an empty list — a working mechanism that looked broken.
/// These are plain data in the same `{page, blocks}` JSON the user-saved
/// templates use, so `applyTemplate` needs no second code path: built-ins are
/// merely entries that exist before the user saves anything.
///
/// Layout constants: the page is 1100 wide with content conventionally starting
/// at x=60; y values leave room for the title band. Text is the Markdown
/// dialect, so headings/checkboxes/tables render immediately.
library;

const Map<String, String> builtinTemplates = {
  'Meeting notes': '''
{"page":{"background":"ruled"},"blocks":[
 {"type":"text","x":60,"y":40,"w":480,"content":{"text":"# Meeting\\n\\n**Date:**  \\n**Attendees:** "}},
 {"type":"text","x":60,"y":190,"w":480,"content":{"text":"## Agenda\\n- "}},
 {"type":"text","x":60,"y":360,"w":480,"content":{"text":"## Notes\\n"}},
 {"type":"text","x":600,"y":190,"w":420,"content":{"text":"## Actions\\n- [ ] "}}
]}''',
  'Cornell notes': '''
{"page":{"background":"blank"},"blocks":[
 {"type":"text","x":60,"y":40,"w":960,"content":{"text":"# Topic\\n**Date:** "}},
 {"type":"text","x":60,"y":170,"w":280,"content":{"text":"## Cues\\n- "}},
 {"type":"text","x":380,"y":170,"w":640,"content":{"text":"## Notes\\n"}},
 {"type":"text","x":60,"y":620,"w":960,"content":{"text":"## Summary\\n"}}
]}''',
  'Weekly plan': '''
{"page":{"background":"grid"},"blocks":[
 {"type":"text","x":60,"y":40,"w":960,"content":{"text":"# Week of "}},
 {"type":"text","x":60,"y":150,"w":300,"content":{"text":"## Monday\\n- [ ] "}},
 {"type":"text","x":390,"y":150,"w":300,"content":{"text":"## Tuesday\\n- [ ] "}},
 {"type":"text","x":720,"y":150,"w":300,"content":{"text":"## Wednesday\\n- [ ] "}},
 {"type":"text","x":60,"y":400,"w":300,"content":{"text":"## Thursday\\n- [ ] "}},
 {"type":"text","x":390,"y":400,"w":300,"content":{"text":"## Friday\\n- [ ] "}},
 {"type":"text","x":720,"y":400,"w":300,"content":{"text":"## Weekend\\n- [ ] "}}
]}''',
  'Lecture notes': '''
{"page":{"background":"ruled"},"blocks":[
 {"type":"text","x":60,"y":40,"w":700,"content":{"text":"# Lecture\\n**Course:**  \\n**Date:** "}},
 {"type":"text","x":60,"y":200,"w":700,"content":{"text":"## Key points\\n- "}},
 {"type":"text","x":800,"y":200,"w":240,"content":{"text":"## Questions to answer later\\n- ","tags":[{"kind":"question","line":1}]}},
 {"type":"text","x":60,"y":560,"w":700,"content":{"text":"## Follow-up\\n- [ ] Review these notes\\n- [ ] "}}
]}''',
  'Revision sheet': '''
{"page":{"background":"blank"},"blocks":[
 {"type":"text","x":60,"y":40,"w":960,"content":{"text":"# Revision\\n**Topic:**  \\n**Exam:** "}},
 {"type":"text","x":60,"y":190,"w":460,"content":{"text":"## Definitions\\n","tags":[{"kind":"definition","line":1}]}},
 {"type":"flashcard","x":560,"y":190,"w":420,"h":170,"content":{"front":"","back":""}},
 {"type":"flashcard","x":560,"y":390,"w":420,"h":170,"content":{"front":"","back":""}},
 {"type":"text","x":60,"y":430,"w":460,"content":{"text":"## Still shaky on\\n- [ ] "}}
]}''',
  'Project kickoff': '''
{"page":{"background":"blank"},"blocks":[
 {"type":"text","x":60,"y":40,"w":960,"content":{"text":"# Project\\n**Owner:**  \\n**Target:** "}},
 {"type":"text","x":60,"y":190,"w":460,"content":{"text":"## Goals\\n- "}},
 {"type":"text","x":560,"y":190,"w":460,"content":{"text":"## Non-goals\\n- "}},
 {"type":"text","x":60,"y":420,"w":460,"content":{"text":"## Risks\\n- "}},
 {"type":"text","x":560,"y":420,"w":460,"content":{"text":"## Next steps\\n- [ ] "}}
]}''',
  'Math worksheet': '''
{"page":{"background":"grid"},"blocks":[
 {"type":"text","x":60,"y":40,"w":700,"content":{"text":"# Problem set\\n**Topic:** "}},
 {"type":"text","x":60,"y":170,"w":500,"content":{"text":"## Problem 1\\n"}},
 {"type":"math","x":90,"y":260,"w":320,"content":{"latex":"","linear":""}},
 {"type":"text","x":60,"y":400,"w":500,"content":{"text":"## Problem 2\\n"}},
 {"type":"math","x":90,"y":490,"w":320,"content":{"latex":"","linear":""}}
]}''',
};
