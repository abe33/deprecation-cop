{$, $$, ScrollView} = require 'atom'
path = require 'path'
_ = require 'underscore-plus'
fs = require 'fs-plus'
Grim = require 'grim'

module.exports =
class DeprecationCopView extends ScrollView
  @content: ->
    @div class: 'deprecation-cop pane-item native-key-bindings', tabindex: -1, =>
      @div class: 'panel', =>
        @div class: 'panel-heading', =>
          @div class: 'btn-toolbar pull-right', =>
            @div class: 'btn-group', =>
              @button outlet: 'refreshButton', class: 'btn refresh', 'Refresh'
          @span "Deprecated calls"
        @ul outlet: 'list', class: 'list-tree has-collapsable-children'

  initialize: ({@uri}) ->
    @subscribe Grim, 'updated', =>
      @refreshButton.show()

  afterAttach: ->
    @update()

    @subscribe @refreshButton, 'click', =>
      @update()

    @subscribe this, 'click', '.deprecation-info', ->
      $(this).parent().toggleClass('collapsed')

    @subscribe this, 'click', '.stack-line-location', ->
      pathToOpen = @href.replace('file://', '')
      pathToOpen = pathToOpen.replace(/^\//, '') if process.platform is 'win32'
      atom.open(pathsToOpen: [pathToOpen])

  destroy: ->
    @detach()

  serialize: ->
    deserializer: @constructor.name
    uri: @getUri()

  getUri: ->
    @uri

  getTitle: ->
    'Deprecation Cop'

  getIconName: ->
    'alert'

  getPackagePathsByPackageName: ->
    return @packagePathsByPackageName if @packagePathsByPackageName?

    @packagePathsByPackageName = {}
    for pack in atom.packages.getLoadedPackages()
      @packagePathsByPackageName[pack.name] = pack.path

    @packagePathsByPackageName

  getPackageName: (stack) ->
    resourcePath = atom.getLoadSettings().resourcePath
    {functionName, location, fileName} = stack[1]

    # Empty when it was run from the dev console
    return unless fileName

    for packageName, packagePath of @getPackagePathsByPackageName()
      relativePath = path.relative(packagePath, fileName)
      return packageName unless /^\.\./.test(relativePath)

  createIssueUrl: (packageName, deprecation, stack) ->
    return unless repo = atom.packages.getActivePackage(packageName)?.metadata?.repository
    repoUrl = repo.url ? repo
    repoUrl = repoUrl.replace(/\.git$/, '')

    title = "#{deprecation.getOriginName()} is deprecated."
    stacktrace = stack.map(({functionName, location}) -> "#{functionName} (#{location})").join("\n")
    body = "#{deprecation.getMessage()}\n```\n#{stacktrace}\n```"
    "#{repoUrl}/issues/new?title=#{encodeURI(title)}&body=#{encodeURI(body)}"

  update: ->
    @refreshButton.hide()
    deprecations = Grim.getDeprecations()
    deprecations.sort (a, b) -> b.getCallCount() - a.getCallCount()
    @list.empty()

    # I feel guilty about this nested code catastrophe
    if deprecations.length == 0
      @list.append $$ ->
        @li class: 'list-item', "No deprecated calls"
    else
      self = this
      for deprecation in deprecations
        @list.append $$ ->
          @li class: 'deprecation list-nested-item collapsed', =>
            @div class: 'deprecation-info list-item', =>
              @span class: 'text-highlight', deprecation.getOriginName()
              if deprecation.getCallCount() >= Grim.maxDeprecationCallCount()
                @span " (called more than #{deprecation.getCallCount()} times)"
              else
                @span " (called #{_.pluralize(deprecation.getCallCount(), 'time')})"

            @ul class: 'list', =>
              @li class: 'list-item', =>
                @div class: 'list-item text-success', deprecation.getMessage()

              stacks = deprecation.getStacks()
              stacks.sort (a, b) -> b.callCount - a.callCount
              for stack in stacks
                @li class: 'list-item', =>
                  @div class: 'btn-toolbar', =>
                    @span class: 'icon icon-alert'
                    if packageName = self.getPackageName(stack)
                      @span packageName + " package (called #{_.pluralize(stack.callCount, 'time')})"
                      if url = self.createIssueUrl(packageName, deprecation, stack)
                        @a href:url, "Create Issue on #{packageName} repo"
                    else
                      @span "atom core"  + " (called #{_.pluralize(stack.callCount, 'time')})"

                  @div class: 'stack-trace', =>
                    for {functionName, location, fileName} in stack
                      @div class: 'stack-line', =>
                        @span functionName
                        @span " - "
                        @a class:'stack-line-location', href:location, location
