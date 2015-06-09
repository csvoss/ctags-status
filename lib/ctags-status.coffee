{CompositeDisposable} = require 'atom'

Q = null

Ctags = null
CtagsStatusView = null

Cache = null
Finder = null


module.exports = CtagsStatus =
  ctagsStatusView: null
  subscriptions: null

  config:
    ctagsTypes:
      title: 'Ctags type(s)'
      description: 'A list of CTags type(s) that could define a scope.'
      type: 'string'
      default: 'class,func,function,member,type,method,interface'
    statusbarPriority:
      title: 'Statusbar Priority'
      description: 'The priority of the scope name on the status bar.
                    Lower priority leans toward the side.'
      type: 'integer'
      default: 1
      minimum: -1
    cacheSize:
      title: 'Cache size'
      description: 'Number of slots to hold Ctags cache in memory.'
      type: 'integer'
      default: 8
      minimum: 1
    outerScope:
      title: 'Show outer scope(s)'
      description: 'Show all scope(s) on current line.'
      type: 'boolean'
      default: false


  activate: (state) ->
    Q ?= require 'q'

    Ctags ?= require './ctags'
    CtagsStatusView ?= require './ctags-status-view'

    Cache ?= require './cache'
    Finder ?= require './scope-finder'

    cache_size = atom.config.get('ctags-status.cacheSize')

    @cache = new Cache(cache_size)
    @ctags = new Ctags
    @ctagsStatusView = new CtagsStatusView(state.ctagsStatusViewState)

    @subscriptions = new CompositeDisposable

    # Register config monitors
    @subscriptions.add atom.config.onDidChange 'ctags-status.statusbarPriority',
    ({newValue, oldValue}) =>
      priority = newValue

      @ctagsStatusView.unmount()
      @ctagsStatusView.mount(@statusBar, priority)

    # Register command that toggles this view
    @subscriptions.add atom.workspace.observeActivePaneItem =>
      @unsubscribeLastActiveEditor()
      @subscribeToActiveEditor()
      @toggle()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      disposable = editor.onDidDestroy =>
        path = editor.getPath()

        if path?
          @cache.remove path

        disposable.dispose()

  deactivate: ->
    @unsubscribeLastActiveEditor()
    @subscriptions.dispose()

    @ctagsStatusView.destroy()
    @statusBar = null

    @cache.clear()
    @cache = null

    Q = null

    Ctags = null
    CtagsStatusView = null

    Cache = null
    Finder = null

  serialize: ->
    ctagsStatusViewState: @ctagsStatusView.serialize()

  consumeStatusBar: (statusBar) ->
    @statusBar = statusBar

    priority = atom.config.get('ctags-status.statusbarPriority')
    @ctagsStatusView.mount(@statusBar, priority)

  subscribeToActiveEditor: ->
    editor = atom.workspace.getActiveTextEditor()
    if not editor?
      return

    @editor_subscriptions = new CompositeDisposable

    @editor_subscriptions.add editor.onDidChangeCursorPosition (evt) =>
      last_pos = evt.oldBufferPosition
      this_pos = evt.newBufferPosition

      if last_pos.row == this_pos.row
        return

      @toggle()

    @editor_subscriptions.add editor.onDidSave =>
      @toggle(true)

  unsubscribeLastActiveEditor: ->
    if @editor_subscriptions?
      @editor_subscriptions.dispose()

    @editor_subscriptions = null

  toggle: (refresh=false) ->
    editor = atom.workspace.getActiveTextEditor()
    if not editor?
      @ctagsStatusView.clear()
      return

    path = editor.getPath()
    if not path?
      @ctagsStatusView.clear()
      return

    finder = Finder.on(editor)

    findScope = (map) =>
      scopes = finder.getScopesFrom map
      scopes = if not scopes? then ['global'] else scopes

      @ctagsStatusView.clear()
      show_outer = atom.config.get('ctags-status.outerScope')
      if show_outer
        for scope in scopes
          @ctagsStatusView.addText scope
      else
        @ctagsStatusView.addText scopes[scopes.length-1]

    if refresh or not @cache.has path
      # Always set a blank map to prevent Ctags failure / no tag is found.
      @cache.set path, {}

      deferred = Q.defer()

      disposable = editor.getBuffer().onDidDestroy ->
        deferred.reject()

      @ctags.generateTags path, (tags) ->
        deferred.resolve(tags)

      deferred.promise.fin ->
        disposable.dispose()

      deferred.promise.then (tags) =>
        filter = (tags) ->
          # Ignore un-interested tags
          # In: (Tags, Type, Start Line)
          # Out: (Tags, Start Line)
          do_ = (info) ->
            interested = atom.config.get('ctags-status.ctagsTypes')
            interested = interested.split(',')
            [tag, type, tagstart] = info

            if type not in interested
              return

            [tag, tagstart]

          (do_(info) for info in tags when info?)

        enrich = (tags) ->
          # Enrich tag info
          # In: (Tags, Start Line)
          # Out: (Tags, Start Line, Estimated End Line, Tag Indent)
          lastline = editor.getLastBufferRow()

          do_ = (info) ->
            [tag, tagstart] = info
            tagindent = editor.indentationForBufferRow tagstart

            # Set the last line as the default estimated end line of all tags.
            [tag, tagstart, lastline, tagindent]

          (do_(info) for info in tags when info?)

        transform = (tags) ->
          # Guess tag's end line
          # In: (Tags, Start Line, Estimated End Line, Tag Indent)
          # Out: (Tags, Start Line, Refined End Line)
          do_ = (info) ->
            [tag, tagstart, tagend, tagindent] = info
            tagend = finder.findScopeEnd tagstart, tagend, tagindent

            [tag, tagstart, tagend]

          (do_(info) for info in tags when info?)

        tags = transform(enrich(filter(tags)))
        map = finder.scopeMapFrom tags

        @cache.set path, map
        findScope map
    else
      map = @cache.get path
      findScope map
