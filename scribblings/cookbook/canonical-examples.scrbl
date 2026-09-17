#lang scribble/manual

@(require racket/list
          racket/string
          "../../private/example-catalog.rkt")

@title[#:tag "cookbook-canonical-examples"]{Complete Example Programs}

The short Cookbook recipes are evaluated directly by Scribble. The programs
listed here are intentionally different: each is a complete repository example
whose file structure, assets, GUI use, media output, or external tools can be
part of the demonstration.

The executable catalogue drives maintained links and repository checks.
Requirements such as @tt{latex}, @tt{ffmpeg}, and @tt{gui} describe what is
needed to run the complete demonstration, not what is needed merely to require
the core library.

@itemlist[
@(for/list ([entry (in-list canonical-example-catalog)])
   @item{@bold[(example-entry-title entry)] —
         @filepath[(example-entry-source entry)]
         @italic{(@(string-join
                    (map symbol->string (example-entry-requirements entry))
                    ", "))}})]
