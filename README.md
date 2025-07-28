# crispys löve stüff
This repo is just a place for me to dump all my [LÖVE](https://love2d.org/) related libraries which I didn't feel like making a standalone repo for.
They're usually less well written, not very well documented, but still open source. Some (usually incomplete) documentation is in the files themselves, but here's a basic rundown of some of the libraries:

## Marker
Marker is a library for making very dynamic and animated text in LÖVE.

The basic idea is that you don't have to define specific effects in a text programatically, instead you can define a "MarkedString" in the format of `"This text is <shake amount='1'>shaking</shake>."`

There's a couple built-in effects (can be found in the `marker.registeredEffects` table) and more custom effects can be added (through `marker.registerEffect()`).

The `marker.textVariables` (global for all text) or `MarkedText.textVariables` (only for the specific text) tables are for variables that the text can dynamically show using the `<var ref='varname'/>` tag.
