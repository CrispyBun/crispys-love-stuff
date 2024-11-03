# crispys löve stüff
This repo is just a place for me to dump all my [LÖVE](https://love2d.org/) related libraries which I didn't feel like making a standalone repo for.
They're usually less well written, not very well documented, but still open source. Some (usually incomplete) documentation is in the files themselves, but here's a basic rundown of some of the libraries:

## Marker
Marker is a library for making very dynamic and animated text in LÖVE. It's really not written in the prettiest way but it works.

The basic idea is that you don't have to define specific effects in a text programatically, instead you can define a "markedString" in the format of `"This text is [[shake:1]]shaking[[shake:none]]."`

The tags can be escaped with backslashes, the keywords to reset a tag are `none`, `unset`, and `/` (configurable), some effects take multiple comma separated arguments and more effects can be added.

The available tags are written out in a comment [near the start of the file](https://github.com/CrispyBun/crispys-love-stuff/blob/main/Libraries/marker.lua#L64).
