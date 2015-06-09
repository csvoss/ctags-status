require 'atom'


findByIndentation = (editor, tagstart, tagindent, excludes=[]) ->
    # Guess tag end by assuming both start and end lines use same indent
    lastline = editor.getLastBufferRow()

    ended = false
    tagend = lastline
    for i in [tagstart + 1..lastline] when not ended
      text = editor.lineTextForBufferRow i
      if not text?
        # Skip when Atom cannot read any line from the Buffer
        continue

      trimmed = text.trim()
      if trimmed == ''
        # Blank line should not be considered as tag end line
        continue

      is_excluded = false
      if lineindent == tagindent
        for re in excludes when not is_excluded
          is_excluded = re.test(trimmed)

      if is_excluded
        continue

      lineindent = editor.indentationForBufferRow i

      if lineindent <= tagindent
        ended = true
        tagend = i - 1

    # Strip trailing blank lines
    while editor.lineTextForBufferRow(tagend).trim() == ''
      tagend = tagend - 1

    tagend


findByCloseCurly = (editor, tagstart, tagindent, excludes=[]) ->
    # Guess tag end by assuming end curly use same indent as that of tag
    lastline = editor.getLastBufferRow()

    ended = false
    tagend = lastline
    for i in [tagstart + 1..lastline] when not ended
      text = editor.lineTextForBufferRow i
      if not text?
        # Skip when Atom cannot read any line from the Buffer
        continue

      trimmed = text.trim()
      if trimmed == ''
        # Blank line should not be considered as tag end line
        continue

      lineindent = editor.indentationForBufferRow i

      if lineindent == tagindent && /^{.*/.test(trimmed)
        # Open curly should not be considered as tag end
        continue

      is_excluded = false
      if lineindent == tagindent
        for re in excludes when not is_excluded
          is_excluded = re.test(trimmed)

      if is_excluded
        continue

      if /^}/.test(trimmed)
        if lineindent == tagindent
          ended = true
          tagend = i  # Belongs to current scope
        else if lineindent < tagindent
          ended = true
          tagend = i - 1  # Belongs to outer scope
      else if lineindent <= tagindent
          ended = true
          tagend = i - 1  # End of scope without seeing close curly

    # Strip trailing blank lines
    while editor.lineTextForBufferRow(tagend).trim() == ''
      tagend = tagend - 1

    tagend


findByEndStmt = (editor, tagstart, tagindent, excludes=[]) ->
    # Guess tag end by assuming 'end' statement use same indent as that of tag
    lastline = editor.getLastBufferRow()

    ended = false
    tagend = lastline
    for i in [tagstart + 1..lastline] when not ended
      text = editor.lineTextForBufferRow i
      if not text?
        # Skip when Atom cannot read any line from the Buffer
        continue

      trimmed = text.trim()
      if trimmed == ''
        # Blank line should not be considered as tag end line
        continue

      lineindent = editor.indentationForBufferRow i

      is_excluded = false
      if lineindent == tagindent
        for re in excludes when not is_excluded
          is_excluded = re.test(trimmed)

      if is_excluded
        continue

      if /^end\s*/.test(trimmed)
        if lineindent == tagindent
          ended = true
          tagend = i
      else if lineindent <= tagindent
          ended = true
          tagend = i - 1  # End of scope without seeing end statement

    # Strip trailing blank lines
    while editor.lineTextForBufferRow(tagend).trim() == ''
      tagend = tagend - 1

    tagend


findCPPClose = (editor, tagstart, tagindent) ->
  excludes = [
    # Inheritance access control should be excluded as tag end
    /^(public|protected|private):\s*/
  ]
  findByCloseCurly(editor, tagstart, tagindent, excludes)


tagEndFinders =
  '.c': findCPPClose,
  '.cc': findCPPClose,
  '.coffee': findByCloseCurly,
  '.cpp': findCPPClose,
  '.css': findByCloseCurly,
  '.cxx': findCPPClose,
  '.c++': findCPPClose,
  '.go': findByCloseCurly,
  '.h': findCPPClose,
  '.hh': findCPPClose,
  '.hpp': findCPPClose,
  '.hxx': findCPPClose,
  '.h++': findCPPClose,
  '.java': findByCloseCurly,
  '.js': findByCloseCurly,
  '.php': findByCloseCurly,
  '.rb': findByEndStmt,
  '.py': findByIndentation,


class Finder
  constructor: (editor) ->
    @editor = editor
    matches = @editor.getPath().match(/(\.[a-zA-Z0-9]+)$/)
    if matches?
      @fileext = matches[1].toLowerCase()
    else
      @fileext = ''

  findScopeEnd: (tagstart, tagindent) ->
    findFunc = tagEndFinders[@fileext] || findByIndentation
    tagend = findFunc @editor, tagstart, tagindent

  scopeMapFrom: (tags) ->
    map = {}

    for info in tags  # tags sorted by tagstart ASC
      [tag, tagstart, tagend] = info
      for i in [tagstart..tagend]
        if not map[i]?
          map[i] = []
        map[i].push(tag)

    map

  getScopesFrom: (map) ->
    current = @editor.getCursorBufferPosition()
    scopes = map[current.row]
    if not scopes?
      return

    scopes  # Inner scope at last, refer to scopeMapFrom()


module.exports =
  on: (editor) ->
    new Finder(editor)
